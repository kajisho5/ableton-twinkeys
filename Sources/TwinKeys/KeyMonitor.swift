#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics
import TwinKeysCore

/// Watches the keyboard system-wide with an event tap.
/// - Listen-only (default): only reads key events. Needs Input Monitoring.
/// - Blocking: may also keep cue keys from other apps (the handler returns true).
///   Needs the Accessibility permission; without it the tap cannot be created and
///   `start(blocking: true)` falls back to listen-only.
final class KeyMonitor {
    /// Returns true to keep the key from other apps (only honoured by a blocking tap).
    var onKey: ((KeyInput) -> Bool)?
    /// Called on the tap thread when macOS paused the tap: key-ups may have been missed.
    var onEventsMissed: (() -> Void)?
    private let tapLock = NSLock()
    private var _tap: CFMachPort?
    /// Read on the tap thread, written on the main thread: guarded by a lock.
    fileprivate var tap: CFMachPort? {
        get { tapLock.lock(); defer { tapLock.unlock() }; return _tap }
        set { tapLock.lock(); _tap = newValue; tapLock.unlock() }
    }
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt the first time; afterwards the person has to use System Settings.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    var isRunning: Bool { tap != nil }
    /// The running tap can keep keys from other apps.
    private(set) var isBlocking = false
    /// While true, key events are passed on untouched and not handled (recording a new cue key).
    var paused: Bool {
        get { tapLock.lock(); defer { tapLock.unlock() }; return _paused }
        set { tapLock.lock(); _paused = newValue; tapLock.unlock() }
    }
    private var _paused = false

    /// Accessibility permission (needed to keep keys from other apps).
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt for Accessibility (only the first time) and adds TwinKeys to the list.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Returns false if no tap could be created (usually: no permission).
    /// `blocking`: try a tap that can keep cue keys from other apps; falls back to listen-only.
    func start(blocking: Bool = false) -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        var made: CFMachPort?
        if blocking && Self.hasAccessibility {
            made = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                     eventsOfInterest: mask, callback: keyTapCallback, userInfo: me)
        }
        isBlocking = made != nil
        if made == nil {
            made = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                     eventsOfInterest: mask, callback: keyTapCallback, userInfo: me)
        }
        guard let tap = made else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [weak self] in
            let rl = CFRunLoopGetCurrent()
            self?.runLoop = rl
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "TwinKeys key monitor"
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
        ready.wait()
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil; runLoop = nil; thread = nil; isBlocking = false
    }

    /// Returns true if the event should be kept from other apps.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onEventsMissed?()
            return false
        case .keyDown, .keyUp:
            if paused { return false }
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            var mods: Modifiers = []
            let f = event.flags
            if f.contains(.maskShift) { mods.insert(.shift) }
            if f.contains(.maskControl) { mods.insert(.control) }
            if f.contains(.maskAlternate) { mods.insert(.option) }
            if f.contains(.maskCommand) { mods.insert(.command) }
            return onKey?(KeyInput(keycode: code, isDown: type == .keyDown, isRepeat: isRepeat, modifiers: mods)) ?? false
        default:
            return false
        }
    }
}

private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon, Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event) {
        return nil      // kept from other apps (a blocking tap only; a listen-only tap ignores this)
    }
    return Unmanaged.passUnretained(event)
}
#endif
