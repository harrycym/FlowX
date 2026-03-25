import AppKit

class CursorManager {
    private static var animationTimer: Timer?
    private static var animationFrame = 0
    private static var currentMode: CursorMode = .normal

    enum CursorMode {
        case normal
        case recording
        case processing
    }

    // MARK: - Public API

    static func showRecordingCursor() {
        guard currentMode != .recording else { return }
        stopAnimation()
        currentMode = .recording
        animationFrame = 0
        pushCursor(for: .recording, frame: 0)
        startAnimation()
    }

    static func showProcessingCursor() {
        guard currentMode != .processing else { return }
        stopAnimation()
        currentMode = .processing
        animationFrame = 0
        pushCursor(for: .processing, frame: 0)
        startAnimation()
    }

    static func restoreCursor() {
        stopAnimation()
        if currentMode != .normal {
            NSCursor.pop()
            currentMode = .normal
        }
    }

    // MARK: - Animation

    private static func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { _ in
            animationFrame += 1
            updateCursor()
        }
    }

    private static func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private static func updateCursor() {
        let cursor = buildCursor(for: currentMode, frame: animationFrame)
        cursor.set()
    }

    private static func pushCursor(for mode: CursorMode, frame: Int) {
        let cursor = buildCursor(for: mode, frame: frame)
        cursor.push()
    }

    // MARK: - Cursor rendering

    private static func buildCursor(for mode: CursorMode, frame: Int) -> NSCursor {
        let size: CGFloat = 28
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            switch mode {
            case .recording:
                drawRecordingCursor(in: rect, size: size, frame: frame)
            case .processing:
                drawProcessingCursor(in: rect, size: size, frame: frame)
            case .normal:
                break
            }
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    // MARK: - Recording cursor: indigo→violet gradient circle with waveform bars

    private static func drawRecordingCursor(in rect: NSRect, size: CGFloat, frame: Int) {
        let circleRect = rect.insetBy(dx: 1, dy: 1)

        // Gradient background circle
        let path = NSBezierPath(ovalIn: circleRect)
        path.addClip()

        // Indigo to violet gradient
        let gradient = NSGradient(colors: [
            NSColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 0.9),  // #6366F1
            NSColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 0.9),  // #8B5CF6
        ])
        gradient?.draw(in: circleRect, angle: 135)

        // Draw 5 waveform bars in white
        let barCount = 5
        let barWidth: CGFloat = 2.2
        let barSpacing: CGFloat = 3.2
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * (barSpacing - barWidth)
        let startX = (size - totalWidth) / 2

        let phase = Double(frame) * 0.18

        for i in 0..<barCount {
            let wave1 = sin(phase + Double(i) * 0.9) * 0.5 + 0.5
            let wave2 = sin(phase * 1.3 + Double(i) * 0.6) * 0.3 + 0.5
            let normalizedHeight = (wave1 + wave2) / 2
            let barHeight = 3.0 + CGFloat(normalizedHeight) * 10.0
            let x = startX + CGFloat(i) * barSpacing
            let y = (size - barHeight) / 2

            let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            NSColor.white.withAlphaComponent(0.95).setFill()
            barPath.fill()
        }
    }

    // MARK: - Processing cursor: violet→cyan gradient circle with animated dots

    private static func drawProcessingCursor(in rect: NSRect, size: CGFloat, frame: Int) {
        let circleRect = rect.insetBy(dx: 1, dy: 1)

        // Gradient background circle
        let path = NSBezierPath(ovalIn: circleRect)
        path.addClip()

        // Violet to cyan gradient
        let gradient = NSGradient(colors: [
            NSColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 0.9),  // #8B5CF6
            NSColor(red: 0.02, green: 0.71, blue: 0.83, alpha: 0.9),  // #06B6D4
        ])
        gradient?.draw(in: circleRect, angle: 135)

        // Draw 3 animated dots
        let dotCount = 3
        let dotRadius: CGFloat = 2.2
        let dotSpacing: CGFloat = 6.0
        let totalWidth = CGFloat(dotCount - 1) * dotSpacing
        let startX = (size - totalWidth) / 2
        let centerY = size / 2

        let phase = Double(frame) * 0.12

        for i in 0..<dotCount {
            let dotPhase = sin(phase + Double(i) * 1.3) * 0.5 + 0.5
            let scale = 0.6 + dotPhase * 0.4
            let alpha = 0.5 + dotPhase * 0.5
            let x = startX + CGFloat(i) * dotSpacing
            let r = dotRadius * CGFloat(scale)

            let dotRect = NSRect(x: x - r, y: centerY - r, width: r * 2, height: r * 2)
            let dotPath = NSBezierPath(ovalIn: dotRect)
            NSColor.white.withAlphaComponent(CGFloat(alpha)).setFill()
            dotPath.fill()
        }
    }
}
