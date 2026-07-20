import Foundation
import XCTest
@testable import SessionDomain

final class PresentationSettingsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_752_000_000)

    private var identity: AgentSessionIdentity {
        AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("session-1"))
    }

    private func association(validity: HostContextValidity = .live) -> HostContextAssociation {
        HostContextAssociation(
            id: HostContextID("context-1"),
            sessionIdentity: identity,
            host: .iterm2,
            hostVersion: "3",
            integrationInstanceID: IntegrationInstanceID("instance-1"),
            integrationMode: "hooks",
            incarnation: HostIncarnation("incarnation-1"),
            locator: .iterm2LiveSession(sessionID: "live-session"),
            provenance: HostLocatorProvenance(host: .iterm2, evidence: .liveSessionAPI, observedAt: now),
            validity: validity,
            firstObservedAt: now,
            lastValidatedAt: validity == .live ? now : nil
        )
    }

    private func observation(
        association: HostContextAssociation,
        revalidated: Bool = true,
        directInspection: Bool = true,
        appOnly: Bool = false,
        locator: HostLocator? = nil
    ) -> ExactHostForegroundObservation {
        ExactHostForegroundObservation(
            sessionIdentity: identity,
            hostContextID: association.id,
            host: association.host,
            incarnation: association.incarnation,
            locator: locator ?? association.locator,
            revalidated: revalidated,
            directInspection: directInspection,
            appOnly: appOnly,
            observedAt: now
        )
    }

    func testExactForegroundRequiresCurrentOwningLiveContext() {
        let context = association()
        let policy = LocalPresentationPolicy.default
        XCTAssertEqual(policy.suppression(hasActiveSession: true, isFullScreen: false, foreground: observation(association: context), owningAssociation: context, candidate: identity), .exactOwningHostForeground)

        XCTAssertEqual(policy.suppression(hasActiveSession: true, isFullScreen: false, foreground: observation(association: context, revalidated: false), owningAssociation: context, candidate: identity), .none)
        XCTAssertEqual(policy.suppression(hasActiveSession: true, isFullScreen: false, foreground: observation(association: context, appOnly: true), owningAssociation: context, candidate: identity), .none)
        let historical = association(validity: .historical)
        XCTAssertEqual(policy.suppression(hasActiveSession: true, isFullScreen: false, foreground: observation(association: historical), owningAssociation: historical, candidate: identity), .none)
        XCTAssertEqual(policy.suppression(hasActiveSession: true, isFullScreen: false, foreground: observation(association: context, locator: .iterm2Tab(tabID: "nearby")), owningAssociation: context, candidate: identity), .none)
    }

    func testLocalPoliciesDoNotChangeCanonicalSessionState() {
        let policy = LocalPresentationPolicy(hideWhenNoActiveSession: true, hideInFullScreen: true, suppressWhenExactHostForeground: true)
        XCTAssertEqual(policy.suppression(hasActiveSession: false, isFullScreen: false), .noActiveSession)
        XCTAssertEqual(policy.suppression(hasActiveSession: true, isFullScreen: true), .fullScreen)
    }

    func testClickPolicyDisabledNeverNavigatesAndEnabledReportsAchievedLevel() {
        XCTAssertEqual(PresentationClickPolicy.resolve(action: .inspectExpand), .inspectedOrExpanded)
        XCTAssertEqual(PresentationClickPolicy.resolve(action: .jumpBack), .jumpBackUnavailable)
        let outcome = JumpBackOutcome(sessionIdentity: identity, host: .iterm2, qualifier: .workspaceOrFile, occurredAt: now, reason: .reachedFallback(from: .exactSurface, to: .workspaceOrFile), navigationPerformed: true)
        XCTAssertEqual(PresentationClickPolicy.resolve(action: .jumpBack, jumpBackOutcome: outcome), .jumpBackAchieved(.workspaceOrFile))
    }

    func testCustomRuleRequiresDocumentedGrammarAndNeverAcceptsBareURL() {
        XCTAssertEqual(HostDestinationPolicy.offer(host: .cursor, grammar: nil), .noCustomRule(lowerFallback: .appOnly))
        let bareURL = DocumentedHostDestinationGrammar(host: .cursor, identifier: "cursor://thread", documented: true)
        XCTAssertEqual(HostDestinationPolicy.offer(host: .cursor, grammar: bareURL), .noCustomRule(lowerFallback: .appOnly))
        let grammar = DocumentedHostDestinationGrammar(host: .cursor, identifier: "documented.workspace.file", documented: true)
        XCTAssertEqual(HostDestinationPolicy.offer(host: .cursor, grammar: grammar), .documentedRule(grammar))
    }
}
