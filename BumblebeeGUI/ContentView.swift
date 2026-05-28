import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

struct ContentView: View {
    @StateObject private var runner  = BumblebeeRunner()
    @StateObject private var updater = ThreatIntelUpdater()
    @ObservedObject private var prefs = AppPreferences.shared

    @State private var selectedFolder: URL? = {
        guard let url = AppPreferences.shared.defaultScanFolder,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }()
    @State private var profile: ScanProfile = AppPreferences.shared.defaultScanProfile
    @State private var showPicker = false
    @State private var showExportError = false

    var body: some View {
        VStack(spacing: 0) {
            if updater.updateAvailable {
                UpdateBannerView(updater: updater)
            }

            // Folder selector — entire row is clickable
            Button(action: { showPicker = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    if let folder = selectedFolder {
                        Text(folder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.primary)
                    } else {
                        Text("Choose a folder to scan…")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Browse…")
                        .foregroundStyle(Color.accentColor)
                        .font(.callout)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(NSColor.controlBackgroundColor))
            .disabled(runner.isScanning)

            Divider()

            // Profile description
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(profile.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if runner.isScanning || runner.hasResults {
                ResultsView(
                    summary: runner.summary,
                    statusMessage: runner.statusMessage
                )
            } else {
                EmptyStateView(
                    canScan: selectedFolder != nil,
                    onSelectFolder: { showPicker = true },
                    onScan: {
                        guard let folder = selectedFolder else { return }
                        runner.scan(folder: folder, profile: profile, skipCloudCheck: !prefs.checkCloudFilesBeforeScanning)
                    }
                )
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .navigationTitle("Bumblebee")
        .onAppear { updater.setupOnLaunch() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    exportResults()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15))
                        Text("Save")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 68, height: 36)
                    .contentShape(Rectangle())
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .opacity(runner.hasResults ? 1 : 0.3)
                .disabled(!runner.hasResults)
                .keyboardShortcut("s", modifiers: .command)
                .help("Save scan results (⌘S)")

                ProfilePickerView(profile: $profile, isDisabled: runner.isScanning, isScanning: runner.isScanning)

                Button {
                    if runner.isScanning {
                        runner.cancel()
                    } else {
                        guard let folder = selectedFolder else { return }
                        runner.scan(folder: folder, profile: profile, skipCloudCheck: !prefs.checkCloudFilesBeforeScanning)
                    }
                } label: {
                    Image(systemName: runner.isScanning ? "stop.fill" : "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(runner.isScanning ? .red : .accentColor)
                .disabled(!runner.isScanning && selectedFolder == nil)
            }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                selectedFolder = urls.first
            }
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK") { }
        } message: {
            Text("The results could not be saved.")
        }
        .alert("Scan Error", isPresented: Binding(
            get: { runner.error != nil },
            set: { if !$0 { runner.error = nil } }
        )) {
            Button("OK") { runner.error = nil }
        } message: {
            Text(runner.error ?? "")
        }
        .alert("Files Not Available Locally", isPresented: Binding(
            get: { runner.pendingCloudScan != nil },
            set: { if !$0 { runner.cancelCloudWarning() } }
        )) {
            Button("Scan Anyway") { runner.proceedAfterCloudWarning() }
            Button("Cancel", role: .cancel) { runner.cancelCloudWarning() }
        } message: {
            if let pending = runner.pendingCloudScan {
                let n = pending.count
                Text("\(n) file\(n == 1 ? "" : "s") in this folder \(n == 1 ? "is" : "are") stored in the cloud and not available locally. Scanning will trigger downloads, which may be significantly slower than usual.")
            }
        }
    }

    // MARK: - Export

    private func exportResults() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "bumblebee-scan.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let markdown = runner.summary.markdownReport(
                folder: runner.scannedFolder,
                profile: runner.scannedProfile
            )
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                showExportError = true
            }
        }
    }
}

// MARK: - Profile picker

