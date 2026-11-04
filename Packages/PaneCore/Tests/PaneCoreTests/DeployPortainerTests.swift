import Foundation
import Security
import Testing
@testable import PaneCore

/// SHA-256 of `Fixtures/portainer-test-cert.der`, a self-signed certificate for `fixture.invalid`.
private let testCertificateSHA256 = "2534ed0958dd52cecd710e9b0d73f49708502cf0d72d4a0f76524a629cb3522b"
private let otherSHA256 = String(repeating: "0f", count: 32)

private func testTrust() throws -> SecTrust {
    let certificate = try #require(SecCertificateCreateWithData(nil, CodeSample.data("portainer-test-cert", "der") as CFData))
    var trust: SecTrust?
    let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "fixture.invalid" as CFString), &trust)
    #expect(status == errSecSuccess)
    return try #require(trust)
}

@Suite("Deploy Portainer")
struct DeployPortainerTests {
    @Test func decodesTheRecordedContainers() throws {
        let containers = try PortainerClient.parseContainers(CodeSample.data("portainer-containers"))
        #expect(containers.map(\.name) == ["beacon-beacon-1", "ledger", "socket-proxy", "hub", "updater"])
        let beacon = containers[0]
        #expect(beacon.image == "ghcr.io/sample-user/beacon:latest")
        #expect(beacon.imageID.hasPrefix("sha256:"))
        #expect(beacon.state == "running")
        #expect(beacon.labels[RevisionComparison.sourceLabel] == "https://github.com/sample-user/beacon")
        #expect(beacon.labels[RevisionComparison.revisionLabel]?.hasPrefix("6ad3d84") == true)
        #expect(beacon.created.timeIntervalSince1970.rounded() == beacon.created.timeIntervalSince1970)
        #expect(containers[4].labels.isEmpty)
    }

    @Test func decodesImageInspectAndStatus() throws {
        let image = try PortainerClient.parseImage(CodeSample.data("portainer-image"))
        #expect(image.created == CodeSample.date("2026-09-26T05:17:11.941394352Z"))
        #expect(image.labels[RevisionComparison.revisionLabel]?.hasPrefix("6ad3d84") == true)
        #expect(try PortainerClient.parseVersion(CodeSample.data("portainer-status")) == "2.45.1")
        #expect(throws: PortainerError.malformed("containers")) { try PortainerClient.parseContainers(Data("{}".utf8)) }
    }

