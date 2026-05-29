import Foundation

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var defaultScanFolderPath: String? {
        didSet { UserDefaults.standard.set(defaultScanFolderPath, forKey: Keys.folderPath) }
    }
    @Published var defaultScanProfile: ScanProfile {
        didSet { UserDefaults.standard.set(defaultScanProfile.rawValue, forKey: Keys.profile) }
    }
    @Published var checkCloudFilesBeforeScanning: Bool {
        didSet { UserDefaults.standard.set(checkCloudFilesBeforeScanning, forKey: Keys.cloudCheck) }
    }

    var defaultScanFolder: URL? {
        get { defaultScanFolderPath.map { URL(fileURLWithPath: $0) } }
        set { defaultScanFolderPath = newValue?.path }
    }

    private enum Keys {
        static let folderPath = "defaultScanFolderPath"
        static let profile    = "defaultScanProfile"
        static let cloudCheck = "checkCloudFilesBeforeScanning"
    }

    private init() {
        let ud = UserDefaults.standard
        defaultScanFolderPath = ud.string(forKey: Keys.folderPath)
        defaultScanProfile = ScanProfile(rawValue: ud.string(forKey: Keys.profile) ?? "") ?? .project
        checkCloudFilesBeforeScanning = ud.object(forKey: Keys.cloudCheck) as? Bool ?? false
    }
}
