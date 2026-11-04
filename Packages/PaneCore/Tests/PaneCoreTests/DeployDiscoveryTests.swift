import Foundation
import Testing
@testable import PaneCore

private func files(_ names: String...) -> [WorkflowFile] {
    names.map { WorkflowFile(path: ".github/workflows/\($0)", state: "active") }
}

private let publish = files("ci.yml", "publish.yml")

@Suite("Deploy discovery")
struct DeployDiscoveryTests {
    @Test(arguments: [
        ("https://github.com/sample-user/beacon", "sample-user/beacon"),
        ("https://github.com/Sample-User/beacon", "sample-user/beacon"),
        ("https://github.com/SAMPLE-USER/beacon.git", "sample-user/beacon"),
        ("https://github.com/sample-user/beacon.GIT/", "sample-user/beacon"),
        ("http://www.github.com/sample-user/beacon/tree/main", "sample-user/beacon"),
        (" https://GitHub.com/sample-user/beacon ", "sample-user/beacon"),
    ])
    func readsOwnedSources(source: String, repository: String) {
        #expect(DeployDiscovery.repository(source: source, login: "sample-user") == repository)
    }

    @Test(arguments: [
        "https://github.com/example-org/socket-proxy",
        "https://github.com/sample-user-two/beacon",
        "https://gitlab.com/sample-user/beacon",
        "https://github.com/sample-user",
        "git@github.com:sample-user/beacon.git",
        "ftp://github.com/sample-user/beacon",
        "",
        "https://github.com/sample-user/bea con",
    ])
    func ignoresOtherSources(source: String) {
        #expect(DeployDiscovery.repository(source: source, login: "sample-user") == nil)
    }

    @Test func keepsTheLoginsSpelling() {
        #expect(DeployDiscovery.repository(source: "https://github.com/sample-user/Beacon", login: "Sample-User") == "Sample-User/Beacon")
    }

    @Test(arguments: [
        (["ci.yml", "publish.yml"], "publish.yml"),
        (["build.yml", "release.yml", "docker-image.yml"], "docker-image.yml"),
        (["build.yml", "image.yaml"], "image.yaml"),
        (["ci.yml", "deploy.yml", "build.yml", "release.yml"], "release.yml"),
        (["ci.yml", "build.yml", "deploy.yml"], "deploy.yml"),
        (["ci.yml", "Build-Containers.yml"], "Build-Containers.yml"),
        (["publish-docs.yml", "docker.yml"], "publish-docs.yml"),
        (["b-publish.yml", "a-publish.yml"], "a-publish.yml"),
    ])
    func guessesThePublishWorkflow(names: [String], expected: String) {
        let workflows = names.map { WorkflowFile(path: ".github/workflows/\($0)", state: "active") }
        #expect(DeployDiscovery.guessWorkflow(workflows) == expected)
    }

    @Test func noGuessWithoutAKeywordOrWhenDisabled() {
        #expect(DeployDiscovery.guessWorkflow(files("ci.yml", "lint.yml")) == nil)
        #expect(DeployDiscovery.guessWorkflow([]) == nil)
        let disabled = [WorkflowFile(path: ".github/workflows/publish.yml", state: "disabled_manually")] + files("build.yml")
        #expect(DeployDiscovery.guessWorkflow(disabled) == "build.yml")
    }

