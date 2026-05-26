import Foundation
import SwiftUI

enum ScanProfile: String, CaseIterable {
    case project, baseline, deep

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .project:  return "document.viewfinder.fill"
        case .baseline: return "square.stack.fill"
        case .deep:     return "square.3.layers.3d.bottom.filled"
        }
    }

    var description: String {
        switch self {
        case .baseline: return "Scans system-wide package managers (pip, npm, Homebrew, gem…). Folder selection is optional."
        case .project:  return "Scans dependency manifests in the selected folder — package.json, requirements.txt, go.mod, Gemfile, etc."
        case .deep:     return "Recursively walks every file in the selected folder. Most thorough, but slowest."
        }
    }
}

struct ScanPackage: Identifiable {
    let id = UUID()
    let ecosystem: String
    let packageName: String
    let version: String?
    let sourceFile: String?
    let confidence: String?
    let projectPath: String?
}

struct ScanFinding: Identifiable {
    let id = UUID()
    let ecosystem: String
    let packageName: String
    let version: String?
    let severity: String
    let findingType: String?
    let catalogName: String?
    let evidence: String?

    var severityRank: Int {
        switch severity.lowercased() {
        case "critical": return 4
        case "high":     return 3
        case "medium":   return 2
        case "low":      return 1
        default:         return 0
        }
    }

    var severityColor: Color {
        switch severity.lowercased() {
        case "critical": return .red
        case "high":     return .orange
        case "medium":   return Color(red: 0.85, green: 0.65, blue: 0.0)
        case "low":      return .blue
        default:         return .secondary
        }
    }
}

struct ScanSummary {
    var packages: [ScanPackage] = []
    var findings: [ScanFinding] = []

    var packagesByEcosystem: [String: [ScanPackage]] {
        Dictionary(grouping: packages, by: \.ecosystem)
    }

    var sortedFindings: [ScanFinding] {
        findings.sorted { $0.severityRank > $1.severityRank }
    }
}
