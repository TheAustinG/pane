import Foundation
import PaneCore

extension HomeConnection {
    /// The value of the `home.connection` accessibility element.
    var stateName: String {
        switch self {
        case .notConfigured: "notConfigured"
        case .connecting: "connecting"
        case .connected: "connected"
        case .disconnected: "disconnected"
        case .authFailed: "authFailed"
        }
    }

    var settingsValue: String {
        switch self {
        case .notConfigured: "Not set up"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .disconnected: "Reconnecting"
        case .authFailed: "Token rejected"
        }
    }
}

extension HAEntity {
    /// The state as a short phrase for lists, such as "31%", "Heat, 70°" or "Away".
    var stateText: String {
        if isUnavailable { return "Unavailable" }
        switch domain {
        case "sensor":
            guard let unit else { return state }
            return unit == "%" ? "\(state)%" : "\(state) \(unit)"
        case "scene": return "Scene"
        case "script": return "Script"
        case "input_button": return "Button"
        case "person", "device_tracker":
            return state == "home" ? "Home" : state == "not_home" ? "Away" : state.capitalizedWords
        case "climate":
            let mode = state.capitalizedWords
            guard let current = attributes["current_temperature"]?.number else { return mode }
            return "\(mode), \(Int(current.rounded()))°"
        default: return state.capitalizedWords
        }
    }
}

extension String {
    var capitalizedWords: String {
        replacingOccurrences(of: "_", with: " ").capitalized
    }
}

extension HomeEntityRole {
    var help: String {
        switch self {
        case .thermostat: "The thermostat whose temperature and heating or cooling state the card shows."
        case .humidity: "Humidity sensors. The first you pick is the main reading; the others show beside it."
        case .lock: "The door lock the card shows. It also drives the unlocked-late nudge."
        case .lights: "Lights the card counts and names. A light group counts as one."
        case .people: "People whose home or away state the card shows. It also drives the lights-on nudge."
        case .bedroomTV: "The bedroom media player. It drives the bedroom TV nudge."
        case .scenes: "Scenes, scripts and buttons shown when you click the Home card, in the order you pick them."
        }
    }

    var disconnectedHelp: String {
        "Connect Home Assistant first, then choose entities here."
    }
}
