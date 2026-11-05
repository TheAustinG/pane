// Usage: swift scripts/blur-photo.swift <out-dir> <image>...
// Crops each image to 16:9 around its center, scales it to 1920x1080, blurs it with a Gaussian
// of sigma 24 px and writes <out-dir>/<image name>.heic. Edges are clamped before the blur so
// they do not darken.
import CoreImage
import Foundation
import ImageIO

let width = 1920.0
let height = 1080.0
let sigma = 24.0
let quality = 0.6

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2 else { fail("usage: blur-photo.swift <out-dir> <image>...") }
let outDirectory = URL(fileURLWithPath: arguments[arguments.startIndex], isDirectory: true)
let context = CIContext()
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

for path in arguments.dropFirst() {
    let input = URL(fileURLWithPath: path)
    guard let source = CIImage(contentsOf: input, options: [.applyOrientationProperty: true]) else {
        fail("cannot read \(path)")
    }
    let extent = source.extent
    guard extent.width > 0, extent.height > 0 else { fail("empty image \(path)") }

    let scale = max(width / extent.width, height / extent.height)
    let scaled = source
        .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        .applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0,
        ])
    let box = CGRect(
        x: ((scaled.extent.width - width) / 2).rounded(),
        y: ((scaled.extent.height - height) / 2).rounded(),
        width: width,
        height: height
    )
    let frame = CGRect(x: 0, y: 0, width: width, height: height)
    let cropped = scaled
        .cropped(to: box)
        .transformed(by: CGAffineTransform(translationX: -box.minX, y: -box.minY))
    let blurred = cropped
        .clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: sigma])
        .cropped(to: frame)

    let output = outDirectory.appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".heic")
    do {
        try context.writeHEIFRepresentation(
            of: blurred,
            to: output,
            format: .RGBA8,
            colorSpace: colorSpace,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        )
    } catch {
        fail("cannot write \(output.path): \(error.localizedDescription)")
    }
}
