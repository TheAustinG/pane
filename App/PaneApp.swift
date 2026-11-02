import SwiftUI

@main
struct PaneApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

private struct RootView: View {
    var body: some View {
        #if DEBUG
        if let page = PreviewPage(rawValue: UserDefaults.standard.string(forKey: "designPreview") ?? "") {
            DesignPreviewView(page: page)
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        Text("Pane")
            .font(.largeTitle)
            .accessibilityIdentifier("pane.placeholder")
    }
}
