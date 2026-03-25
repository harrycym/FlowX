import AppKit
import SwiftUI
import Combine

// MARK: - Floating indicator panel (never steals focus, click-through)

class StatusIndicatorPanel: NSPanel {
    private var hostingView: NSHostingView<StatusPillView>!
    private var cancellables = Set<AnyCancellable>()
    private let pillState = PillState()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 32),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none

        hostingView = NSHostingView(rootView: StatusPillView(pillState: pillState))
        hostingView.frame = contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.layer?.backgroundColor = .clear
        contentView?.addSubview(hostingView)

        positionOnScreen()

        // Re-position if the screen arrangement changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.positionOnScreen()
        }
    }

    func bind(to pipelineState: PipelineState) {
        pipelineState.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.handleStatus(status)
            }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private func handleStatus(_ status: PipelineStatus) {
        switch status {
        case .recording:
            pillState.mode = .recording
            showAnimated()
        case .processing:
            pillState.mode = .processing
            showAnimated()
        case .idle, .error:
            hideAnimated()
        }
    }

    private func showAnimated() {
        guard !isVisible else {
            // Already visible — just update content (mode already set)
            return
        }
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    private func hideAnimated() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.pillState.mode = .idle
        })
    }

    private func positionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame  // excludes menu bar & dock

        // Use hardcoded pill width so centering isn't affected by
        // frame.width being unreliable before layout completes
        let pillWidth: CGFloat = 64
        let x = screen.frame.midX - pillWidth / 2
        let y = visibleFrame.minY + 20
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - SwiftUI pill view

enum IndicatorMode {
    case idle
    case recording
    case processing
}

class PillState: ObservableObject {
    @Published var mode: IndicatorMode = .idle
}

struct StatusPillView: View {
    @ObservedObject var pillState: PillState

    // Waveform animation
    @State private var wavePhase: Double = 0
    // Dot animation
    @State private var dotPhase: Double = 0

    private let waveTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    private let dotTimer = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            if pillState.mode != .idle {
                pillBackground
                    .overlay(pillContent)
                    .transition(.opacity)
            }
        }
        .frame(width: 64, height: 32)
        .onReceive(waveTimer) { _ in
            if pillState.mode == .recording {
                wavePhase += 0.12
            }
        }
        .onReceive(dotTimer) { _ in
            if pillState.mode == .processing {
                dotPhase += 0.08
            }
        }
    }

    // MARK: - Background pill with gradient border glow

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.black.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(borderGradient, lineWidth: 1.5)
            )
            .shadow(color: glowColor.opacity(0.5), radius: 12, x: 0, y: 0)
    }

    private var borderGradient: LinearGradient {
        switch pillState.mode {
        case .recording:
            return LinearGradient(
                colors: [Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .processing:
            return LinearGradient(
                colors: [Color(hex: 0x8B5CF6), Color(hex: 0x06B6D4)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .idle:
            return LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing)
        }
    }

    private var glowColor: Color {
        switch pillState.mode {
        case .recording: return Color(hex: 0x6366F1)
        case .processing: return Color(hex: 0x8B5CF6)
        case .idle: return .clear
        }
    }

    // MARK: - Content (waveform bars or loading dots)

    @ViewBuilder
    private var pillContent: some View {
        switch pillState.mode {
        case .recording:
            waveformBars
        case .processing:
            loadingDots
        case .idle:
            EmptyView()
        }
    }

    // 5 vertical waveform bars with indigo→violet gradient
    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                let height = barHeight(index: i)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x6366F1), Color(hex: 0x8B5CF6)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3, height: height)
            }
        }
        .frame(height: 18)
    }

    private func barHeight(index: Int) -> CGFloat {
        let base: CGFloat = 4
        let maxExtra: CGFloat = 14
        let wave1 = sin(wavePhase + Double(index) * 0.8) * 0.5 + 0.5
        let wave2 = sin(wavePhase * 1.4 + Double(index) * 0.5) * 0.3 + 0.5
        return base + CGFloat((wave1 + wave2) / 2) * maxExtra
    }

    // 3 animated dots with violet→cyan gradient
    private var loadingDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x8B5CF6), Color(hex: 0x06B6D4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 5, height: 5)
                    .opacity(dotOpacity(index: i))
                    .scaleEffect(dotScale(index: i))
            }
        }
    }

    private func dotOpacity(index: Int) -> Double {
        let phase = sin(dotPhase + Double(index) * 1.2) * 0.5 + 0.5
        return 0.4 + phase * 0.6
    }

    private func dotScale(index: Int) -> CGFloat {
        let phase = sin(dotPhase + Double(index) * 1.2) * 0.5 + 0.5
        return 0.7 + CGFloat(phase) * 0.5
    }
}

// MARK: - Hex color helper

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
