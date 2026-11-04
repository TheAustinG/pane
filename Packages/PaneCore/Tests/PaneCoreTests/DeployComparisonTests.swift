import Foundation
import Testing
@testable import PaneCore

private let runSHA = "399d8f03a09a72556113bc3431c44f5c0c3a783b"
private let otherSHA = "5b2a4c667340e6814a6f798aebfa6711cad4781b"
private let completedAt = CodeSample.date("2026-09-26T05:17:29Z")
private let run = PublishRun(repository: "sample-user/beacon", workflow: "publish.yml", headSHA: runSHA, completedAt: completedAt)

private func at(_ offset: TimeInterval) -> String {
    CodeDate.string(completedAt.addingTimeInterval(offset))
}

struct ComparisonCase: CustomTestStringConvertible, Sendable {
    let name: String
    let revision: String?
    let created: String?
    let imageRevision: String?
    let imageCreated: TimeInterval?
    let verdict: DeployVerdict

    init(_ name: String, revision: String? = nil, created: String? = nil, imageRevision: String? = nil, imageCreated: TimeInterval? = nil, _ verdict: DeployVerdict) {
        self.name = name
        self.revision = revision
        self.created = created
        self.imageRevision = imageRevision
        self.imageCreated = imageCreated
        self.verdict = verdict
    }

    var testDescription: String { name }
}

private let behind = DeployVerdict.behind(builtAt: completedAt)

private let cases: [ComparisonCase] = [
    ComparisonCase("full sha match", revision: runSHA, .current),
    ComparisonCase("label is a 7 digit prefix", revision: "399d8f0", .current),
    ComparisonCase("label is longer than a short run sha", revision: runSHA, .current),
    ComparisonCase("uppercase label", revision: runSHA.uppercased(), .current),
    ComparisonCase("mismatch", revision: otherSHA, created: at(-3 * 86400), behind),
    ComparisonCase("mismatch without a created time", revision: otherSHA, behind),
    ComparisonCase("mismatch built just after the run", revision: otherSHA, created: at(4 * 60), behind),
    ComparisonCase("newer local build", revision: otherSHA, created: at(6 * 60), .unknown),
    ComparisonCase("newer local build from image inspect", revision: otherSHA, imageCreated: 3600, .unknown),
    ComparisonCase("six digit label is no revision", revision: "399d8f", created: at(-60), .current),
    ComparisonCase("non-hex label is no revision", revision: "latest", created: at(-86400), behind),
    ComparisonCase("image inspect revision", imageRevision: runSHA, .current),
    ComparisonCase("container label beats image inspect", revision: otherSHA, imageRevision: runSHA, behind),
    ComparisonCase("no label, built during the run", created: at(-30), .current),
    ComparisonCase("no label, built at the window edge", created: at(-10 * 60), .current),
    ComparisonCase("no label, built before the window", created: at(-10 * 60 - 1), behind),
    ComparisonCase("no label, built long before", created: at(-30 * 86400), behind),
    ComparisonCase("no label, built after", created: at(3600), .current),
    ComparisonCase("no label, image inspect time before", imageCreated: -3600, behind),
    ComparisonCase("no label, image inspect time after", imageCreated: -60, .current),
    ComparisonCase("container label time beats image inspect", created: at(-60), imageCreated: -86400, .current),
    ComparisonCase("nothing to compare", .unknown),
    ComparisonCase("unreadable created label", created: "yesterday", .unknown),
]

@Suite("Deploy revision comparison")
struct DeployComparisonTests {
    @Test(arguments: cases)
    func verdicts(_ test: ComparisonCase) {
        var labels: [String: String] = [:]
        if let revision = test.revision { labels[RevisionComparison.revisionLabel] = revision }
        if let created = test.created { labels[RevisionComparison.createdLabel] = created }
        let container = PortainerContainer(
            id: "c1", name: "beacon", image: "ghcr.io/sample-user/beacon:latest", imageID: "sha256:aa",
            state: "running", created: completedAt.addingTimeInterval(86400), labels: labels
        )
        let shortRun = test.name == "label is longer than a short run sha"
            ? PublishRun(repository: run.repository, workflow: run.workflow, headSHA: "399d8f0", completedAt: completedAt)
            : run
        let verdict = RevisionComparison.verdict(
            run: shortRun,
            container: container,
            imageRevision: test.imageRevision,
            imageCreated: test.imageCreated.map { completedAt.addingTimeInterval($0) }
        )
        #expect(verdict == test.verdict)
    }

    @Test func missingRunOrContainerIsUnknown() {
        let container = CodeSample.container("beacon", revision: otherSHA)
        #expect(RevisionComparison.verdict(run: nil, container: container) == .unknown)
        #expect(RevisionComparison.verdict(run: run, container: nil) == .unknown)
        #expect(RevisionComparison.verdict(run: nil, container: nil) == .unknown)
    }

    @Test func prefixMatching() {
        #expect(RevisionComparison.revision("399d8f0", matches: runSHA))
        #expect(RevisionComparison.revision(runSHA, matches: "399d8f0"))
        #expect(RevisionComparison.revision(" 399D8F03 ", matches: runSHA))
        #expect(!RevisionComparison.revision("399d8f", matches: runSHA))
        #expect(!RevisionComparison.revision("399d8f1", matches: runSHA))
        #expect(!RevisionComparison.revision("", matches: ""))
        #expect(!RevisionComparison.revision("zzzzzzz", matches: "zzzzzzz"))
    }

    @Test func readsDockerAndGitHubTimestamps() {
        let expected = Date(timeIntervalSince1970: 1_790_399_817)
        #expect(CodeDate.parse("2026-09-26T05:16:57Z") == expected)
        #expect(abs(CodeDate.parse("2026-09-26T05:16:57.194Z")!.timeIntervalSince(expected) - 0.194) < 0.0005)
        #expect(abs(CodeDate.parse("2026-09-26T05:16:57.941394352Z")!.timeIntervalSince(expected) - 0.941) < 0.0005)
        #expect(CodeDate.parse("2026-09-26 05:16:57+00:00") == expected)
        #expect(CodeDate.parse("2026-09-26T00:16:57-05:00") == expected)
        #expect(CodeDate.parse("2026-09-26") == nil)
        #expect(CodeDate.parse("") == nil)
        #expect(CodeDate.string(expected) == "2026-09-26T05:16:57Z")
    }
}
