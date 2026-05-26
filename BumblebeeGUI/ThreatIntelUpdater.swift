import Foundation

private struct GitHubRelease: Decodable {
    let tagName: String
    let publishedAt: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

@MainActor
class ThreatIntelUpdater: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var updateError: String?

    private let versionKey = "installedThreatIntelVersion"

    var installedVersion: String? {
        UserDefaults.standard.string(forKey: versionKey)
    }

    static func threatIntelDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BumblebeeGUI/threat_intel")
    }

    func setupOnLaunch() {
        Task {
            installBundledIfNeeded()
            await checkForUpdates()
        }
    }

    func checkForUpdates() async {
        isChecking = true
        updateError = nil
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            latestVersion = release.tagName
            updateAvailable = release.tagName != (installedVersion ?? "")
        } catch {
            // Silently ignore update check failures (network may be unavailable)
            print("Threat intel update check failed: \(error)")
        }
    }

    func applyUpdate() async {
        guard let version = latestVersion else { return }
        isUpdating = true
        updateError = nil

        do {
            let release = try await fetchLatestRelease()
            try await downloadAndInstall(release: release)
            UserDefaults.standard.set(version, forKey: versionKey)
            updateAvailable = false
        } catch {
            updateError = error.localizedDescription
        }

        isUpdating = false
    }

    // MARK: - Private

    private func installBundledIfNeeded() {
        let dest = Self.threatIntelDirectory()
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }

        guard let src = Bundle.main.url(forResource: "threat_intel", withExtension: nil) else {
            return
        }

        do {
            let parent = dest.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: src, to: dest)
        } catch {
            print("Failed to install bundled threat intel: \(error)")
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/perplexityai/bumblebee/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func downloadAndInstall(release: GitHubRelease) async throws {
        // Pick a darwin tarball — arm64 preferred, any darwin as fallback
        let preferredArch = BumblebeeRunner.currentArch() == "arm64" ? "arm64" : "amd64"
        guard let asset = release.assets.first(where: {
            $0.name.contains("darwin") && $0.name.contains(preferredArch) && $0.name.hasSuffix(".tar.gz")
        }) ?? release.assets.first(where: {
            $0.name.contains("darwin") && $0.name.hasSuffix(".tar.gz")
        }) else {
            throw UpdateError.noSuitableAsset
        }

        let (tmpURL, _) = try await URLSession.shared.download(from: URL(string: asset.browserDownloadURL)!)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        try await extractThreatIntel(from: tmpURL)
    }

    private func extractThreatIntel(from tarball: URL) async throws {
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractDir) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["-xzf", tarball.path, "-C", extractDir.path]
        try proc.run()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            throw UpdateError.extractionFailed
        }

        // Find threat_intel/ inside the extracted tree
        var threatIntelSrc: URL?
        if let enumerator = FileManager.default.enumerator(
            at: extractDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) {
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent == "threat_intel",
                   (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    threatIntelSrc = url
                    break
                }
            }
        }

        guard let src = threatIntelSrc else {
            throw UpdateError.threatIntelNotFound
        }

        let dest = Self.threatIntelDirectory()
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: src, to: dest)
    }

    enum UpdateError: LocalizedError {
        case noSuitableAsset, extractionFailed, threatIntelNotFound

        var errorDescription: String? {
            switch self {
            case .noSuitableAsset:    return "No darwin release asset found on GitHub"
            case .extractionFailed:   return "Failed to extract the release archive"
            case .threatIntelNotFound: return "threat_intel directory not found in release archive"
            }
        }
    }
}
