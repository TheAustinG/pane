import SwiftUI
import UIKit

/// Apple's required attribution mark. It is the image WeatherKit's attribution returns, kept by
/// the controller so it still shows offline; until that loads, the name stands in as text.
struct AppleWeatherMark: View {
    let imageData: Data?

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 26)
            } else {
                Text("Apple Weather")
                    .font(Theme.Typeface.caption.weight(.medium))
                    .foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .accessibilityLabel("Apple Weather")
        .accessibilityIdentifier("weather.attributionMark")
    }
}
