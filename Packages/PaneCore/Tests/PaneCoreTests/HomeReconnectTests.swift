import Foundation
import Testing
@testable import PaneCore

private let start = HomeSample.start

private func pings(_ snapshot: FixtureHATransportFactory.Snapshot) -> Int {
    snapshot.received.filter { $0.contains(#""type":"ping""#) }.count
}

/// Defaults under test: the first retry after a drop waits 1 s, each failure since the last good
/// connection doubles the wait up to 30 s, and a good connection starts the count again. The
/// heartbeat pings every 30 s and drops a socket that sends nothing within 10 s of a ping.
@Suite("Home reconnect", .timeLimit(.minutes(1)))
@MainActor
struct HomeReconnectTests {
    @Test func backoffDoublesToTheCapWhileTheServerIsDown() async {
        let harness = HomeHarness()
        harness.fixture.refusesConnections = true
        let controller = harness.controller
        harness.launch()

        var retryAt = start
        var expectedHistory: [HomeConnection] = []
        for delay: TimeInterval in [1, 2, 4, 8, 16, 30, 30] {
            retryAt = retryAt.addingTimeInterval(delay)
            let expected = HomeConnection.disconnected(since: start, retryAt: retryAt)
            expectedHistory += [.connecting, expected]
            await waitUntil { controller.connection == expected }
            await harness.clock.waitForSleeper(until: retryAt)
            harness.clock.advance(by: delay)
        }
        let last = HomeConnection.disconnected(since: start, retryAt: retryAt.addingTimeInterval(30))
        await waitUntil { controller.connection == last }
        #expect(harness.fixture.connectionsOpened == 8)
        #expect(controller.connectionHistory == expectedHistory + [.connecting, last])

        harness.fixture.refusesConnections = false
        await harness.clock.waitForSleeper(until: retryAt.addingTimeInterval(30))
        harness.clock.advance(by: 30)
        await waitUntil { controller.connection.isConnected }
        #expect(controller.reconnectCount == 0)
        await harness.stop()
    }

    @Test func aGoodConnectionResetsTheBackoff() async {
        let harness = HomeHarness()
        harness.fixture.refusesConnections = true
        let controller = harness.controller
        harness.launch()
        for delay: TimeInterval in [1, 2, 4] {
            await waitUntil { if case .disconnected = controller.connection { true } else { false } }
            await harness.clock.waitForSleeper(until: harness.clock.now.addingTimeInterval(delay))
            if delay == 4 { harness.fixture.refusesConnections = false }
            harness.clock.advance(by: delay)
        }
        await waitUntil { controller.connection.isConnected }
        let connectedAt = harness.clock.now
        #expect(connectedAt == start.addingTimeInterval(7))

        harness.fixture.dropConnections()
        await waitUntil { controller.connection == .disconnected(since: connectedAt, retryAt: connectedAt.addingTimeInterval(1)) }
        await harness.clock.waitForSleeper(until: connectedAt.addingTimeInterval(1))
        harness.clock.advance(by: 1)
        await waitUntil { controller.connection.isConnected }
        #expect(controller.reconnectCount == 1)
        await harness.stop()
    }

    @Test func aForcedDropReconnectsWithinThirtySecondsOnItsOwn() async throws {
        let harness = HomeHarness(backoff: ReconnectBackoff())
        await harness.connect()
        let controller = harness.controller

        controller.forceDisconnect()
        await waitUntil { if case .disconnected = controller.connection { true } else { false } }
        guard case .disconnected(let since, let retryAt?) = controller.connection else {
            Issue.record("expected a scheduled retry")
            return
        }
        let delay = retryAt.timeIntervalSince(since)
        #expect(since == start)
        #expect(delay >= 1 && delay <= 1.2)

        await harness.clock.waitForSleeper(until: retryAt)
        harness.clock.advance(by: delay + 0.001)
        await waitUntil { controller.connection.isConnected }
        #expect(harness.clock.now.timeIntervalSince(since) < 30)
        #expect(controller.reconnectCount == 1)
        #expect(harness.fixture.connectionsOpened == 2)
        #expect(harness.fixture.snapshot.openConnections == 1)
        await harness.stop()
    }

    @Test func authInvalidStopsRetriesUntilConfigured() async throws {
        let harness = HomeHarness(token: "wrong-token")
        let controller = harness.controller
        harness.launch()
        await waitUntil { controller.connection == .authFailed }
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(HomeController.idleInterval))

        harness.clock.advance(by: 2 * HomeController.idleInterval)
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(3 * HomeController.idleInterval))
        #expect(controller.connection == .authFailed)
        #expect(harness.fixture.connectionsOpened == 1)
        #expect(!harness.fixture.snapshot.received.contains { $0.contains("wrong-token") })

        try controller.configure(server: HomeSample.server, token: HomeSample.token)
        await waitUntil { controller.connection.isConnected }
        #expect(harness.fixture.connectionsOpened == 2)
        await harness.stop()
    }

    @Test func configureDuringBackoffConnectsAtOnce() async throws {
        let harness = HomeHarness()
        harness.fixture.refusesConnections = true
        let controller = harness.controller
        harness.launch()
        await waitUntil { controller.connection == .disconnected(since: start, retryAt: start.addingTimeInterval(1)) }
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(1))

        harness.fixture.refusesConnections = false
        try controller.configure(server: HomeSample.server, token: HomeSample.token)
        await waitUntil { controller.connection.isConnected }
        #expect(harness.clock.now == start)
        await harness.stop()
    }

    @Test func aPongKeepsTheSocket() async {
        let harness = HomeHarness()
        await harness.connect()
        let controller = harness.controller

        harness.clock.advance(by: 30)
        await harness.fixture.waitUntil { pings($0) == 1 && $0.isIdle }
        #expect(harness.received.last?["id"]?.int == 3)
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(40))
        harness.clock.advance(by: 10)
        // The next ping shares its deadline with the nudge tick.
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(60), count: 2)
        #expect(controller.connection.isConnected)
        #expect(harness.fixture.connectionsOpened == 1)
        await harness.stop()
    }

    @Test func noPongMeansADeadSocket() async {
        let harness = HomeHarness()
        await harness.connect()
        let controller = harness.controller
        harness.fixture.respondsToPings = false

        harness.clock.advance(by: 30)
        await harness.fixture.waitUntil { pings($0) == 1 && $0.isIdle }
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(40))
        harness.clock.advance(by: 10)
        let dropped = HomeConnection.disconnected(since: start.addingTimeInterval(40), retryAt: start.addingTimeInterval(41))
        await waitUntil { controller.connection == dropped }
        #expect(harness.fixture.snapshot.openConnections == 0)

        await harness.clock.waitForSleeper(until: start.addingTimeInterval(41))
        harness.clock.advance(by: 1)
        await waitUntil { controller.connection.isConnected }
        #expect(controller.reconnectCount == 1)
        #expect(harness.fixture.connectionsOpened == 2)
        await harness.stop()
    }

    @Test func anyFrameCountsAsLife() async {
        let harness = HomeHarness()
        await harness.connect()
        harness.fixture.respondsToPings = false

        harness.clock.advance(by: 30)
        await harness.fixture.waitUntil { pings($0) == 1 }
        harness.fixture.setState("light.pantry", to: "on")
        await harness.fixture.waitUntil { $0.isIdle }
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(40))
        harness.clock.advance(by: 10)
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(60), count: 2)
        #expect(harness.controller.connection.isConnected)
        #expect(harness.fixture.connectionsOpened == 1)
        await harness.stop()
    }

    @Test func aSilentServerTimesOutTheHandshake() async throws {
        let clock = SteppingClock(now: start)
        let server = ScriptedTransportFactory()
        let secrets = InMemorySecretStore()
        let controller = HomeController(store: InMemoryKeyValueStore(), secrets: secrets, transport: server, clock: clock, backoff: ReconnectBackoff(jitter: 0))
        try controller.configure(server: HomeSample.server, token: HomeSample.token)
        let task = Task { await controller.run() }

        await clock.waitForSleeper(until: start.addingTimeInterval(HomeController.requestTimeout))
        #expect(controller.connection == .connecting)
        clock.advance(by: HomeController.requestTimeout)
        let timedOut = start.addingTimeInterval(HomeController.requestTimeout)
        await waitUntil { controller.connection == .disconnected(since: timedOut, retryAt: timedOut.addingTimeInterval(1)) }
        #expect(server.transports.withLock { $0.allSatisfy(\.isClosed) })
        task.cancel()
        await task.value
    }
}
