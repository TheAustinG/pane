// Usage: swift scripts/qr-decode.swift IMAGE
// Prints the payload of each QR code found in IMAGE, one per line.
// Exits 1 if the image cannot be read or contains no QR code.
import CoreImage
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/qr-decode.swift IMAGE\n".utf8))
    exit(2)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = CIImage(contentsOf: url) else {
    FileHandle.standardError.write(Data("error: cannot read image \(url.path)\n".utf8))
    exit(1)
}

let detector = CIDetector(
    ofType: CIDetectorTypeQRCode,
    context: CIContext(),
    options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
)
let payloads = (detector?.features(in: image) ?? [])
    .compactMap { ($0 as? CIQRCodeFeature)?.messageString }

if payloads.isEmpty {
    FileHandle.standardError.write(Data("error: no QR code found\n".utf8))
    exit(1)
}
payloads.forEach { print($0) }
