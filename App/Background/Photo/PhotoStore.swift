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
    private static var unreadable: Set<PhotoKey> = []
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "pane", category: "background")

    /// The photo if a layer still shows it, so a second background (Settings) appears at once.
    static func cached(_ key: PhotoKey) -> DecodedPhoto? {
        shown[key]?.photo
    }

    /// Nil for a missing or unreadable photo, logged the first time.
    static func load(_ key: PhotoKey) async -> DecodedPhoto? {
        if let photo = cached(key) { return photo }
        guard !unreadable.contains(key) else { return nil }
        let url = Bundle.main.url(forResource: key.name, withExtension: "heic")
        let decoded = await Task.detached(priority: .userInitiated) {
            url.flatMap(decode).map { DecodedPhoto(key: key, image: $0) }
        }.value
        if let photo = cached(key) { return photo }
        guard let decoded else {
            unreadable.insert(key)
            log.error("Photo \(key.name, privacy: .public).heic is missing or unreadable; showing the gradient")
            return nil
        }
        shown = shown.filter { $0.value.photo != nil }
        shown[key] = Shown(photo: decoded)
        return decoded
    }

    nonisolated private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