struct ProfilePickerView: View {
    @Binding var profile: ScanProfile
    let isDisabled: Bool
    let isScanning: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ScanProfile.allCases, id: \.self) { p in
                Button(action: { profile = p }) {
                    VStack(spacing: 3) {
                        Image(systemName: p.icon)
                            .font(.system(size: 15))
                            .symbolEffect(
                                .variableColor.cumulative.nonReversing,
                                options: .repeating,
                                isActive: isScanning && profile == p
                            )
                        Text(p.displayName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 68, height: 36)
                    .contentShape(Rectangle())
                    .background(
                        profile == p
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
        .padding(2)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - Update banner

struct UpdateBannerView: View {
    @ObservedObject var updater: ThreatIntelUpdater

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
            Text("Threat intelligence update available")
                .font(.callout)
            if let v = updater.latestVersion {
                Text("(\(v))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if updater.isUpdating {
                ProgressView().scaleEffect(0.75)
                Text("Updating…").font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Update Now") {
                    Task { await updater.applyUpdate() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Dismiss") { updater.updateAvailable = false }
                    .controlSize(.small)
            }
            if let err = updater.updateError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.08))
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let canScan: Bool
    let onSelectFolder: () -> Void
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            HStack(spacing: 0) {
                Button("Select a folder") { onSelectFolder() }
                    .buttonStyle(.link)
                Text(" and click ")
                    .foregroundStyle(.secondary)
                Button("Scan") { onScan() }
                    .buttonStyle(.link)
                    .disabled(!canScan)
            }
            .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Results

struct ResultsView: View {
    let summary: ScanSummary
    let statusMessage: String

    @State private var expandedEcosystems: Set<String> = []
    @State private var ecosystemSearch: [String: String] = [:]

    // Render at most this many package rows per ecosystem at once.
    // Large ecosystems get a filter field instead of a 10,000-row list.
    private let maxVisible = 100

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if !summary.findings.isEmpty {
                    Label(
                        "\(summary.findings.count) finding\(summary.findings.count == 1 ? "" : "s")",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout.bold())
                    .foregroundStyle(.orange)
                }
                if !summary.packages.isEmpty {
                    Text("·").foregroundStyle(.secondary)
                    Text("\(summary.packages.count) package\(summary.packages.count == 1 ? "" : "s")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // List virtualises rows — only visible rows exist in memory,
            // so expanding a 9,000-package ecosystem stays responsive.
            List {
                if !summary.findings.isEmpty {
                    Section {
                        ForEach(summary.sortedFindings) { finding in
                            FindingRowView(finding: finding)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        SectionHeaderView(
                            icon: "exclamationmark.triangle.fill",
                            title: "Findings",
                            count: summary.findings.count,
                            iconColor: .orange
                        )
                    }
                }

                if !summary.packages.isEmpty {
                    Section {
                        ForEach(summary.packagesByEcosystem.keys.sorted(), id: \.self) { eco in
                            ecosystemRow(eco)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        SectionHeaderView(
                            icon: "shippingbox.fill",
                            title: "Packages",
                            count: summary.packages.count,
                            iconColor: .blue
                        )
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    @ViewBuilder
    private func ecosystemRow(_ eco: String) -> some View {
        let packages  = summary.packagesByEcosystem[eco] ?? []
        let query     = ecosystemSearch[eco, default: ""]
        let filtered  = query.isEmpty
            ? packages
            : packages.filter { $0.packageName.localizedCaseInsensitiveContains(query) }
        let shown     = Array(filtered.prefix(maxVisible))
        let isLarge   = packages.count > maxVisible

        EcosystemGroupView(
            ecosystem: eco,
            packages: packages,
            shown: shown,
            isLarge: isLarge,
            filteredCount: filtered.count,
            maxVisible: maxVisible,
            isExpanded: expandedBinding(eco),
            searchText: searchBinding(eco)
        )
    }

    private func expandedBinding(_ eco: String) -> Binding<Bool> {
        Binding(
            get: { expandedEcosystems.contains(eco) },
            set: { if $0 { expandedEcosystems.insert(eco) } else { expandedEcosystems.remove(eco) } }
        )
    }

    private func searchBinding(_ eco: String) -> Binding<String> {
        Binding(
            get: { ecosystemSearch[eco, default: ""] },
            set: { ecosystemSearch[eco] = $0 }
        )
    }
}

struct SectionHeaderView: View {
    let icon: String
    let title: String
    let count: Int
    let iconColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(iconColor)
            Text(title).font(.headline)
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(NSColor.quaternarySystemFill))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Finding row

struct FindingRowView: View {
    let finding: ScanFinding
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                SeverityBadgeView(severity: finding.severity, color: finding.severityColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(finding.packageName)
                            .font(.body.bold())
                        if let v = finding.version {
                            Text(v)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(finding.ecosystem)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let cat = finding.catalogName {
                            Text("·").foregroundStyle(.tertiary)
                            Text(cat).font(.caption).foregroundStyle(.secondary)
                        }
                        if let type = finding.findingType {
                            Text("·").foregroundStyle(.tertiary)
                            Text(type).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if finding.evidence != nil {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 9)

            if isExpanded, let evidence = finding.evidence {
                Text(evidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.leading, 42)
                    .padding(.bottom, 8)
                    .textSelection(.enabled)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if finding.evidence != nil { isExpanded.toggle() } }
    }
}

struct SeverityBadgeView: View {
    let severity: String
    let color: Color

    var body: some View {
        Text(severity.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 58)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Ecosystem group

struct EcosystemGroupView: View {
    let ecosystem: String
    let packages: [ScanPackage]   // full list (for the header count)
    let shown: [ScanPackage]      // pre-filtered & capped slice to render
    let isLarge: Bool
    let filteredCount: Int
    let maxVisible: Int
    @Binding var isExpanded: Bool
    @Binding var searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(ecosystem)
                        .font(.callout.bold())
                    Text("\(packages.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Filter field — shown for any ecosystem over the cap
                if isLarge {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(.secondary)
                        TextField("Filter \(ecosystem) packages…", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }

                // Package rows — capped at maxVisible
                ForEach(shown) { pkg in
                    PackageRowView(package: pkg)
                    Divider().padding(.leading, 32)
                }

                // Cap / filter hint
                if filteredCount > maxVisible {
                    HStack {
                        Spacer()
                        Text(
                            searchText.isEmpty
                                ? "Showing \(maxVisible) of \(filteredCount) — filter to narrow results"
                                : "\(shown.count) of \(filteredCount) matching"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                } else if !searchText.isEmpty && shown.isEmpty {
                    Text("No packages matching \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                }
            }
        }
    }
}

struct PackageRowView: View {
    let package: ScanPackage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(package.packageName)
                        .font(.callout)
                    if let v = package.version {
                        Text(v)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let file = package.sourceFile {
                    Text(file)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if let conf = package.confidence, conf != "high" {
                let (heading, label, tip): (String, String, String) = conf == "medium"
                    ? ("medium confidence", "package version inferred",  "Version was inferred from a spec or tag, not confirmed by a lockfile or installed metadata")
                    : ("low confidence",    "package version uncertain", "Detected from a config reference only — not confirmed as actually installed")
                VStack(alignment: .trailing, spacing: 1) {
                    Text(heading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.trailing)
                .help(tip)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
    }
}
