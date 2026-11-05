import Foundation
import ImageIO
import os
import PaneCore

/// One slot's photo, decoded. Every layer showing the slot shares it, and it is freed with the last.
final class DecodedPhoto: Sendable {
    let key: PhotoKey
    let image: CGImage

    init(key: PhotoKey, image: CGImage) {
        self.key = key
        self.image = image
    }
}

/// Decodes the bundled `<slot>.heic` photos with ImageIO rather than `UIImage(named:)`, whose cache
/// would keep every photo ever shown and break the flat-memory check.
@MainActor
enum PhotoStore {
    private struct Shown {
        weak var photo: DecodedPhoto?
    }

    private static var shown: [PhotoKey: Shown] = [:]
    /// Slots whose decode failed, with when to try again; a memory spike can fail one decode.
    private static var unreadable: [PhotoKey: Date] = [:]
    private static var decoding: [PhotoKey: Task<DecodedPhoto?, Never>] = [:]
    static let retryAfter: TimeInterval = 600
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "pane", category: "background")

    /// The photo if a layer still shows it, so a second background (Settings) appears at once.
    static func cached(_ key: PhotoKey) -> DecodedPhoto? {
        shown[key]?.photo
    }

    /// Nil for a missing or unreadable photo, logged the first time. A caller asking for a slot
    /// already being decoded joins that decode, so a target that flips back and forth decodes once.
    static func load(_ key: PhotoKey) async -> DecodedPhoto? {
        if let photo = cached(key) { return photo }
        if let retry = unreadable[key], retry > .now { return nil }
        guard let url = Bundle.main.url(forResource: key.name, withExtension: "heic") else {
            if unreadable[key] == nil { log.error("Photo \(key.name, privacy: .public).heic is missing; showing the gradient") }
            unreadable[key] = .distantFuture
            return nil
        }
        let task = decoding[key] ?? Task.detached(priority: .userInitiated) {
            decode(url).map { DecodedPhoto(key: key, image: $0) }
        }
        decoding[key] = task
        let decoded = await task.value
        decoding[key] = nil
        if let photo = cached(key) { return photo }
        guard let decoded else {
            if unreadable[key] == nil { log.error("Photo \(key.name, privacy: .public).heic did not decode; showing the gradient") }
            unreadable[key] = .now.addingTimeInterval(retryAfter)
            return nil
        }
        unreadable[key] = nil
        shown = shown.filter { $0.value.photo != nil }
        shown[key] = Shown(photo: decoded)
        return decoded
    }

    nonisolated private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
