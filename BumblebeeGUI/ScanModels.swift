import Foundation
import SwiftUI

enum ScanProfile: String, CaseIterable {
    case baseline, project, deep

    var displayName: String { rawValue.capitalized }

    var description: String {
        switch self {
        case .baseline: return "System package managers (pip, npm, gem…)"
        case .project:  return "Project dependencies in the selected folder"
        case .deep:     return "Deep scan — every file in the selected folder"
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
