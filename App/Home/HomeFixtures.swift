#if DEBUG
import PaneCore

/// Sample entities for repeatable Home card states. Invented names and ids only.
enum HomeFixtures {
    static let entities: [HAEntity] = []
    static let selection = HomeSelection.empty

    static func overrides(raising kind: HomeNudgeKind, selection: HomeSelection) -> [String: HAEntity] {
        [:]
    }
}
#endif
