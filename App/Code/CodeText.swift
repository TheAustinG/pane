import Foundation
import PaneCore

extension CodeConnection {
    /// The value of the `code.card` accessibility element, per connection.
    var stateName: String {
        switch self {
        case .notConfigured: "notConfigured"
        case .loading: "loading"
        case .ready: "ready"
        case .authFailed: "authFailed"
        case .failed: "failed"
        }
    }

    var settingsValue: String {
        switch self {
        case .notConfigured: "Not set up"
        case .loading: "Connecting"
        case .ready: "Connected"
        case .authFailed: "Token rejected"
        case .failed: "Unreachable"
        }
    }
}

extension CodeController {
    /// The GitHub row's value in Settings: "Connected as sample", "Not set up", "Token rejected".
    var githubSettingsValue: String {
        switch githubConnection {
        case .ready, .loading:
            github.map { "Connected as \($0.login)" } ?? githubConnection.settingsValue
        default:
            githubConnection.settingsValue
        }
    }
}

enum CodeService {
    case github
    case portainer

    var name: String {
        switch self {
        case .github: "GitHub"
        case .portainer: "Portainer"
        }
    }
}

extension CodeSetupError {
    func message(for service: CodeService) -> String {
        switch self {
        case .badAddress:
            "That address does not look right. Try something like portainer.local:9443."
        case .unreachable:
            switch service {
            case .github: "Could not reach GitHub. Check that the Apple TV is online."
            case .portainer: "Could not reach the server. Check the address and that the Apple TV is on the same network."
            }
        case .invalidToken:
            switch service {
            case .github: "GitHub rejected the token. Create a new fine-grained token and paste it again."
            case .portainer: "Portainer rejected the token. Create a new access token and paste it again."
            }
        case .timeout:
            "\(service.name) took too long to answer. Try again."
        case .missingPermission(let name):
            "The token works but lacks the \(name) permission. Add read-only \(name) access and test again."
        case .unknownEnvironment:
            "Portainer has no environment with that id. Check the number in its Environments list."
        case .certificateChanged:
            "The server's certificate is not the one Pane trusts. Forget Portainer and set it up again if you replaced it."
        case .unexpectedReply:
            "The server answered, but not like \(service.name). Check the address."
        }
    }
}

enum CodeText {
    /// "just now", "5m ago", "2h ago", "3d ago".
    static func age(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86_400)d ago"
        }
    }

    /// The first and last 8 hex digits of a SHA-256 in groups of four, such as "3A7F 90C1 ... 9E21 B4D0".
    static func fingerprint(_ hex: String) -> String {
        func groups(_ text: Substring) -> String {
            stride(from: 0, to: text.count, by: 4).map { start in
                let from = text.index(text.startIndex, offsetBy: start)
                let to = text.index(from, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex
                return String(text[from..<to])
            }.joined(separator: " ").uppercased()
        }
        guard hex.count > 16 else { return groups(Substring(hex)) }
        return "\(groups(hex.prefix(8))) ... \(groups(hex.suffix(8)))"
    }

    static func nudgeText(_ nudges: [DeployStatus], now: Date) -> String? {
        guard let first = nudges.first, case .behind(let builtAt) = first.verdict else { return nil }
        var text = "\(first.target.repositoryName) image built \(age(from: builtAt, now: now)), not redeployed"
        if nudges.count > 1 { text += " (+\(nudges.count - 1) more)" }
        return text
    }
}
