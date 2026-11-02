#if DEBUG
import SwiftUI

enum PreviewPage: String, CaseIterable {
    case type
    case palette
    case components
    case dashboard
    case storm
    case night
    case settings
    case setup

    var title: String {
        switch self {
        case .type: "Type and spacing"
        case .palette: "Palette and scenes"
        case .components: "Components"
        case .dashboard: "Dashboard"
        case .storm: "Storm takeover"
        case .night: "Night dim"
        case .settings: "Settings"
        case .setup: "Setup"
        }
    }

    var defaultFocus: String? {
        switch self {
        case .type, .palette: nil
        case .components: "pane"
        case .dashboard, .night: "weather"
        case .storm: "alert"
        case .settings: "location"
        case .setup: "address"
        }
    }

    var next: PreviewPage {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Hidden design preview, opened with `-designPreview <page>`. Play/Pause steps through the pages.
/// `-scene`, `-previewFocus`, `-stormLayout` and `-setupState` pin a state for screenshots.
struct DesignPreviewView: View {
    @State private var page: PreviewPage
    @FocusState private var focus: String?
    private let scene: ScenePreset
    private let stormLayout: StormLayout
    private let setupState: SetupSampleState
    private let requestedFocus: String?
    @State private var dashboardModel: AppModel
    @State private var nightModel: AppModel

    init(page: PreviewPage, defaults: UserDefaults = .standard) {
        _page = State(initialValue: page)
        scene = ScenePreset.named(defaults.string(forKey: "scene")) ?? .golden
        stormLayout = StormLayout(rawValue: defaults.string(forKey: "stormLayout") ?? "") ?? .side
        setupState = SetupSampleState(rawValue: defaults.string(forKey: "setupState") ?? "") ?? .ok
        requestedFocus = defaults.string(forKey: "previewFocus")
        _dashboardModel = State(initialValue: PreviewDashboard.model(scene: scene, night: false))
        _nightModel = State(initialValue: PreviewDashboard.model(scene: .night, night: true))
    }

    var body: some View {
        pageView
            .id(page)
            .onPlayPauseCommand { page = page.next }
    }

    @ViewBuilder private var pageView: some View {
        switch page {
        case .dashboard:
            DashboardView(
                model: dashboardModel,
                initialFocus: PreviewDashboard.focus(for: requestedFocus),
                handlesDebugMenu: false
            )
        case .night:
            DashboardView(
                model: nightModel,
                initialFocus: PreviewDashboard.focus(for: requestedFocus),
                handlesDebugMenu: false
            )
        default:
            samplePage
        }
    }

    private var samplePage: some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if page.defaultFocus == nil || page == .components {
                    Text("Design preview: \(page.title). Play/Pause shows the next page.")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                        .padding(.trailing, Theme.Layout.marginHorizontal)
                        .padding(.bottom, 24)
                }
            }
            .defaultFocus($focus, initialFocus)
            .task(id: page) {
                // Lazy lists realize far rows late, so a second attempt reaches them.
                for delay in [400, 1200] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    if focus != initialFocus { focus = initialFocus }
                }
            }
    }

    private var initialFocus: String? {
        page == .components || page.defaultFocus != nil ? (requestedFocus ?? page.defaultFocus) : nil
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .type:
            TypePage()
        case .palette:
            PalettePage()
        case .components:
            ComponentsPage(focus: $focus)
        case .storm:
            StormSample(scene: .storm, layout: stormLayout, focus: $focus)
        case .settings:
            SettingsSample(scene: scene, focus: $focus, scrollTarget: requestedFocus)
        case .setup:
            SetupSample(scene: scene, state: setupState, focus: $focus)
        case .dashboard, .night:
            EmptyView()
        }
    }
}
#endif
