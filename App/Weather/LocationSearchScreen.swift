import MapKit
import PaneCore
import SwiftUI

struct LocationMatch: Hashable {
    let name: String
    let detail: String?
    let latitude: Double
    let longitude: Double
}

/// City search for the home location. Laid out like the Settings choice screens: title and help on
/// the left, the field and its results in a 1000 pt list on the right.
struct LocationSearchScreen: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var phase = Phase.idle
    @FocusState private var fieldFocused: Bool

    enum Phase: Equatable {
        case idle
        case searching
        case results([LocationMatch])
        case failed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text("Location")
                    .font(Theme.Typeface.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                SettingsHelpPane(text: WeatherSettingsSection.locationHelp)
            }
            .frame(width: 620, alignment: .leading)
            List {
                TextField("City", text: $query)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("settings.location.search")
                resultRows
            }
            .frame(width: 1000)
        }
        .padding(.vertical, Theme.Layout.marginVertical)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
        .defaultFocus($fieldFocused, true)
        .task(id: query) { await search() }
    }

    @ViewBuilder private var resultRows: some View {
        switch phase {
        case .idle:
            stateLine("Type a city name")
        case .searching:
            stateLine("Searching")
        case .failed:
            stateLine("Search is unavailable right now")
        case .results(let matches) where matches.isEmpty:
            stateLine("No cities found")
        case .results(let matches):
            ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
                Button {
                    choose(match)
                } label: {
                    HStack {
                        Text(match.name)
                        Spacer()
                        if let detail = match.detail {
                            Text(detail).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("settings.location.result.\(index)")
            }
        }
    }

    private func stateLine(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.Ink.tertiary)
            .accessibilityIdentifier("settings.location.state")
    }

    private func choose(_ match: LocationMatch) {
        model.setHomeLocation(
            HomeLocation(name: match.name, coordinate: GeoPoint(latitude: match.latitude, longitude: match.longitude))
        )
        dismiss()
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .idle
            return
        }
        phase = .searching
        do {
            try await Task.sleep(for: .milliseconds(400))
            phase = .results(try await Self.matches(for: text))
        } catch is CancellationError {
            return
        } catch {
            phase = .failed
        }
    }

    private static func matches(for text: String) async throws -> [LocationMatch] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        request.addressFilter = MKAddressFilter(including: .locality)
        let response = try await MKLocalSearch(request: request).start()
        var seen = Set<String>()
        return response.mapItems.compactMap { item in
            guard let name = item.addressRepresentations?.cityWithContext ?? item.name,
                  seen.insert(name).inserted else { return nil }
            let coordinate = item.location.coordinate
            return LocationMatch(
                name: name,
                detail: item.addressRepresentations?.regionName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }
}
