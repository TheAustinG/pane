import PaneCore
import SwiftUI

/// Server address and token, a connection test, and Save. Fields and actions stack vertically
/// because tvOS moves focus to the geometrically nearest control, so a side-by-side row under a
/// wide field sends Down to the wrong button.
struct HomeSetupScreen: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var status = Status.idle
    @State private var tested: Tested?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case address, token, test, save, cancel, forget
    }

    private enum Status: Equatable {
        case idle
        case testing
        case passed(HomeServerInfo)
        case failed(HomeSetupError)
        case saveFailed
        case forgetFailed
    }

    private struct Tested: Equatable {
        let address: String
        let token: String
    }

    private var hasBothFields: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty && !token.isEmpty
    }

    private var canSave: Bool {
        guard case .passed = status else { return false }
        return tested == Tested(address: address, token: token)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 96) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Image(systemName: "house")
                    .font(.system(size: 64, weight: .light))
                    .frame(width: 132, height: 132)
                    .glassPane()
                    .accessibilityHidden(true)
                Text("Connect Home Assistant")
                    .font(Theme.Typeface.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Use a long-lived access token from a Home Assistant user without admin rights. Focus a field and accept the keyboard prompt on your iPhone to paste it.")
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 680, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                TextField("Server address", text: $address, prompt: Text("http://homeassistant.local:8123"))
                    .autocorrectionDisabled()
                    .focused($focus, equals: .address)
                    .accessibilityIdentifier("home.setup.address")
                SecureField("Access token", text: $token, prompt: Text(model.home.hasToken ? "Enter the token again to test" : "Long-lived access token"))
                    .focused($focus, equals: .token)
                    .accessibilityIdentifier("home.setup.token")
                statusLine
                    .frame(minHeight: 72, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("home.setup.status")
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Button { Task { await test() } } label: { Text("Test connection").frame(width: 400) }
                        .buttonStyle(.glass)
                        .disabled(!hasBothFields || status == .testing)
                        .focused($focus, equals: .test)
                        .accessibilityIdentifier("home.setup.test")
                    Button { save() } label: { Text("Save").frame(width: 400) }
                        .buttonStyle(.glass)
                        .disabled(!canSave)
                        .focused($focus, equals: .save)
                        .accessibilityIdentifier("home.setup.save")
                    Button { dismiss() } label: { Text("Not now").frame(width: 400) }
                        .buttonStyle(.glass)
                        .focused($focus, equals: .cancel)
                        .accessibilityIdentifier("home.setup.cancel")
                    if model.home.server != nil {
                        Button { forget() } label: { Text("Forget server").frame(width: 400) }
                            .buttonStyle(.glass)
                            .focused($focus, equals: .forget)
                            .accessibilityIdentifier("home.setup.forget")
                    }
                }
            }
            .frame(width: 860, alignment: .leading)
        }
        .padding(.top, 140)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
        .frame(maxHeight: .infinity, alignment: .top)
        .defaultFocus($focus, .address)
        .onAppear(perform: prefill)
        .onChange(of: address) { _, _ in invalidateTest() }
        .onChange(of: token) { _, _ in invalidateTest() }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .idle:
            Text(hasBothFields ? "Run the test, then save." : "Both fields are needed before Pane can connect.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
        case .testing:
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Testing connection").font(Theme.Typeface.body)
            }
        case .passed(let info):
            StatusRow(
                symbol: "checkmark",
                title: "Connected",
                detail: "Home Assistant \(info.version), \(info.entityCount) \(info.entityCount == 1 ? "entity" : "entities")"
            )
        case .failed(let error):
            NudgeChip(text: Self.message(for: error), symbol: "exclamationmark.triangle.fill", tone: .warning)
        case .saveFailed:
            NudgeChip(text: "Could not save the token to the Keychain. Try again.", symbol: "exclamationmark.triangle.fill", tone: .warning)
        case .forgetFailed:
            NudgeChip(text: "Could not remove the token from the Keychain. Try again.", symbol: "exclamationmark.triangle.fill", tone: .warning)
        }
    }

    private static func message(for error: HomeSetupError) -> String {
        switch error {
        case .badAddress: "That address does not look right. Try something like http://homeassistant.local:8123."
        case .unreachable: "Could not reach the server. Check the address and that the Apple TV is on the same network."
        case .invalidToken: "Home Assistant rejected the token. Create a new long-lived token and paste it again."
        case .timeout: "The server took too long to answer. Check the address and try again."
        case .unexpectedReply: "The server answered, but not like Home Assistant. Check the address."
        }
    }

    private func prefill() {
        guard address.isEmpty, token.isEmpty else { return }
        if let server = model.home.server { address = server.address }
        #if DEBUG
        if LaunchOptions.parse().homeSetupPrefill, let prefill = HomeWiring.prefill {
            address = prefill.address
            token = prefill.token
        }
        #endif
    }

    private func invalidateTest() {
        guard tested != Tested(address: address, token: token) else { return }
        switch status {
        case .testing: break
        default: status = .idle
        }
    }

    private func test() async {
        guard let server = HomeServer(address: address) else {
            status = .failed(.badAddress)
            return
        }
        let snapshot = Tested(address: address, token: token)
        status = .testing
        let result = await HomeController.testConnection(server: server, token: token, transport: URLSessionHATransportFactory())
        guard snapshot == Tested(address: address, token: token) else {
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
        guard let server = HomeServer(address: address) else { return }
        do {
            try model.home.configure(server: server, token: token)
            dismiss()
        } catch {
            status = .saveFailed
        }
    }

    private func forget() {
        do {
            try model.home.forget()
        } catch {
            status = .forgetFailed
            return
        }
        address = ""
        token = ""
        status = .idle
        tested = nil
        focus = .address
    }
}
