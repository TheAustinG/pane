#if DEBUG
import Darwin
import Foundation
import os
import PaneCore

/// `-photoCycle <seconds>`: pins the photo to each slot in turn and, after every crossfade, logs
/// the memory footprint, so a long run shows whether decoded photos are released.
@MainActor
enum PhotoCycle {
    private static var isRunning = false
    private static var crossfades = 0
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "pane", category: "photo-cycle")

    static func run(model: AppModel, interval: Double?) async {
        guard let interval, interval > 0, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        var step = 0
        while !Task.isCancelled {
            model.photoOverride = PhotoKey.all[step % PhotoKey.all.count]
            step += 1
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    static func crossfadeEnded(to target: BackgroundTarget) {
        guard isRunning else { return }
        crossfades += 1
        let footprint = footprintMB.map { String(format: "%.1f", $0) } ?? "unknown"
        let line = "photo-cycle n=\(crossfades) key=\(target.name) footprintMB=\(footprint)"
        log.notice("\(line, privacy: .public)")
        try? FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8))
    }

    private static var footprintMB: Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }
}
#endif
