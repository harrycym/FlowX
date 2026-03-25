#!/usr/bin/env swift

import AppKit

func generateIcon() {
    let sizes: [(CGFloat, String)] = [
        (16,   "icon_16x16"),
        (32,   "icon_16x16@2x"),
        (32,   "icon_32x32"),
        (64,   "icon_32x32@2x"),
        (128,  "icon_128x128"),
        (256,  "icon_128x128@2x"),
        (256,  "icon_256x256"),
        (512,  "icon_256x256@2x"),
        (512,  "icon_512x512"),
        (1024, "icon_512x512@2x"),
    ]

    let iconsetPath = "/tmp/NimbusGlide.iconset"
    let fm = FileManager.default
    try? fm.removeItem(atPath: iconsetPath)
    try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    for (size, name) in sizes {
        let image = renderIcon(size: size)
        let pngData = image.tiffRepresentation.flatMap {
            NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
        }
        let path = "\(iconsetPath)/\(name).png"
        try! pngData!.write(to: URL(fileURLWithPath: path))
    }

    let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon.icns"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetPath, "-o", outputPath]
    try! process.run()
    process.waitUntilExit()

    try? fm.removeItem(atPath: iconsetPath)
    print("Icon generated: \(outputPath)")
}

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    let padding = size * 0.04
    let iconRect = CGRect(x: padding, y: padding, width: size - padding * 2, height: size - padding * 2)

    // --- Background circle: deep indigo-to-purple gradient ---
    let bgGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.38, green: 0.20, blue: 0.92, alpha: 1.0), // indigo
            CGColor(red: 0.62, green: 0.18, blue: 0.95, alpha: 1.0), // purple
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.saveGState()
    ctx.addEllipse(in: iconRect)
    ctx.clip()
    ctx.drawLinearGradient(bgGradient,
        start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.midX, y: iconRect.minY),
        options: [])
    ctx.restoreGState()

    // --- Soft inner glow at top-left ---
    let glowColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12)
    let glowGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [glowColor, CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.saveGState()
    ctx.addEllipse(in: iconRect)
    ctx.clip()
    ctx.drawRadialGradient(glowGradient,
        startCenter: CGPoint(x: iconRect.minX + iconRect.width * 0.35, y: iconRect.maxY - iconRect.height * 0.25),
        startRadius: 0,
        endCenter: CGPoint(x: iconRect.midX, y: iconRect.midY),
        endRadius: size * 0.55,
        options: [])
    ctx.restoreGState()

    // --- Waveform bars: 5 bars, white with slight transparency ---
    let barCount = 5
    let barHeights: [CGFloat] = [0.28, 0.50, 0.70, 0.50, 0.28]
    let waveAreaWidth = size * 0.46
    let barWidth = waveAreaWidth / CGFloat(barCount * 2 - 1)
    let startX = (size - waveAreaWidth) / 2.0
    let centerY = size * 0.5

    for i in 0..<barCount {
        let x = startX + CGFloat(i) * barWidth * 2
        let h = size * barHeights[i]
        let y = centerY - h / 2
        let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
        let barPath = CGPath(roundedRect: barRect,
            cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)

        // White-to-light-cyan gradient on the bars
        let barGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
                CGColor(red: 0.75, green: 0.90, blue: 1.0, alpha: 0.90),
            ] as CFArray,
            locations: [0.0, 1.0]
        )!

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01),
                      blur: size * 0.025,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))
        ctx.addPath(barPath)
        ctx.clip()
        ctx.drawLinearGradient(barGradient,
            start: CGPoint(x: x, y: y + h),
            end: CGPoint(x: x, y: y),
            options: [])
        ctx.restoreGState()
    }

    image.unlockFocus()
    return image
}

generateIcon()
