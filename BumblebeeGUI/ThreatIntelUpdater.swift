import Foundation

private struct GitHubCommit: Decodable {
    let sha: String
}

@MainActor
class ThreatIntelUpdater: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String?  // holds the latest commit SHA
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var updateError: String?
    @Published var showUpToDate = false

    private let versionKey = "installedThreatIntelCommitSHA"

    // The repo tarball URL for the main branch
    private let repoTarballURL = URL(string: "https://api.github.com/repos/perplexityai/bumblebee/tarball/main")!

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
            if FileManager.default.fileExists(atPath: Self.threatIntelDirectory().path) {
                await checkForUpdates()
            } else {
                await firstInstall()
            }
        }
    }

    func checkForUpdates() async {
        isChecking = true
        showUpToDate = false
        updateError = nil
        defer { isChecking = false }

        // Keep spinning for at least one full rotation so the animation is visible
        async let minimumDelay: () = Task.sleep(nanoseconds: 1_000_000_000)

        do {
            let sha = try await fetchLatestThreatIntelCommitSHA()
            _ = await minimumDelay
            latestVersion = sha
            if sha != (installedVersion ?? "") {
                updateAvailable = true
            } else {
                showUpToDate = true
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    showUpToDate = false
                }
            }
        } catch {
            _ = await minimumDelay
            // Silently ignore update check failures (network may be unavailable)
            print("Threat intel update check failed: \(error)")
        }
    }

    func applyUpdate() async {
        guard let sha = latestVersion else { return }
        isUpdating = true
        updateError = nil

        do {
            try await downloadAndInstall()
            UserDefaults.standard.set(sha, forKey: versionKey)
            updateAvailable = false
        } catch {
            updateError = error.localizedDescription
        }

        isUpdating = false
    }

    // MARK: - Private

    // On first launch: try to fetch the latest from GitHub; fall back to the bundled copy if offline.
    private func firstInstall() async {
        isUpdating = true
        defer { isUpdating = false }

        do {
            let sha = try await fetchLatestThreatIntelCommitSHA()
            try await downloadAndInstall()
            UserDefaults.standard.set(sha, forKey: versionKey)
        } catch {
            print("First-launch GitHub fetch failed, falling back to bundled copy: \(error)")
            installBundledCopy()
        }
    }

    private func installBundledCopy() {
        guard let src = Bundle.main.url(forResource: "threat_intel", withExtension: nil) else { return }
        let dest = Self.threatIntelDirectory()
        do {
            let parent = dest.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: src, to: dest)
        } catch {
            print("Failed to install bundled threat intel: \(error)")
        }
    }

    // Returns the SHA of the latest commit that touched the threat_intel/ path.
    private func fetchLatestThreatIntelCommitSHA() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/perplexityai/bumblebee/commits?path=threat_intel&per_page=1")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        let commits = try JSONDecoder().decode([GitHubCommit].self, from: data)
        guard let first = commits.first else { throw UpdateError.noCommitsFound }
        return first.sha
    }

    // Downloads the main branch tarball and extracts threat_intel/ from it.
    private func downloadAndInstall() async throws {
        var req = URLRequest(url: repoTarballURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (tmpURL, _) = try await URLSession.shared.download(for: req)
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
        case noCommitsFound, extractionFailed, threatIntelNotFound

        var errorDescription: String? {
            switch self {
            case .noCommitsFound:      return "No commits found for threat_intel on GitHub"
            case .extractionFailed:    return "Failed to extract the repository archive"
            case .threatIntelNotFound: return "threat_intel directory not found in repository archive"
            }
        }
    }
}
