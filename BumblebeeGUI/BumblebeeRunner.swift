import Foundation

@MainActor
class BumblebeeRunner: ObservableObject {
    @Published var isScanning = false
    @Published var summary = ScanSummary()
    @Published var statusMessage = ""
    @Published var error: String?
    @Published var hasResults = false
    @Published var scannedFolder: URL?
    @Published var scannedProfile: ScanProfile?

    private var currentProcess: Process?
    private var cancelled = false

    func scan(folder: URL, profile: ScanProfile) {
        guard !isScanning else { return }
        isScanning = true
        hasResults = false
        cancelled = false
        summary = ScanSummary()
        error = nil
        statusMessage = "Starting scan…"
        scannedFolder = folder
        scannedProfile = profile

        // Resolve paths on the main actor before going off-actor
        let binaryURL: URL
        do {
            binaryURL = try Self.installedBinaryURL()
        } catch {
            self.error = error.localizedDescription
            isScanning = false
            statusMessage = "Scan failed"
            return
        }

        var args = ["scan", "--profile", profile.rawValue, "--root", folder.path]
        let threatIntelPath = ThreatIntelUpdater.threatIntelDirectory().path
        if FileManager.default.fileExists(atPath: threatIntelPath) {
            args += ["--exposure-catalog", threatIntelPath]
        }

        statusMessage = "Scanning \(folder.lastPathComponent)…"

        // Run parsing off the main actor so it doesn't block the UI
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.runScan(binaryURL: binaryURL, args: args)
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isScanning = false
                    self.statusMessage = "Scan failed"
                }
            }
        }
    }

    func cancel() {
        cancelled = true
        currentProcess?.terminate()
        currentProcess = nil
        isScanning = false
    }

    // MARK: - Private

    // nonisolated: runs on a background thread, explicit MainActor.run for UI updates
    private nonisolated func runScan(binaryURL: URL, args: [String]) async throws {
        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        await MainActor.run { self.currentProcess = proc }

        try proc.run()

        let outHandle = stdoutPipe.fileHandleForReading
        var textBuffer = ""
        var pendingPackages: [ScanPackage] = []
        var pendingFindings: [ScanFinding] = []
        var lastFlush = Date()

        while proc.isRunning {
            let chunk = outHandle.availableData
            if chunk.isEmpty {
                // Flush batched results to UI every 250ms while idle
                if Date().timeIntervalSince(lastFlush) >= 0.25 {
                    let pkgs = pendingPackages
                    let fnds = pendingFindings
                    if !pkgs.isEmpty || !fnds.isEmpty {
                        pendingPackages = []
                        pendingFindings = []
                        lastFlush = Date()
                        await MainActor.run {
                            self.summary.packages.append(contentsOf: pkgs)
                            self.summary.findings.append(contentsOf: fnds)
                            let total = self.summary.packages.count
                            self.statusMessage = "Scanning… \(total) package\(total == 1 ? "" : "s") found"
                        }
                    }
                }
                try await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            if let text = String(data: chunk, encoding: .utf8) {
                textBuffer += text
                Self.flushLines(from: &textBuffer, packages: &pendingPackages, findings: &pendingFindings)
            }
        }

        // Drain remaining output
        let tail = outHandle.readDataToEndOfFile()
        if !tail.isEmpty, let text = String(data: tail, encoding: .utf8) {
            textBuffer += text
        }
        Self.flushLines(from: &textBuffer, packages: &pendingPackages, findings: &pendingFindings, force: true)

        // Final batch push to main actor
        let finalPkgs = pendingPackages
        let finalFnds = pendingFindings
        await MainActor.run {
            self.summary.packages.append(contentsOf: finalPkgs)
            self.summary.findings.append(contentsOf: finalFnds)

            let pkgCount = self.summary.packages.count
            let fndCount = self.summary.findings.count
            self.isScanning = false
            self.hasResults = pkgCount > 0 || fndCount > 0
            self.currentProcess = nil
            if self.cancelled {
                if fndCount > 0 {
                    self.statusMessage = "Scan cancelled — \(fndCount) finding\(fndCount == 1 ? "" : "s") in \(pkgCount) package\(pkgCount == 1 ? "" : "s") checked so far (incomplete)"
                } else {
                    self.statusMessage = "Scan cancelled — \(pkgCount) package\(pkgCount == 1 ? "" : "s") checked so far, no findings (incomplete)"
                }
            } else if fndCount > 0 {
                self.statusMessage = "\(fndCount) finding\(fndCount == 1 ? "" : "s") · \(pkgCount) package\(pkgCount == 1 ? "" : "s")"
            } else {
                self.statusMessage = "Clean — \(pkgCount) package\(pkgCount == 1 ? "" : "s") scanned, no findings"
            }
        }
    }

    // Synchronous, nonisolated static — no actor interaction, safe to call from background thread
    private nonisolated static func flushLines(
        from buffer: inout String,
        packages: inout [ScanPackage],
        findings: inout [ScanFinding],
        force: Bool = false
    ) {
        var lines = buffer.components(separatedBy: "\n")
        let incomplete = force ? "" : lines.removeLast()
        buffer = incomplete
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            parseRecord(trimmed, packages: &packages, findings: &findings)
        }
    }

    private nonisolated static func parseRecord(
        _ line: String,
        packages: inout [ScanPackage],
        findings: inout [ScanFinding]
    ) {
        guard
            let data = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let hasFindingFields = json["severity"] != nil || json["finding_type"] != nil

        if hasFindingFields {
            let evidenceDict = json["evidence"] as? [String: Any]
            let evidenceStr = evidenceDict.map { dict in
                dict.sorted(by: { $0.key < $1.key })
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "  ·  ")
            }
            findings.append(ScanFinding(
                ecosystem:   json["ecosystem"] as? String ?? "unknown",
                packageName: json["package_name"] as? String ?? "unknown",
                version:     json["version"] as? String,
                severity:    json["severity"] as? String ?? "unknown",
                findingType: json["finding_type"] as? String,
                catalogName: json["catalog_name"] as? String,
                evidence:    evidenceStr
            ))
        } else if json["package_name"] != nil {
            packages.append(ScanPackage(
                ecosystem:   json["ecosystem"] as? String ?? "unknown",
                packageName: json["package_name"] as? String ?? "unknown",
                version:     json["version"] as? String,
                sourceFile:  json["source_file"] as? String,
                confidence:  json["confidence"] as? String,
                projectPath: json["project_path"] as? String
            ))
        }
    }

    // MARK: - Cloud placeholder detection

    /// Counts files under `root` that exist only as cloud placeholders (SF_DATALESS).
    /// Uses stat() only — never triggers a download.
    static func countCloudPlaceholders(in root: URL) -> Int {
        let SF_DATALESS: UInt32 = 0x40000000
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var count = 0
        for case let url as URL in enumerator {
            var fileInfo = stat()
            if lstat(url.path, &fileInfo) == 0,
               (fileInfo.st_flags & SF_DATALESS) != 0 {
                count += 1
            }
        }
        return count
    }

    // MARK: - Binary management

    static func installedBinaryURL() throws -> URL {
        let dest = appSupportDir().appendingPathComponent("bumblebee")
        if !FileManager.default.fileExists(atPath: dest.path) {
            try installBinary(to: appSupportDir())
        }
        return dest
    }

    private static func installBinary(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let arch = currentArch()
        guard let src = Bundle.main.url(forResource: "bumblebee_\(arch)", withExtension: nil) else {
            throw BumblebeeError.binaryNotFound(arch: arch)
        }

        let dest = dir.appendingPathComponent("bumblebee")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: src, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }

    static func currentArch() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    private static func appSupportDir() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BumblebeeGUI")
    }
}

enum BumblebeeError: LocalizedError {
    case binaryNotFound(arch: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let arch):
            return "Bumblebee binary for \(arch) not found in app bundle. Run setup.sh first."
        }
    }
}
