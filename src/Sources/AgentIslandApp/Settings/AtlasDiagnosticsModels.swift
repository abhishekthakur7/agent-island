import Foundation
import SessionDomain

/// Settings-facing, allowlisted diagnostics model. SwiftUI can render this
/// value without receiving a SessionStore, Adapter, destination, or raw event.
public struct AtlasDiagnosticsModel: Codable, Equatable, Hashable, Sendable {
    public let evidence: [DiagnosticEvidence]
    public let bundleAvailable: Bool
    public let accessibilityLabel: String
    public let accessibilityHint: String

    public init(evidence: [DiagnosticEvidence] = [], bundleAvailable: Bool = true) {
        self.evidence = evidence
        self.bundleAvailable = bundleAvailable
        self.accessibilityLabel = "Redacted integration diagnostics, \(evidence.count) evidence records"
        self.accessibilityHint = bundleAvailable ? "Creates visible local Markdown and JSON artifacts after a person confirms the destination." : "Diagnostic Bundle is currently unavailable."
    }
}

public struct AtlasMaintenanceModel: Codable, Equatable, Hashable, Sendable {
    public let actions: [MaintenanceAccessibilityModel]

    public init() {
        self.actions = MaintenanceFlow.allCases.map(MaintenanceAccessibilityModel.init(flow:))
    }

    public func action(for flow: MaintenanceFlow) -> MaintenanceAccessibilityModel {
        actions.first { $0.title == flow.title } ?? MaintenanceAccessibilityModel(flow: flow)
    }
}

public enum AtlasDiagnosticAccessibility {
    public static func label(for evidence: DiagnosticEvidence) -> String {
        let capability = evidence.scope.capability.map { ", \($0.rawValue)" } ?? ""
        return "\(evidence.outcome.rawValue), \(evidence.reason.rawValue), \(evidence.scope.component.rawValue)\(capability)"
    }

    public static func hint(for evidence: DiagnosticEvidence) -> String {
        "Safe next step: \(evidence.safeNextStep.rawValue). Correlation is \(evidence.correlationID.value)."
    }
}
