#!/usr/bin/env swift

import AppKit

// Generate a FlowX app icon using Core Graphics
func generateIcon() {
    let sizes: [(CGFloat, String)] = [
        (16, "icon_16x16"),
        (32, "icon_16x16@2x"),
        (32, "icon_32x32"),
        (64, "icon_32x32@2x"),
        (128, "icon_128x128"),
        (256, "icon_128x128@2x"),
        (256, "icon_256x256"),
        (512, "icon_256x256@2x"),
        (512, "icon_512x512"),
        (1024, "icon_512x512@2x"),
    ]

    let iconsetPath = "/tmp/FlowX.iconset"
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

    // Convert iconset to icns
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
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Helper to draw a single 7-bar waveform
    func drawWaveform(context: CGContext, canvasSize: CGFloat, color: CGColor) {
        let barCount = 7
        let centerY = canvasSize * 0.5
        let totalWidth = canvasSize * 0.7
        let barWidth = totalWidth / CGFloat(barCount * 2 - 1)
        let startX = (canvasSize - totalWidth) / 2.0
        
        let barHeights: [CGFloat] = [0.3, 0.5, 0.7, 0.95, 0.7, 0.5, 0.3]
        
        for i in 0..<barCount {
            let x = startX + CGFloat(i) * barWidth * 2
            let h = canvasSize * barHeights[i]
            let y = centerY - h / 2
            let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
            let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
            
            context.saveGState()
            // Strong dark drop shadow so it works on all desktop wallpapers
            context.setShadow(offset: CGSize(width: 0, height: -canvasSize * 0.01), blur: canvasSize * 0.03, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
            context.setFillColor(color)
            context.addPath(barPath)
            context.fillPath()
            context.restoreGState()
        }
    }

    // Draw two intersecting waveforms to form the "X"
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: size / 2)
    ctx.rotate(by: .pi / 4) // 45 degrees
    ctx.translateBy(x: -size / 2, y: -size / 2)
    drawWaveform(context: ctx, canvasSize: size, color: CGColor(red: 0.1, green: 0.8, blue: 1.0, alpha: 0.95)) // Cyan
    ctx.restoreGState()
    
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: size / 2)
    ctx.rotate(by: -.pi / 4) // -45 degrees
    ctx.translateBy(x: -size / 2, y: -size / 2)
    drawWaveform(context: ctx, canvasSize: size, color: CGColor(red: 0.6, green: 0.1, blue: 1.0, alpha: 0.95)) // Purple
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

generateIcon()
