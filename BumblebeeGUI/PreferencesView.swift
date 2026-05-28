import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var showFolderPicker = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    if let folder = prefs.defaultScanFolder {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(folder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Clear") { prefs.defaultScanFolder = nil }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("None")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Button("Choose…") { showFolderPicker = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Default Scan Folder")
            } footer: {
                Text("Pre-selected when the app launches. You can always pick a different folder before scanning.")
            }

            Section {
                Picker("", selection: $prefs.defaultScanProfile) {
                    ForEach(ScanProfile.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(prefs.defaultScanProfile.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Default Scan Type")
            }

            Section {
                Toggle("Check for cloud files before scanning", isOn: $prefs.checkCloudFilesBeforeScanning)
            } header: {
                Text("Cloud Files")
            } footer: {
                Text("When enabled, Bumblebee checks for iCloud and Dropbox placeholder files before scanning. Undownloaded files trigger automatic downloads, which can make scans significantly slower.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                prefs.defaultScanFolder = urls.first
            }
        }
    }
}
