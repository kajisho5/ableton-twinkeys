#if os(macOS)
import AppKit
import CoreGraphics
import TwinKeysCore

/// Watches the keyboard system-wide with a listen-only event tap. It only reads
/// key events; it never blocks or changes them. Needs the Input Monitoring permission.
final class KeyMonitor {
    var onKey: ((KeyInput) -> Void)?
    fileprivate var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt the first time; afterwards the person has to use System Settings.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    var isRunning: Bool { tap != nil }

    /// Returns false if the tap could not be created (usually: no permission).
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: keyTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
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
        tap = nil; runLoop = nil; thread = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown, .keyUp:
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            var mods: Modifiers = []
            let f = event.flags
            if f.contains(.maskShift) { mods.insert(.shift) }
            if f.contains(.maskControl) { mods.insert(.control) }
            if f.contains(.maskAlternate) { mods.insert(.option) }
            if f.contains(.maskCommand) { mods.insert(.command) }
            onKey?(KeyInput(keycode: code, isDown: type == .keyDown, isRepeat: isRepeat, modifiers: mods))
        default:
            break
        }
    }
}

private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
#endif
