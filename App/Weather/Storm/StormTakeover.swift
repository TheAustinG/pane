import PaneCore
import SwiftUI

/// Radar over the whole screen with the weather strip floating on it. Shown in place of the
/// dashboard layout while `AppModel.isStormTakeoverShown`.
struct StormTakeover: View {
    let model: AppModel
    let date: Date

    var body: some View {
        Button {} label: {
            Text("Radar")
                .font(Theme.Typeface.title)
                .padding(Theme.Layout.paneInset)
        }
        .buttonStyle(GlassPaneButtonStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { model.closeStormTakeover() }
    }
}
