import PaneCore
import SwiftUI

/// Portainer address, environment id and token, a connection test, and Save. Saving pins the
/// certificate the test reported, so a self-signed server is trusted on first use.
struct PortainerSetupScreen: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var environment = ""
    @State private var token = ""
    @State private var status = Status.idle
    @State private var tested: Tested?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case address, environment, token, test, save, cancel, forget
    }

    private enum Status: Equatable, Error {
        case idle
        case testing
        case passed(PortainerServerInfo)
        case failed(CodeSetupError)
        case badEnvironment
        case saveFailed
        case forgetFailed
    }

    private struct Tested: Equatable {
        let address: String
        let environment: String
        let token: String
    }

    private var current: Tested { Tested(address: address, environment: environment, token: token) }

    private var hasAllFields: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !environment.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.isEmpty
    }

    private var canSave: Bool {
        guard case .passed = status else { return false }
        return tested == current
    }

    var body: some View {
        CodeSetupLayout(
            symbol: "shippingbox",
            title: "Connect Portainer",
            instructions: "Enter the address you open Portainer at (https is assumed), the id of the environment that runs your containers, and an access token from your Portainer account. Pane only reads the container list. A self-signed certificate is trusted once you test and save.",
            topPadding: Theme.Layout.marginVertical
        ) {
            HStack(spacing: Theme.Space.m) {
                TextField("Address", text: $address, prompt: Text("portainer.local:9443"))
                    .autocorrectionDisabled()
                    .focused($focus, equals: .address)
                    .accessibilityIdentifier("code.setup.portainer.address")
                TextField("Environment id", text: $environment, prompt: Text("2"))
                    .autocorrectionDisabled()
                    .frame(width: 260)
                    .focused($focus, equals: .environment)
                    .accessibilityIdentifier("code.setup.portainer.environment")
            }
            SecureField("Access token", text: $token, prompt: Text(model.code.hasPortainerToken ? "Enter the token again to test" : "Portainer access token"))
                .focused($focus, equals: .token)
                .accessibilityIdentifier("code.setup.portainer.token")
            statusLine
                .frame(minHeight: 100, alignment: .topLeading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("code.setup.portainer.status")
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Button { Task { await test() } } label: { Text("Test connection").frame(width: 400) }
                    .buttonStyle(.glass)
                    .disabled(!hasAllFields || status == .testing)
                    .focused($focus, equals: .test)
                    .accessibilityIdentifier("code.setup.portainer.test")
                Button { save() } label: { Text("Save").frame(width: 400) }
                    .buttonStyle(.glass)
                    .disabled(!canSave)
                    .focused($focus, equals: .save)
                    .accessibilityIdentifier("code.setup.portainer.save")
                Button { dismiss() } label: { Text("Not now").frame(width: 400) }
                    .buttonStyle(.glass)
                    .focused($focus, equals: .cancel)
                    .accessibilityIdentifier("code.setup.portainer.cancel")
                if model.code.portainer != nil {
                    Button { forget() } label: { Text("Forget server").frame(width: 400) }
                        .buttonStyle(.glass)
                        .focused($focus, equals: .forget)
                        .accessibilityIdentifier("code.setup.portainer.forget")
                }
            }
        }
        .defaultFocus($focus, .address)
        .onAppear(perform: prefill)
        .onChange(of: address) { _, _ in invalidateTest() }
        .onChange(of: environment) { _, _ in invalidateTest() }
        .onChange(of: token) { _, _ in invalidateTest() }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .idle:
            Text(hasAllFields ? "Run the test, then save." : "The address, environment id and token are all needed.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
        case .testing:
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Testing connection").font(Theme.Typeface.body)
            }
        case .passed(let info):
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                StatusRow(
                    symbol: "checkmark",
                    title: "Connected",
                    detail: "Portainer \(info.version), \(info.containerCount) \(info.containerCount == 1 ? "container" : "containers")"
                )
                if let fingerprint = info.certificateSHA256 {
                    Text("Certificate \(CodeText.fingerprint(fingerprint)). Save will trust this certificate.")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .failed(let error):
            NudgeChip(text: error.message(for: .portainer), symbol: "exclamationmark.triangle.fill", tone: .warning)
        case .badEnvironment:
            NudgeChip(text: "The environment id is a number, such as 2.", symbol: "exclamationmark.triangle.fill", tone: .warning)
        case .saveFailed:
            NudgeChip(text: "Could not save the token to the Keychain. Try again.", symbol: "exclamationmark.triangle.fill", tone: .warning)
        case .forgetFailed:
            NudgeChip(text: "Could not remove the token from the Keychain. Try again.", symbol: "exclamationmark.triangle.fill", tone: .warning)
        }
    }

    private func prefill() {
        guard address.isEmpty, environment.isEmpty, token.isEmpty else { return }
        if let server = model.code.portainer {
            address = server.address
            environment = String(server.environmentID)
        }
        #if DEBUG
        if LaunchOptions.parse().codeSetupPrefill, let prefill = CodeWiring.portainerPrefill {
            address = prefill.address
            environment = prefill.environmentID
            token = prefill.token
        }
        #endif
    }

    private func invalidateTest() {
        guard tested != current else { return }
        switch status {
        case .testing: break
        default: status = .idle
        }
    }

    private func makeServer(pinning fingerprint: String? = nil) -> Result<PortainerServer, Status> {
        guard let id = Int(environment.trimmingCharacters(in: .whitespaces)), id > 0 else { return .failure(.badEnvironment) }
        guard let server = PortainerServer(address: address, environmentID: id, pinnedCertificateSHA256: fingerprint) else {
            return .failure(.failed(.badAddress))
        }
        return .success(server)
    }

    private func test() async {
        let server: PortainerServer
        switch makeServer() {
        case .success(let value): server = value
        case .failure(let failure):
            status = failure
            return
        }
        let snapshot = current
        status = .testing
        let result = await CodeController.testPortainer(server: server, token: token)
        guard snapshot == current else {
            status = .idle
            return
        }
        switch result {
        case .success(let info):
            tested = snapshot
            status = .passed(info)
            focus = .save
        case .failure(let error):
            tested = nil
            status = .failed(error)
        }
    }

    private func save() {
        guard case .passed(let info) = status, case .success(let server) = makeServer(pinning: info.certificateSHA256) else { return }
        do {
            try model.code.configurePortainer(server: server, token: token)
            dismiss()
        } catch {
            status = .saveFailed
        }
    }

    private func forget() {
        do {
            try model.code.forgetPortainer()
        } catch {
            status = .forgetFailed
            return
        }
        address = ""
        environment = ""
        token = ""
        status = .idle
        tested = nil
        focus = .address
    }
}