    @Test func findsCandidatesInTheRecordedContainers() {
        let workflows = ["sample-user/beacon": publish, "sample-user/ledger": publish]
        let candidates = DeployDiscovery.candidates(containers: CodeSample.containers, login: "sample-user", workflows: workflows)
        #expect(candidates == [CodeSample.beacon, CodeSample.ledger])
        #expect(DeployDiscovery.candidates(containers: CodeSample.containers, login: "example-org", workflows: [
            "example-org/socket-proxy": publish, "example-org/hub": files("docker.yml"),
        ]).map(\.repository) == ["example-org/hub", "example-org/socket-proxy"])
    }

    @Test func oneTargetPerRepositoryFromRunningContainers() {
        let containers = [
            CodeSample.container("beacon-web-2"),
            CodeSample.container("beacon-web-1"),
            CodeSample.container("beacon-old", state: "exited"),
            CodeSample.container("orchard", repository: "Sample-User/orchard-ops"),
            CodeSample.container("kite", repository: "sample-user/kite-league"),
            CodeSample.container("proxy", repository: "example-org/proxy"),
            CodeSample.container("plain", repository: nil),
        ]
        let workflows = [
            "sample-user/beacon": publish,
            "sample-user/orchard-ops": files("ci.yml"),
            "sample-user/proxy": publish,
        ]
        let candidates = DeployDiscovery.candidates(containers: containers, login: "sample-user", workflows: workflows)
        #expect(candidates == [DeployTarget(repository: "sample-user/beacon", workflow: "publish.yml", containerName: "beacon-web-1")])
        #expect(DeployDiscovery.ownedContainers(containers, login: "sample-user") == [
            "sample-user/beacon": ["beacon-web-1", "beacon-web-2"],
            "sample-user/orchard-ops": ["orchard"],
            "sample-user/kite-league": ["kite"],
        ])
    }

    @Test func findsTheTargetsContainerOrARecreatedOne() {
        let named = CodeSample.container("beacon-beacon-1")
        let renamed = CodeSample.container("beacon-beacon-2")
        let other = CodeSample.container("ledger", repository: "sample-user/ledger")
        #expect(DeployDiscovery.container(for: CodeSample.beacon, in: [other, renamed, named]) == named)
        #expect(DeployDiscovery.container(for: CodeSample.beacon, in: [other, renamed]) == renamed)
        #expect(DeployDiscovery.container(for: CodeSample.beacon, in: [other]) == nil)
        #expect(DeployDiscovery.container(for: CodeSample.beacon, in: [CodeSample.container("beacon-beacon-1", state: "exited")]) == nil)
    }

    @Test func statusesForTheRecordedState() throws {
        let runs = [
            RunKey(CodeSample.beacon): try #require(try GitHubClient.parseRun(CodeSample.data("github-runs-beacon"), repository: "sample-user/beacon", workflow: "publish.yml")),
            RunKey(CodeSample.ledger): try #require(try GitHubClient.parseRun(CodeSample.data("github-runs-ledger"), repository: "sample-user/ledger", workflow: "publish.yml")),
        ]
        let statuses = DeployDiscovery.statuses(
            targets: [CodeSample.beacon, CodeSample.ledger],
            containers: CodeSample.containers,
            runs: runs,
            images: [:]
        )
        #expect(statuses.map(\.verdict) == [.current, .behind(builtAt: CodeSample.ledgerBuiltAt)])
        #expect(statuses.map { $0.container?.name } == ["beacon-beacon-1", "ledger"])
        #expect(statuses.map(\.run) == [runs[RunKey(CodeSample.beacon)], runs[RunKey(CodeSample.ledger)]])
    }

    @Test func statusesUseImageInspectWithoutALabel() {
        let imageID = "sha256:" + String(repeating: "e", count: 64)
        let container = CodeSample.container("beacon-beacon-1", imageID: imageID)
        let run = PublishRun(repository: "sample-user/beacon", workflow: "publish.yml", headSHA: String(repeating: "a", count: 40), completedAt: CodeSample.beaconBuiltAt)
        let old = PortainerImage(created: CodeSample.beaconBuiltAt.addingTimeInterval(-86400), labels: [:])
        let fresh = PortainerImage(created: nil, labels: [RevisionComparison.revisionLabel: String(repeating: "a", count: 40)])
        let statuses: ([String: PortainerImage]) -> [DeployVerdict] = { images in
            DeployDiscovery.statuses(targets: [CodeSample.beacon], containers: [container], runs: [RunKey(CodeSample.beacon): run], images: images).map(\.verdict)
        }
        #expect(statuses([imageID: old]) == [.behind(builtAt: CodeSample.beaconBuiltAt)])
        #expect(statuses([imageID: fresh]) == [.current])
        #expect(statuses([:]) == [.unknown])
        #expect(DeployDiscovery.needsImage(container))
        #expect(!DeployDiscovery.needsImage(CodeSample.container("x", revision: String(repeating: "a", count: 40))))
    }

    @Test func nudgesAreBehindStatusesNewestFirst() {
        let older = DeployStatus(target: CodeSample.beacon, run: nil, container: nil, verdict: .behind(builtAt: CodeSample.beaconBuiltAt))
        let current = DeployStatus(target: CodeSample.ledger, run: nil, container: nil, verdict: .current)
        let newer = DeployStatus(
            target: DeployTarget(repository: "sample-user/kite", workflow: "build.yml", containerName: "kite"),
            run: nil, container: nil, verdict: .behind(builtAt: CodeSample.ledgerBuiltAt)
        )
        let fallback = CodeSample.start
        #expect(DeployDiscovery.nudges(statuses: [older, current, newer], enabled: true, debugNudge: nil, fallbackBuiltAt: fallback) == [newer, older])
        #expect(DeployDiscovery.nudges(statuses: [older, newer], enabled: false, debugNudge: nil, fallbackBuiltAt: fallback) == [])
        #expect(DeployDiscovery.nudges(statuses: [older, newer], enabled: true, debugNudge: false, fallbackBuiltAt: fallback) == [])
        #expect(DeployDiscovery.nudges(statuses: [current], enabled: false, debugNudge: true, fallbackBuiltAt: fallback) == [])
    }

    @Test func debugNudgeRaisesTheFirstTarget() {
        let run = PublishRun(repository: "sample-user/ledger", workflow: "publish.yml", headSHA: "abcdef1", completedAt: CodeSample.ledgerBuiltAt)
        let current = DeployStatus(target: CodeSample.ledger, run: run, container: nil, verdict: .current)
        let unknown = DeployStatus(target: CodeSample.beacon, run: nil, container: nil, verdict: .unknown)
        let fallback = CodeSample.start.addingTimeInterval(-3 * 3600)
        #expect(DeployDiscovery.nudges(statuses: [current, unknown], enabled: true, debugNudge: true, fallbackBuiltAt: fallback)
            == [DeployStatus(target: CodeSample.ledger, run: run, container: nil, verdict: .behind(builtAt: CodeSample.ledgerBuiltAt))])
        #expect(DeployDiscovery.nudges(statuses: [unknown, current], enabled: true, debugNudge: true, fallbackBuiltAt: fallback)
            == [DeployStatus(target: CodeSample.beacon, run: nil, container: nil, verdict: .behind(builtAt: fallback))])
        #expect(DeployDiscovery.nudges(statuses: [], enabled: true, debugNudge: true, fallbackBuiltAt: fallback) == [])
    }
}
