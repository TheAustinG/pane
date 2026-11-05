import PaneCore
import SwiftUI

/// GitHub and Portainer connections and the deploy nudge (Phase 5).
enum CodeSettingsSection: SettingsSection {
    static let title = "Code"

    static func rows(model: AppModel) -> some View {
        CodeSettingsRows(model: model)
    }

    static let githubHelp = "A fine-grained token with read-only Contents, Metadata and Actions on all repositories."
    static let portainerHelp = "Used for the redeploy nudge: compares the running container's revision with the latest build."
    static let nudgeHelp = "Shows a nudge on the GitHub card when a watched image was built but its container still runs an older one."

    static func targetHelp(_ target: DeployTarget) -> String {
        "Compares the container \(target.containerName) with the latest successful run of \(target.workflow) in \(target.repository)."
    }
}

private struct CodeSettingsRows: View {
    let model: AppModel

    var body: some View {
        let code = model.code
        NavigationLink {
            GitHubSetupScreen(model: model)
        } label: {
            LabeledContent("GitHub", value: code.githubSettingsValue)
        }
        .settingsHelp(CodeSettingsSection.githubHelp)
        .accessibilityIdentifier("settings.code.github")

        NavigationLink {
            PortainerSetupScreen(model: model)
        } label: {
            LabeledContent("Portainer", value: code.portainerConnection.settingsValue)
        }
        .settingsHelp(CodeSettingsSection.portainerHelp)
        .accessibilityIdentifier("settings.code.portainer")

        Toggle("Deploy nudge", isOn: Binding(
            get: { model.code.nudgeEnabled },
            set: { model.code.nudgeEnabled = $0 }
        ))
        .settingsHelp(CodeSettingsSection.nudgeHelp)
        .accessibilityIdentifier("settings.code.nudge")

        ForEach(code.candidates) { target in
            Toggle("Watch \(target.repositoryName)", isOn: Binding(
                get: { isWatched(target) },
                set: { setWatched(target, $0) }
            ))
            .settingsHelp(CodeSettingsSection.targetHelp(target))
            .accessibilityIdentifier("settings.code.target.\(target.repositoryName)")
        }
    }

    private func isWatched(_ target: DeployTarget) -> Bool {
        model.code.targets?.contains { $0.id == target.id } ?? true
    }

    private func setWatched(_ target: DeployTarget, _ watched: Bool) {
        var list = model.code.targets ?? model.code.candidates
        list.removeAll { $0.id == target.id }
        if watched { list.append(target) }
        model.code.targets = list
    }
}
