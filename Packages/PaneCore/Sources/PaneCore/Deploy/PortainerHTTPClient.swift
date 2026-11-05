import Foundation
import Synchronization

/// Requests to one Portainer server. An https server whose certificate the system does not trust
/// is accepted only when its leaf certificate matches `server.pinnedCertificateSHA256`.
public final class PortainerHTTPClient: HTTPClient, @unchecked Sendable {
    public let server: PortainerServer
    private let session: URLSession
    private let trust: PortainerTrustDelegate

    public convenience init(server: PortainerServer) {
        self.init(server: server, trustOnFirstUse: false)
    }

    /// `trustOnFirstUse` accepts an unpinned certificate the system does not trust, once, for the
    /// setup screen's test.
    init(server: PortainerServer, trustOnFirstUse: Bool, timeout: TimeInterval = 15) {
        self.server = server
        trust = PortainerTrustDelegate(
            host: server.baseURL.host(),
            pinned: server.pinnedCertificateSHA256,
            trustOnFirstUse: trustOnFirstUse
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: trust, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    /// The SHA-256 of the leaf certificate last presented, when the system did not trust it. Nil
    /// for plain http or a certificate the system trusts.
    public var observedCertificateSHA256: String? {
        trust.observed
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        } catch {
            if let rejection = trust.takeRejection() {
                throw PortainerCertificateError(observed: rejection.observed)
            }
            throw error
        }
    }
}

final class PortainerTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    private struct State {
        var observed: String?
        var rejection: PortainerTrust.Rejection?
    }

    let host: String?
    let pinned: String?
    let trustOnFirstUse: Bool
    private let state = Mutex(State())

    init(host: String?, pinned: String?, trustOnFirstUse: Bool) {
        self.host = host
        self.pinned = pinned
        self.trustOnFirstUse = trustOnFirstUse
    }

    var observed: String? {
        state.withLock { $0.observed }
    }

    func takeRejection() -> PortainerTrust.Rejection? {
        state.withLock { state in
            defer { state.rejection = nil }
            return state.rejection
        }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = space.serverTrust,
              host.map({ $0.caseInsensitiveCompare(space.host) == .orderedSame }) ?? false else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        switch PortainerTrust.decide(serverTrust, pinned: pinned, trustOnFirstUse: trustOnFirstUse) {
        case .accept(let observed):
            state.withLock { $0.observed = observed }
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        case .reject(let rejection):
            state.withLock { state in
                state.observed = rejection.observed
                state.rejection = rejection
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
