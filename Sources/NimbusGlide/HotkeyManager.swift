import Cocoa
import Carbon

enum HotkeyChoice: String, CaseIterable, Identifiable, Codable {
    case fn     = "fn Globe 🌐"
    case custom = "Custom Key…"

    var id: String { rawValue }
}

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isKeyDown = false
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void

    // Modifier key codes that fire via flagsChanged
    private static let modifierKeyCodes: Set<UInt16> = [
        56, 60,  // Left/Right Shift
        59, 62,  // Left/Right Control
        58, 61,  // Left/Right Option
        55, 54,  // Left/Right Command
        57,      // Caps Lock
        63,      // fn/Globe
    ]

    var hotkey: HotkeyChoice {
        didSet {
            isKeyDown = false
            setupMonitors()
            print("[NimbusGlide] Hotkey changed to: \(hotkey.rawValue)")
        }
    }
    var customKeyCode: UInt16 = 0 {
        didSet {
            if hotkey == .custom && customKeyCode != oldValue {
                isKeyDown = false
                setupMonitors()
                print("[NimbusGlide] Custom key code changed to: \(customKeyCode)")
            }
        }
    }

    init(hotkey: HotkeyChoice = .fn, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.hotkey = hotkey
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        setupMonitors()
    }

    deinit { removeMonitors() }

    private func removeMonitors() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        if let m = globalKeyMonitor  { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor   { NSEvent.removeMonitor(m) }
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = localFlagsMonitor  { NSEvent.removeMonitor(m) }
        globalKeyMonitor = nil; localKeyMonitor = nil
        globalFlagsMonitor = nil; localFlagsMonitor = nil
    }

    private func setupMonitors() {
        removeMonitors()

        if hotkey == .fn {
            setupFnEventTap()
        } else {
            // Custom key
            let isModifierKey = Self.modifierKeyCodes.contains(customKeyCode)

            if customKeyCode == 63 {
                // fn/Globe selected as custom — use event tap
                setupFnEventTap()
            } else if isModifierKey {
                // Custom modifier key (Shift, Ctrl, etc.)
                globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                    self?.handleCustomModifier(event)
                }
                localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                    self?.handleCustomModifier(event)
                    return event
                }
            } else {
                // Regular key
                globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                    self?.handleKeyEvent(event)
                }
                localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                    self?.handleKeyEvent(event)
                    return event
                }
            }
        }

        print("[NimbusGlide] Hotkey listener active: \(hotkey.rawValue) (customCode: \(customKeyCode))")
    }

    // MARK: - fn/Globe via CGEvent tap (low-level, catches it before macOS intercepts)

    private func setupFnEventTap() {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags

            // fn key: keyCode 63
            if keyCode == 63 {
                let fnDown = flags.contains(.maskSecondaryFn)
                if fnDown && !manager.isKeyDown {
                    manager.isKeyDown = true
                    DispatchQueue.main.async { manager.onKeyDown() }
                    return nil // swallow the event so emoji picker doesn't open
                } else if !fnDown && manager.isKeyDown {
                    manager.isKeyDown = false
                    DispatchQueue.main.async { manager.onKeyUp() }
                    return nil
                }
            }

            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            print("[NimbusGlide] WARNING: Could not create event tap for fn key. Accessibility permission may be needed.")
            // Fall back to NSEvent monitor
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFnFallback(event)
            }
            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFnFallback(event)
                return event
            }
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // Fallback for fn key if event tap fails
    private func handleFnFallback(_ event: NSEvent) {
        guard event.keyCode == 63 else { return }
        let fnDown = event.modifierFlags.contains(.function)
        if fnDown && !isKeyDown {
            isKeyDown = true
            DispatchQueue.main.async { [weak self] in self?.onKeyDown() }
        } else if !fnDown && isKeyDown {
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in self?.onKeyUp() }
        }
    }

    // MARK: - Regular key (keyDown/keyUp)

    private func handleKeyEvent(_ event: NSEvent) {
        guard event.keyCode == customKeyCode else { return }
        if event.type == .keyDown && !isKeyDown {
            isKeyDown = true
            DispatchQueue.main.async { [weak self] in self?.onKeyDown() }
        } else if event.type == .keyUp && isKeyDown {
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in self?.onKeyUp() }
        }
    }

    // MARK: - Custom modifier key (flagsChanged)

    private func handleCustomModifier(_ event: NSEvent) {
        guard event.keyCode == customKeyCode else { return }
        let modFlag = Self.modifierFlagForKeyCode(customKeyCode)
        let isPressed = event.modifierFlags.contains(modFlag)

        if isPressed && !isKeyDown {
            isKeyDown = true
            DispatchQueue.main.async { [weak self] in self?.onKeyDown() }
        } else if !isPressed && isKeyDown {
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in self?.onKeyUp() }
        }
    }

    private static func modifierFlagForKeyCode(_ code: UInt16) -> NSEvent.ModifierFlags {
        switch code {
        case 56, 60: return .shift
        case 59, 62: return .control
        case 58, 61: return .option
        case 55, 54: return .command
        case 57:     return .capsLock
        case 63:     return .function
        default:     return []
        }
    }
}
