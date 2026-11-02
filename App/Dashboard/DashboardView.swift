import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        let date = model.now()
        ZStack {
            SkyView(target: model.palette(at: date), quality: model.quality)
            Text("Pane")
                .font(.largeTitle)
                .accessibilityIdentifier("pane.placeholder")
        }
        .fullScreenCover(isPresented: $model.isSettingsPresented) {
            SettingsRoot(model: model)
        }
    }
}
