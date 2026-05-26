import Foundation

@MainActor
class BumblebeeRunner: ObservableObject {
    @Published var isScanning = false
    @Published var summary = ScanSummary()
    @Published var statusMessage = ""
    @Published var error: String?
    @Published var hasResults = false

    private var currentProcess: Process?

    func scan(folder: URL, profile: ScanProfile) {
        guard !isScanning else { return }
        isScanning = true
        hasResults = false
        summary = ScanSummary()
        error = nil
        statusMessage = "Starting scan…"

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await self?.runScan(folder: folder, profile: profile)
            } catch {
                await MainActor.run {
                    self?.error = error.localizedDescription
                    self?.isScanning = false
                    self?.statusMessage = "Scan failed"
                }
            }
        }
    }

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
        isScanning = false
        statusMessage = "Cancelled"
    }

    // MARK: - Private

    private func runScan(folder: URL, profile: ScanProfile) async throws {
        let binaryURL = try Self.installedBinaryURL()
        let threatIntelPath = ThreatIntelUpdater.threatIntelDirectory().path

        var args = ["scan", "--profile", profile.rawValue, "--root", folder.path]
        if FileManager.default.fileExists(atPath: threatIntelPath) {
            args += ["--exposure-catalog", threatIntelPath]
        }

        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        await MainActor.run {
            self.currentProcess = proc
            self.statusMessage = "Scanning \(folder.lastPathComponent)…"
        }

        try proc.run()

        let outHandle = stdoutPipe.fileHandleForReading
        var textBuffer = ""

        while proc.isRunning {
            let chunk = outHandle.availableData
            if chunk.isEmpty {
                try await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            if let text = String(data: chunk, encoding: .utf8) {
                textBuffer += text
                await flushLines(from: &textBuffer)
            }
        }

        // drain remaining output
        let tail = outHandle.readDataToEndOfFile()
        if !tail.isEmpty, let text = String(data: tail, encoding: .utf8) {
            textBuffer += text
        }
        await flushLines(from: &textBuffer, force: true)

        let pkgCount = await MainActor.run { self.summary.packages.count }
        let fndCount = await MainActor.run { self.summary.findings.count }

        await MainActor.run {
            self.isScanning = false
            self.hasResults = true
            self.currentProcess = nil
            if fndCount > 0 {
                self.statusMessage = "\(fndCount) finding\(fndCount == 1 ? "" : "s") · \(pkgCount) package\(pkgCount == 1 ? "" : "s")"
            } else {
                self.statusMessage = "Clean — \(pkgCount) package\(pkgCount == 1 ? "" : "s") scanned, no findings"
            }
        }
    }

    private func flushLines(from buffer: inout String, force: Bool = false) async {
        var lines = buffer.components(separatedBy: "\n")
        // Keep the last fragment unless force-flushing
        let incomplete = force ? "" : (lines.removeLast())
        buffer = incomplete
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            await parseRecord(trimmed)
        }
    }

    private func parseRecord(_ line: String) async {
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
            let finding = ScanFinding(
                ecosystem:   json["ecosystem"] as? String ?? "unknown",
                packageName: json["package_name"] as? String ?? "unknown",
                version:     json["version"] as? String,
                severity:    json["severity"] as? String ?? "unknown",
                findingType: json["finding_type"] as? String,
                catalogName: json["catalog_name"] as? String,
                evidence:    evidenceStr
            )
            await MainActor.run { self.summary.findings.append(finding) }
        } else if json["package_name"] != nil {
            let pkg = ScanPackage(
                ecosystem:   json["ecosystem"] as? String ?? "unknown",
                packageName: json["package_name"] as? String ?? "unknown",
                version:     json["version"] as? String,
                sourceFile:  json["source_file"] as? String,
                confidence:  json["confidence"] as? String,
                projectPath: json["project_path"] as? String
            )
            await MainActor.run {
                self.summary.packages.append(pkg)
                let count = self.summary.packages.count
                self.statusMessage = "Scanning… \(count) package\(count == 1 ? "" : "s") found"
            }
        }
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
