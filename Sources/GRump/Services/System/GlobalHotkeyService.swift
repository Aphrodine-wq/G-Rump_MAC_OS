import Foundation
import Combine
#if os(macOS)
import AppKit
import Carbon.HIToolbox
#endif

// MARK: - Global Hotkey Service

/// Detects double-tap ⌃Space (or a user-configured hotkey) to show the QuickChatPopover.
/// Uses CGEvent tap on macOS (requires Accessibility permission).
@MainActor
final class GlobalHotkeyService: ObservableObject {

    static let shared = GlobalHotkeyService()

    // MARK: - Published State

    @Published var isEnabled: Bool = UserDefaults.standard.object(forKey: "GlobalHotkeyEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "GlobalHotkeyEnabled")
            if isEnabled { start() } else { stop() }
        }
    }
    @Published var hasAccessibilityPermission = false
    @Published var isListening = false

    /// Fired when the hotkey is activated.
    var onActivate: (() -> Void)?

    // MARK: - Private

    #if os(macOS)
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    #endif
    private var lastControlSpaceTime: Date?
    private let doubleTapWindow: TimeInterval = 0.4

    private init() {
        #if os(macOS)
        checkAccessibilityPermission()
        #endif
    }

    // MARK: - Lifecycle

    func start() {
        guard isEnabled else { return }
        #if os(macOS)
        guard hasAccessibilityPermission else {
            GRumpLogger.general.warning("GlobalHotkeyService: no Accessibility permission")
            return
        }
        installEventTap()
        #endif
    }

    func stop() {
        #if os(macOS)
        removeEventTap()
        #endif
    }

    // MARK: - Accessibility Permission

    #if os(macOS)
    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        hasAccessibilityPermission = trusted
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Re-check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAccessibilityPermission()
        }
    }
    #endif

    // MARK: - Event Tap

    #if os(macOS)
    private func installEventTap() {
        guard eventTap == nil else { return }

        // We need an unmanaged pointer to self for the C callback
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let service = Unmanaged<GlobalHotkeyService>.fromOpaque(refcon).takeUnretainedValue()

                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags

                    // Check for Control + Space (keyCode 49 = space bar)
                    if keyCode == 49 && flags.contains(.maskControl) && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate) {
                        DispatchQueue.main.async {
                            service.handleControlSpace()
                        }
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        )

        guard let eventTap else {
            GRumpLogger.general.error("GlobalHotkeyService: failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isListening = true
        GRumpLogger.general.info("GlobalHotkeyService: event tap installed")
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        isListening = false
    }
    #endif

    // MARK: - Double-Tap Detection

    private func handleControlSpace() {
        let now = Date()
        if let lastTime = lastControlSpaceTime,
           now.timeIntervalSince(lastTime) < doubleTapWindow {
            // Double-tap detected
            lastControlSpaceTime = nil
            GRumpLogger.general.info("GlobalHotkeyService: double-tap ⌃Space activated")
            onActivate?()
        } else {
            lastControlSpaceTime = now
        }
    }
}
