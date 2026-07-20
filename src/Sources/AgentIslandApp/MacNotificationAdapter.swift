import Foundation
import UserNotifications
import SessionDomain

/// Small AppKit-shell adapter.  It only receives the bounded state/label
/// facet, never an Attention Request or Product action.
@MainActor
public final class MacNotificationAdapter: NSObject {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func permissionState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    @discardableResult
    public func requestPermission() async -> NotificationPermissionState {
        do { _ = try await center.requestAuthorization(options: [.alert, .sound]); return await permissionState() }
        catch { return .denied }
    }

    @discardableResult
    public func post(_ facet: NotificationBannerFacet) async -> Bool {
        guard await permissionState() == .granted else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Agent Island"
        content.subtitle = facet.state.rawValue
        // The label is bounded and already secret-scrubbed by SessionDomain.
        content.body = facet.label ?? facet.state.rawValue
        content.sound = nil
        let request = UNNotificationRequest(identifier: "agent-island.\(facet.candidateID.description)", content: content, trigger: nil)
        do { try await center.add(request); return true }
        catch { return false }
    }

    public func remove(_ candidateID: AlertCandidateID) {
        center.removeDeliveredNotifications(withIdentifiers: ["agent-island.\(candidateID.description)"])
        center.removePendingNotificationRequests(withIdentifiers: ["agent-island.\(candidateID.description)"])
    }
}

public typealias MacOSNotificationAdapter = MacNotificationAdapter