    @Test func sendsTheKeyToTheEnvironmentsDockerProxy() async throws {
        let http = FakeHTTP()
        CodeSample.portainerRoutes(http)
        let imageID = "sha256:" + String(repeating: "a", count: 64)
        http.set("/api/endpoints/3/docker/images/\(imageID)/json", fixture: "portainer-image")
        let client = PortainerClient(http: http, server: CodeSample.server, token: CodeSample.portainerToken)
        #expect(try await client.version() == "2.45.1")
        #expect(try await client.containers().count == 5)
        #expect(try await client.image(id: imageID).labels.isEmpty == false)
        await #expect(throws: PortainerError.malformed("image id")) { try await client.image(id: "../../system/status") }
        #expect(http.requests.map { $0.url?.absoluteString } == [
            "https://portainer.fixture.invalid:9443/api/system/status",
            "https://portainer.fixture.invalid:9443/api/endpoints/3/docker/containers/json",
            "https://portainer.fixture.invalid:9443/api/endpoints/3/docker/images/\(imageID)/json",
        ])
        #expect(http.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-API-Key") == CodeSample.portainerToken })
    }

    @Test func statusCodes() async {
        let http = FakeHTTP()
        let client = PortainerClient(http: http, server: CodeSample.server, token: CodeSample.portainerToken)
        let path = "/api/endpoints/3/docker/containers/json"
        http.set(path, fixture: "portainer-bad-key", status: 401)
        await #expect(throws: PortainerError.unauthorized) { try await client.containers() }
        http.set(path, fixture: "portainer-unknown-environment", status: 404)
        await #expect(throws: PortainerError.notFound) { try await client.containers() }
        http.set(path, status: 403)
        await #expect(throws: PortainerError.forbidden) { try await client.containers() }
        http.set(path, status: 500)
        await #expect(throws: PortainerError.status(500)) { try await client.containers() }
    }

    @Test func imageIDs() {
        #expect(PortainerClient.isImageID("sha256:" + String(repeating: "a", count: 64)))
        #expect(PortainerClient.isImageID(String(repeating: "b", count: 12)))
        #expect(!PortainerClient.isImageID("sha256:"))
        #expect(!PortainerClient.isImageID("sha256:../x"))
        #expect(!PortainerClient.isImageID(""))
    }

    @Test func hashesAndNormalizesFingerprints() {
        #expect(PortainerTrust.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(PortainerTrust.normalized(testCertificateSHA256.uppercased()) == testCertificateSHA256)
        let colons = stride(from: 0, to: 64, by: 2).map { index in
            let start = testCertificateSHA256.index(testCertificateSHA256.startIndex, offsetBy: index)
            return String(testCertificateSHA256[start...testCertificateSHA256.index(after: start)])
        }.joined(separator: ":")
        #expect(PortainerTrust.normalized(colons) == testCertificateSHA256)
        #expect(PortainerTrust.normalized("abc") == nil)
        #expect(PortainerTrust.normalized(String(repeating: "g", count: 64)) == nil)
    }

    @Test func trustDecisions() {
        let leaf = testCertificateSHA256
        let decide = PortainerTrust.decide(systemTrusted:leafSHA256:pinned:trustOnFirstUse:)
        #expect(decide(true, leaf, nil, false) == .accept(observed: nil))
        #expect(decide(true, leaf, otherSHA256, false) == .accept(observed: nil))
        #expect(decide(false, leaf, leaf, false) == .accept(observed: leaf))
        #expect(decide(false, leaf.uppercased(), leaf, false) == .accept(observed: leaf))
        #expect(decide(false, leaf, otherSHA256, false) == .reject(.init(observed: leaf)))
        #expect(decide(false, leaf, otherSHA256, true) == .reject(.init(observed: leaf)))
        #expect(decide(false, leaf, nil, true) == .accept(observed: leaf))
        #expect(decide(false, leaf, nil, false) == .reject(.init(observed: leaf)))
        #expect(decide(false, nil, leaf, true) == .reject(.init(observed: nil)))
        #expect(decide(false, leaf, "not a hash", false) == .reject(.init(observed: leaf)))
    }

    @Test func evaluatesASelfSignedCertificate() throws {
        #expect(PortainerTrust.sha256Hex(CodeSample.data("portainer-test-cert", "der")) == testCertificateSHA256)
        #expect(PortainerTrust.decide(try testTrust(), pinned: testCertificateSHA256, trustOnFirstUse: false) == .accept(observed: testCertificateSHA256))
        #expect(PortainerTrust.decide(try testTrust(), pinned: otherSHA256, trustOnFirstUse: false) == .reject(.init(observed: testCertificateSHA256)))
        #expect(PortainerTrust.decide(try testTrust(), pinned: nil, trustOnFirstUse: true) == .accept(observed: testCertificateSHA256))
        #expect(PortainerTrust.decide(try testTrust(), pinned: nil, trustOnFirstUse: false) == .reject(.init(observed: testCertificateSHA256)))
    }

    @Test func serverAddresses() {
        #expect(PortainerServer(address: "portainer.fixture.invalid:9443", environmentID: 3)?.address == "https://portainer.fixture.invalid:9443")
        let server = PortainerServer(address: "https://portainer.fixture.invalid:9443/", environmentID: 3, pinnedCertificateSHA256: testCertificateSHA256)!
        let decoded = try? JSONDecoder().decode(PortainerServer.self, from: JSONEncoder().encode(server))
        #expect(decoded == server)
        #expect(decoded?.pinnedCertificateSHA256 == testCertificateSHA256)
    }
}

@Suite("Deploy Portainer setup test")
struct DeployPortainerSetupTests {
    private func test(_ http: FakeHTTP, token: String = CodeSample.portainerToken, observed: String? = nil) async -> Result<PortainerServerInfo, CodeSetupError> {
        await CodeController.testPortainer(server: CodeSample.server, token: token, http: http) { observed }
    }

    @Test func reportsVersionCountAndFingerprint() async {
        let http = FakeHTTP()
        CodeSample.portainerRoutes(http)
        #expect(await test(http, token: " \(CodeSample.portainerToken) ", observed: testCertificateSHA256)
            == .success(PortainerServerInfo(version: "2.45.1", containerCount: 5, certificateSHA256: testCertificateSHA256)))
        #expect(await test(http) == .success(PortainerServerInfo(version: "2.45.1", containerCount: 5, certificateSHA256: nil)))
    }

    @Test func failures() async {
        let http = FakeHTTP()
        CodeSample.portainerRoutes(http)
        #expect(await test(http, token: "  ") == .failure(.invalidToken))
        #expect(http.count == 0)

        http.set("/api/endpoints/3/docker/containers/json", fixture: "portainer-unknown-environment", status: 404)
        #expect(await test(http) == .failure(.unknownEnvironment))
        http.set("/api/endpoints/3/docker/containers/json", fixture: "portainer-bad-key", status: 401)
        #expect(await test(http) == .failure(.invalidToken))

        http.remove("/api/system/status")
        #expect(await test(http) == .failure(.unexpectedReply("Not a Portainer server")))

        http.fail(with: PortainerCertificateError(observed: otherSHA256))
        #expect(await test(http) == .failure(.certificateChanged))
        http.fail(with: URLError(.cannotConnectToHost))
        #expect(await test(http) == .failure(.unreachable))
        http.fail(with: URLError(.timedOut))
        #expect(await test(http) == .failure(.timeout))
    }

    @Test func plainHTTPRefusedConnectionIsUnreachable() async {
        let server = PortainerServer(address: "http://127.0.0.1:9", environmentID: 1)!
        let result = await CodeController.testPortainer(server: server, token: "sample")
        #expect(result == .failure(.unreachable))
    }
}
