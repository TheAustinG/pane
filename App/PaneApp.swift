import SwiftUI

@main
struct PaneApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Pane")
                .font(.largeTitle)
                .accessibilityIdentifier("pane.placeholder")
        }
    }
}
