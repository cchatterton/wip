import AppKit
import Foundation
import ImageIO

let sourceURL = URL(fileURLWithPath: "assets/brand/reference-logo.png")
let outputDirectory = URL(fileURLWithPath: "assets/brand")
guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let source = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fatalError("Could not read reference logo")
}

func crop(_ rect: CGRect) -> CGImage {
    guard let image = source.cropping(to: rect) else { fatalError("Could not crop logo") }
    return image
}

func writePNG(_ image: CGImage, name: String) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode logo")
    }
    try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
}

// The supplied design contains a light three-stroke mark and a separate WIP wordmark.
let mark = crop(CGRect(x: 1376, y: 136, width: 962, height: 1188))
let wordmark = crop(CGRect(x: 136, y: 1376, width: 2066, height: 962))
try writePNG(mark, name: "WIPMark.png")
try writePNG(wordmark, name: "WIPWordmark.png")

let size = 1024
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not make icon canvas")
}
let tile = CGRect(x: 0, y: 0, width: size, height: size)
context.setFillColor(CGColor(red: 0.115, green: 0.120, blue: 0.132, alpha: 1))
context.addPath(CGPath(roundedRect: tile, cornerWidth: 215, cornerHeight: 215, transform: nil))
context.fillPath()

let markHeight: CGFloat = 720
let markWidth = markHeight * CGFloat(mark.width) / CGFloat(mark.height)
let markRect = CGRect(
    x: (CGFloat(size) - markWidth) / 2,
    y: (CGFloat(size) - markHeight) / 2,
    width: markWidth,
    height: markHeight
)
context.draw(mark, in: markRect)
guard let icon = context.makeImage() else { fatalError("Could not render icon") }
try writePNG(icon, name: "WIPIcon-1024.png")
