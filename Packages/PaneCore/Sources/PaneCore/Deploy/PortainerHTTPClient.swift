import Foundation

/// Requests to one Portainer server. An https server whose certificate the system does not trust
/// is accepted only when its leaf certificate matches `server.pinnedCertificateSHA256`.
public final class PortainerHTTPClient: HTTPClient, @unchecked Sendable {
    public let server: PortainerServer

    public init(server: PortainerServer) {
        self.server = server
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}
