import Foundation

/// One shipped photo's source and license, from `photo-credits.json` in the app bundle.
public struct PhotoCredit: Hashable, Sendable, Codable {
    /// A `PhotoKey.name`.
    public var slot: String
    public var title: String
    public var creator: String
    public var license: String
    public var licenseURL: URL?
    public var sourcePage: URL
    /// The credit line exactly as the license asks for it.
    public var attribution: String

    public init(slot: String, title: String, creator: String, license: String, licenseURL: URL?, sourcePage: URL, attribution: String) {
        self.slot = slot
        self.title = title
        self.creator = creator
        self.license = license
        self.licenseURL = licenseURL
        self.sourcePage = sourcePage
        self.attribution = attribution
    }

    public var key: PhotoKey? { PhotoKey(name: slot) }
}

public struct PhotoCredits: Hashable, Sendable, Codable {
    public var photos: [PhotoCredit]

    public init(photos: [PhotoCredit]) {
        self.photos = photos
    }

    public static func decode(_ data: Data) throws -> PhotoCredits {
        try JSONDecoder().decode(PhotoCredits.self, from: data)
    }

    /// Slots with no credit, in `PhotoKey.all` order.
    public func missingSlots() -> [PhotoKey] {
        let named = Set(photos.map(\.slot))
        return PhotoKey.all.filter { !named.contains($0.name) }
    }
}
