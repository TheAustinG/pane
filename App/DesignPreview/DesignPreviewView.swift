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

    init(page: PreviewPage, defaults: UserDefaults = .standard) {
        _page = State(initialValue: page)
        scene = ScenePreset.named(defaults.string(forKey: "scene")) ?? .golden
        stormLayout = StormLayout(rawValue: defaults.string(forKey: "stormLayout") ?? "") ?? .side
        setupState = SetupSampleState(rawValue: defaults.string(forKey: "setupState") ?? "") ?? .ok
        requestedFocus = defaults.string(forKey: "previewFocus")
    }

    var body: some View {
        content
            .id(page)
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
            .onPlayPauseCommand { page = page.next }
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
        case .dashboard:
            DashboardSample(scene: scene, focus: $focus)
        case .storm:
            StormSample(scene: .storm, layout: stormLayout, focus: $focus)
        case .night:
            DashboardSample(scene: .night, particles: false, focus: $focus)
                .overlay {
                    Color.black.opacity(1 - Theme.Dim.night)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
        case .settings:
            SettingsSample(scene: scene, focus: $focus, scrollTarget: requestedFocus)
        case .setup:
            SetupSample(scene: scene, state: setupState, focus: $focus)
        }
    }
}
#endif
