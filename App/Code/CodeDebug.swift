#if DEBUG
import PaneCore
import SwiftUI

/// Debug menu row: force the deploy nudge on or off, refresh now.
struct CodeDebugRow: View {
    let model: AppModel

    var body: some View {
        let code = model.code
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                button("Nudge on", id: "on", pressed: code.debugNudge == true) { code.debugNudge = true }
                button("Nudge off", id: "off", pressed: code.debugNudge == false) { code.debugNudge = false }
                button("Live", id: "live", pressed: code.debugNudge == nil) { code.debugNudge = nil }
                Button {
                    code.refreshNow()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("debug.code.refresh")
            }
            Text(status)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("debug.code.state")
        }
    }

    private func button(_ title: String, id: String, pressed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: pressed ? "checkmark.circle.fill" : "circle")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityValue(pressed ? "active" : "")
        .accessibilityIdentifier("debug.code.\(id)")
    }

    private var status: String {
        let code = model.code
        let verdicts = code.deploys.map { "\($0.target.repositoryName) \(Self.name($0.verdict))" }.joined(separator: ", ")
        let active = code.nudges.map(\.target.repositoryName).joined(separator: ", ")
        return "GitHub \(code.githubConnection.stateName), Portainer \(code.portainerConnection.stateName), deploys: \(verdicts.isEmpty ? "none" : verdicts), nudges: \(active.isEmpty ? "none" : active)"
    }

    private static func name(_ verdict: DeployVerdict) -> String {
        switch verdict {
        case .current: "current"
        case .behind: "behind"
        case .unknown: "unknown"
        }
    }
}
#endif
