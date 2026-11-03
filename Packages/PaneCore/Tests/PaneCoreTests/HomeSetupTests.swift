import Foundation
import Testing
@testable import PaneCore

private let start = HomeSample.start

private func frame(_ object: [String: HAValue]) -> String {
    HAOutbound.encode(object)
}

private let authRequired = frame(["type": .string("auth_required"), "ha_version": .string("2026.10.4")])
private let authOK = frame(["type": .string("auth_ok"), "ha_version": .string("2026.10.4")])

@Suite("Home setup test", .timeLimit(.minutes(1)))
@MainActor
struct HomeSetupTests {
    @Test func reportsTheVersionAndEntityCountThenCloses() async {
        let fixture = FixtureHATransportFactory(entities: HomeSample.entities, expectedToken: HomeSample.token)
        let result = await HomeController.testConnection(server: HomeSample.server, token: " \(HomeSample.token) ", transport: fixture)
        #expect(result == .success(HomeServerInfo(version: FixtureHATransportFactory.defaultVersion, entityCount: HomeSample.entities.count)))
        #expect(fixture.snapshot.openConnections == 0)
        #expect(fixture.snapshot.received.count == 2)
    }

    @Test func aRejectedTokenIsInvalidToken() async {
        let fixture = FixtureHATransportFactory(expectedToken: HomeSample.token)
        let result = await HomeController.testConnection(server: HomeSample.server, token: "wrong", transport: fixture)
        #expect(result == .failure(.invalidToken))
    }

    @Test func anEmptyTokenIsNeverSent() async {
        let fixture = FixtureHATransportFactory()
        let result = await HomeController.testConnection(server: HomeSample.server, token: "  ", transport: fixture)
        #expect(result == .failure(.invalidToken))
        #expect(fixture.connectionsOpened == 0)
    }

    @Test func aDownServerIsUnreachable() async {
        let fixture = FixtureHATransportFactory()
        fixture.refusesConnections = true
        let result = await HomeController.testConnection(server: HomeSample.server, token: HomeSample.token, transport: fixture)
        #expect(result == .failure(.unreachable))
    }

    @Test func aSilentServerTimesOut() async {
        let clock = SteppingClock(now: start)
        let server = ScriptedTransportFactory()
        let test = Task {
            await HomeController.testConnection(server: HomeSample.server, token: HomeSample.token, transport: server, timeout: 5, clock: clock)
        }
        await clock.waitForSleeper(until: start.addingTimeInterval(5))
        clock.advance(by: 5)
        #expect(await test.value == .failure(.timeout))
        #expect(server.transports.withLock { $0.allSatisfy(\.isClosed) })
    }

    @Test func aSlowSnapshotTimesOutOnTheSameDeadline() async {
        let clock = SteppingClock(now: start)
        let server = ScriptedTransportFactory(frames: [authRequired, authOK])
        let test = Task {
            await HomeController.testConnection(server: HomeSample.server, token: HomeSample.token, transport: server, timeout: 5, clock: clock)
        }
        await clock.waitForSleeper(until: start.addingTimeInterval(5))
        clock.advance(by: 5)
        #expect(await test.value == .failure(.timeout))
    }

    @Test func aServerThatSkipsAuthIsUnexpected() async {
        let server = ScriptedTransportFactory(frames: [authOK])
        let result = await HomeController.testConnection(server: HomeSample.server, token: HomeSample.token, transport: server)
        guard case .failure(.unexpectedReply) = result else {
            Issue.record("expected unexpectedReply, got \(result)")
            return
        }
    }

    @Test func aRefusedSnapshotIsUnexpected() async {
        let refusal = frame([
            "id": .number(1),
            "type": .string("result"),
            "success": .bool(false),
            "error": .object(["code": .string("unauthorized"), "message": .string("Unauthorized")]),
        ])
        let server = ScriptedTransportFactory(frames: [authRequired, authOK, refusal])
        let result = await HomeController.testConnection(server: HomeSample.server, token: HomeSample.token, transport: server)
        #expect(result == .failure(.unexpectedReply("unauthorized: Unauthorized")))
    }
}
