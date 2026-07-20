import SwiftUI

/// Conventional Atlas navigation: a persistent grouped sidebar and one
/// independently scrolling detail pane. The shell owns no Overlay or Product
/// service, so selecting a destination cannot manufacture an external action.
struct AgentIslandSettingsView: View {
    @ObservedObject var model: AtlasSettingsModel
    @ObservedObject var notificationSettings: NotificationPolicySettingsModel
    @ObservedObject var usageSettings: UsageSettingsModel
    let liveDisplayControls: AnyView
    let cursorACPComposition: CursorACPApplicationComposition
    let iterm2HostControls: AnyView
    let warpHostControls: AnyView
    let orcaHostControls: AnyView

    var body: some View {
        NavigationSplitView {
            List(selection: destinationBinding) {
                ForEach(AtlasSettingsDestination.grouped, id: \.group) { group in
                    Section(group.group == .preferences ? "Preferences" : "Advanced") {
                        ForEach(group.destinations, id: \.self) { destination in
                            Label(destination.title, systemImage: destination.systemImage)
                                .tag(destination)
                                .accessibilityIdentifier("atlas.sidebar.\(destination.rawValue)")
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 270)
            .accessibilityLabel("Settings destinations")
        } detail: {
            ScrollView {
                AtlasSettingsDetail(
                    model: model,
                    notificationSettings: notificationSettings,
                    usageSettings: usageSettings,
                    destination: model.selectedDestination,
                    liveDisplayControls: liveDisplayControls,
                    cursorACPComposition: cursorACPComposition,
                    iterm2HostControls: iterm2HostControls,
                    warpHostControls: warpHostControls,
                    orcaHostControls: orcaHostControls
                )
                    .frame(maxWidth: 860, alignment: .topLeading)
                    .padding(24)
            }
            .scrollIndicators(.automatic)
            .accessibilityIdentifier("atlas.detail.\(model.selectedDestination.rawValue)")
            .navigationTitle(model.selectedDestination.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 520)
    }

    private var destinationBinding: Binding<AtlasSettingsDestination?> {
        Binding(
            get: { model.selectedDestination },
            set: { if let destination = $0 { model.select(destination) } }
        )
    }
}

private extension AtlasSettingsDestination {
    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .integrations: "point.3.connected.trianglepath.dotted"
        case .notifications: "bell"
        case .display: "display"
        case .sound: "speaker.wave.2"
        case .usage: "chart.bar"
        case .shortcuts: "command"
        case .labs: "flask"
        case .diagnostics: "stethoscope"
        case .maintenance: "wrench.and.screwdriver"
        }
    }
}
