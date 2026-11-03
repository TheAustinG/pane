import MapKit
import PaneCore
import SwiftUI

/// City suggestions as the query changes. A completion carries no coordinate; `resolve` fetches
/// one for the completion the user picks.
@MainActor
@Observable
final class CityCompleter: NSObject {
    enum State: Equatable {
        case idle
        case searching
        case results
        case failed
    }

    private(set) var state = State.idle
    private(set) var completions: [MKLocalSearchCompletion] = []
    private(set) var isResolving = false
    /// The chosen city could not be looked up; the suggestions stay so another can be picked.
    private(set) var resolveFailed = false
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: .locality)
        completer.delegate = self
    }

    func update(_ query: String) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            completer.cancel()
            completions = []
            state = .idle
            return
        }
        state = .searching
        completer.queryFragment = text
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> HomeLocation? {
        guard !isResolving else { return nil }
        isResolving = true
        resolveFailed = false
        defer { isResolving = false }
        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = .address
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            resolveFailed = true
            return nil
        }
        let coordinate = item.location.coordinate
        let name = item.addressRepresentations?.cityWithContext ?? completion.title
        return HomeLocation(name: name, coordinate: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}

extension CityCompleter: @preconcurrency MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        var seen = Set<String>()
        completions = completer.results
            .filter { seen.insert($0.title + "|" + $0.subtitle).inserted }
            .prefix(8)
            .map { $0 }
        state = .results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        state = .failed
    }
}

/// City search for the home location. Laid out like the Settings choice screens: title and help on
/// the left, the field and its results in a 1000 pt list on the right.
struct LocationSearchScreen: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var completer = CityCompleter()
    @FocusState private var fieldFocused: Bool

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
        .onChange(of: query) { _, text in completer.update(text) }
    }

    @ViewBuilder private var resultRows: some View {
        switch completer.state {
        case .idle:
            stateLine("Type a city name")
        case .searching where completer.completions.isEmpty:
            stateLine("Searching")
        case .failed:
            stateLine("Search is unavailable right now")
        case .results where completer.completions.isEmpty:
            stateLine("No cities found")
        case .searching, .results:
            if completer.resolveFailed {
                stateLine("That city could not be loaded. Try again or pick another.")
            }
            ForEach(Array(completer.completions.enumerated()), id: \.offset) { index, completion in
                Button {
                    Task { await choose(completion) }
                } label: {
                    HStack {
                        Text(completion.title)
                        Spacer()
                        if !completion.subtitle.isEmpty {
                            Text(completion.subtitle).foregroundStyle(.secondary)
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

    private func choose(_ completion: MKLocalSearchCompletion) async {
        guard let home = await completer.resolve(completion) else { return }
        model.setHomeLocation(home)
        dismiss()
    }
}
