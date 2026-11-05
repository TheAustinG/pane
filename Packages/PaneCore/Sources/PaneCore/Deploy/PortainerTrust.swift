import CryptoKit
import Foundation
import Security

/// Whether to accept a Portainer server's certificate. The system's trust wins; otherwise only the
/// leaf certificate pinned at setup is accepted, by the SHA-256 of its DER bytes.
enum PortainerTrust {
    enum Decision: Hashable, Sendable {
        /// `observed` is the leaf's SHA-256 when the system did not trust it, nil when it did.
        case accept(observed: String?)
        case reject(Rejection)
    }

    struct Rejection: Hashable, Sendable {
        /// The leaf's SHA-256, nil when the server sent no certificate.
        let observed: String?
    }

    /// `trustOnFirstUse` accepts an untrusted certificate when nothing is pinned yet, for the setup
    /// screen's test, which shows the fingerprint so saving can pin it.
    static func decide(systemTrusted: Bool, leafSHA256: String?, pinned: String?, trustOnFirstUse: Bool) -> Decision {
        if systemTrusted { return .accept(observed: nil) }
        guard let leaf = leafSHA256.flatMap(normalized) else { return .reject(Rejection(observed: nil)) }
        if let pinned {
            return normalized(pinned) == leaf ? .accept(observed: leaf) : .reject(Rejection(observed: leaf))
        }
        return trustOnFirstUse ? .accept(observed: leaf) : .reject(Rejection(observed: leaf))
    }

    static func decide(_ trust: SecTrust, pinned: String?, trustOnFirstUse: Bool) -> Decision {
        let systemTrusted = SecTrustEvaluateWithError(trust, nil)
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        let leaf = chain?.first.map { sha256Hex(SecCertificateCopyData($0) as Data) }
        return decide(systemTrusted: systemTrusted, leafSHA256: leaf, pinned: pinned, trustOnFirstUse: trustOnFirstUse)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Lowercase hex without separators, so a fingerprint copied as `AB:CD:...` still matches.
    static func normalized(_ fingerprint: String) -> String? {
        let hex = fingerprint.lowercased().filter { !":- ".contains($0) }
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }
}

/// The server's certificate was refused: it is not the pinned one, or nothing is pinned and the
/// system does not trust it.
struct PortainerCertificateError: Error, Hashable, Sendable {
    let observed: String?
}
