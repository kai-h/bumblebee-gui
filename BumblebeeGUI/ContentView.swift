import SwiftUI

// MARK: - Root

struct ContentView: View {
    @StateObject private var runner  = BumblebeeRunner()
    @StateObject private var updater = ThreatIntelUpdater()

    @State private var selectedFolder: URL?
    @State private var profile: ScanProfile = .project
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if updater.updateAvailable {
                UpdateBannerView(updater: updater)
            }

            ScanControlsView(
                selectedFolder: $selectedFolder,
                profile: $profile,
                showPicker: $showPicker,
                runner: runner
            )

            Divider()

            if runner.isScanning || runner.hasResults {
                ResultsView(
                    summary: runner.summary,
                    statusMessage: runner.statusMessage
                )
            } else {
                EmptyStateView()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { updater.setupOnLaunch() }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                selectedFolder = urls.first
            }
        }
        .alert("Scan Error", isPresented: Binding(
            get: { runner.error != nil },
            set: { if !$0 { runner.error = nil } }
        )) {
            Button("OK") { runner.error = nil }
        } message: {
            Text(runner.error ?? "")
        }
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

// MARK: - Scan controls

struct ScanControlsView: View {
    @Binding var selectedFolder: URL?
    @Binding var profile: ScanProfile
    @Binding var showPicker: Bool
    @ObservedObject var runner: BumblebeeRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Folder target
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    if let folder = selectedFolder {
                        Text(folder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Choose a folder to scan…")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Browse…") { showPicker = true }
                        .controlSize(.small)
                }
                .padding(7)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .frame(maxWidth: .infinity)
                .disabled(runner.isScanning)

                // Profile picker
                Picker("Profile", selection: $profile) {
                    ForEach(ScanProfile.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .disabled(runner.isScanning)

                // Action button
                if runner.isScanning {
                    Button(role: .destructive, action: runner.cancel) {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .controlSize(.large)
                } else {
                    Button {
                        guard let folder = selectedFolder else { return }
                        runner.scan(folder: folder, profile: profile)
                    } label: {
                        Label("Scan", systemImage: "magnifyingglass.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedFolder == nil)
                }
            }

            // Profile description — visible beneath the controls row
            Text(profile.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
                .animation(.none, value: profile)
        }
        .padding()
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Select a folder and click Scan")
                .foregroundStyle(.secondary)
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
                Text(conf)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
    }
}
