import PaneCore
import SwiftUI

/// The GitHub token, a connection test, and Save. Actions stack vertically under the field.
struct GitHubSetupScreen: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var status = Status.idle
    @State private var testedToken: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case token, test, save, cancel, forget
    }

    private enum Status: Equatable {
        case idle
        case testing
        case passed(login: String)
        case failed(CodeSetupError)
        case saveFailed
        case forgetFailed
    }

    private var canSave: Bool {
        guard case .passed = status else { return false }
        return testedToken == token
    }

    var body: some View {
        CodeSetupLayout(
            symbol: "arrow.triangle.branch",
            title: "Connect GitHub",
            instructions: "Create a fine-grained personal access token for all repositories with read-only access to Contents, Metadata and Actions. Focus the field and accept the keyboard prompt on your iPhone to paste it."
        ) {
            SecureField("Access token", text: $token, prompt: Text(model.code.hasGitHubToken ? "Enter the token again to test" : "Fine-grained access token"))
                .focused($focus, equals: .token)
                .accessibilityIdentifier("code.setup.github.token")
            statusLine
                .frame(minHeight: 72, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("code.setup.github.status")
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Button { Task { await test() } } label: { Text("Test connection").frame(width: 400) }
                    .buttonStyle(.glass)
                    .disabled(token.isEmpty || status == .testing)
                    .focused($focus, equals: .test)
                    .accessibilityIdentifier("code.setup.github.test")
                Button { save() } label: { Text("Save").frame(width: 400) }
                    .buttonStyle(.glass)
                    .disabled(!canSave)
                    .focused($focus, equals: .save)
                    .accessibilityIdentifier("code.setup.github.save")
                Button { dismiss() } label: { Text("Not now").frame(width: 400) }
                    .buttonStyle(.glass)
                    .focused($focus, equals: .cancel)
                    .accessibilityIdentifier("code.setup.github.cancel")
                if model.code.hasGitHubToken {
                    Button { forget() } label: { Text("Forget token").frame(width: 400) }
                        .buttonStyle(.glass)
                        .focused($focus, equals: .forget)
                        .accessibilityIdentifier("code.setup.github.forget")
                }
            }
        }
        .defaultFocus($focus, .token)
        .onAppear(perform: prefill)
        .onChange(of: token) { _, _ in invalidateTest() }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .idle:
            Text(token.isEmpty ? "The token is needed before Pane can connect." : "Run the test, then save.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
        case .testing:
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Testing connection").font(Theme.Typeface.body)
            }
        case .passed(let login):
            StatusRow(symbol: "checkmark", title: "Connected as \(login)")
        case .failed(let error):
            NudgeChip(text: error.message(for: .github), symbol: "exclamationmark.triangle.fill", tone: .warning)
        case .saveFailed:
            NudgeChip(text: "Could not save the token to the Keychain. Try again.", symbol: "exclamationmark.triangle.fill", tone: .warning)
        case .forgetFailed:
            NudgeChip(text: "Could not remove the token from the Keychain. Try again.", symbol: "exclamationmark.triangle.fill", tone: .warning)
        }
    }

    private func prefill() {
        #if DEBUG
        guard token.isEmpty else { return }
        if LaunchOptions.parse().codeSetupPrefill, let prefill = CodeWiring.githubPrefill {
            token = prefill
        }
        #endif
    }

    private func invalidateTest() {
        guard testedToken != token else { return }
        switch status {
        case .testing: break
        default: status = .idle
        }
    }

    private func test() async {
        let snapshot = token
        status = .testing
        let result = await CodeController.testGitHub(token: snapshot, http: URLSessionHTTPClient())
        guard snapshot == token else {
            status = .idle
            return
        }
        switch result {
        case .success(let login):
            testedToken = snapshot
            status = .passed(login: login)
            focus = .save
        case .failure(let error):
            testedToken = nil
            status = .failed(error)
        }
    }

    private func save() {
        do {
            try model.code.configureGitHub(token: token)
            dismiss()
        } catch {
            status = .saveFailed
        }
    }

    private func forget() {
        do {
            try model.code.forgetGitHub()
        } catch {
            status = .forgetFailed
            return
        }
        token = ""
        status = .idle
        testedToken = nil
        focus = .token
    }
}
