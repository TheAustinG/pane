import Foundation
import ImageIO
import Testing
@testable import PaneCore

/// The shipped photo set in `App/Photos/`: a credit and a 1920x1080 HEIC for every slot.
@Suite("Photo catalog")
struct PhotoCatalogTests {
    static let photos = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../../../App/Photos", directoryHint: .isDirectory)
        .standardizedFileURL

    @Test func creditsCoverEverySlot() throws {
        let data = try Data(contentsOf: Self.photos.appending(path: "photo-credits.json"))
        let credits = try PhotoCredits.decode(data)
        #expect(credits.missingSlots().map(\.name) == [])
        #expect(credits.photos.count == PhotoKey.all.count)
    }

    @Test(arguments: PhotoKey.all)
    func everySlotHasAFullHDPhoto(_ key: PhotoKey) throws {
        let url = Self.photos.appending(path: "\(key.name).heic")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "no readable \(url.path)")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil), "\(key.name).heic does not decode")
        #expect(image.width == 1920 && image.height == 1080, "\(key.name).heic is \(image.width)x\(image.height)")
    }
}
