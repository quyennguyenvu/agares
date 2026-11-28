import AgaresEngine
import AppKit

/// The system-wide key hook. Everything it does not handle passes through untouched.
final class KeyTap {
    var vietnameseOn = true {
        didSet { engine.reset() }
    }

    /// Whether z, f, w and j count as initial consonants. Changing it starts a fresh word.
    var allowsZFWJ = false {
        didSet { engine = Engine(allowsZFWJ: allowsZFWJ) }
    }

    /// Leaves alone keys that another app typed, such as a password manager's auto-type: they are
    /// neither converted nor taken for the hotkey.
    var ignoresOtherApps = true

    var hotkey: Hotkey {
        get { matcher.hotkey }
        set { matcher.hotkey = newValue }
    }

    /// Called when the hotkey is pressed.
    var onHotkey: () -> Void = {}

    private var engine = Engine()
    private var matcher = HotkeyMatcher(hotkey: Hotkey.presets[0])
    private var recorder: HotkeyRecorder?
    private var onRecorded: (Hotkey?) -> Void = { _ in }
    private let typist = Typist()
    private var tap: CFMachPort?
    /// The other apps whose keys have been reported to Diagnostics, so each lookup is made once.
    private var notedSenders: Set<Int64> = []

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.engine.reset()
            self?.typist.forgetSpotlight()
        }
    }

    /// False when macOS refuses the tap, which means Accessibility is not granted.
    func start() -> Bool {
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue().handle(proxy, type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    func stop() {
        guard let tap else { return }
        CFMachPortInvalidate(tap)
        self.tap = nil
        cancelRecording()
        engine.reset()
    }

    /// False while macOS has the hook switched off, and while it is not running.
    var isEnabled: Bool {
        tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    /// Switches the hook back on if macOS switched it off without sending the event that says so.
    func revive() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        engine.reset()
        Diagnostics.note("[tap] found disabled, re-enabled")
    }

    /// Hands the next shortcut the user presses to `done`, or nil if they cancel.
    func record(_ done: @escaping (Hotkey?) -> Void) {
        recorder = HotkeyRecorder()
        onRecorded = done
    }

    func cancelRecording() {
        finishRecording(.cancelled)
    }

    private func finishRecording(_ outcome: HotkeyRecorder.Outcome) {
        guard recorder != nil, outcome != .pending else { return }
        recorder = nil
        if case .captured(let hotkey) = outcome {
            onRecorded(hotkey)
        } else {
            onRecorded(nil)
        }
    }

    private func handle(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        // What this run did that could have waited, for the line written if it was slow.
        var did = "pass"
        let began = DispatchTime.now().uptimeNanoseconds
        defer {
            let ms = (DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
            if ms > 50 { Diagnostics.note("[tap] slow callback: \(ms) ms (\(did))") }
        }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Diagnostics.note(type == .tapDisabledByTimeout ? "[tap] disabled by timeout" : "[tap] disabled by user input")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Keys typed while the tap was off never reached the engine, so its word is stale.
            engine.reset()
            return pass
        case .flagsChanged:
            if isFromAnotherApp(event) { return pass }
            let held = Self.modifiers(event.flags)
            if recorder != nil {
                did = "record"
                finishRecording(recorder!.modifiersChanged(held))
            } else if matcher.modifiersChanged(held) {
                did = "hotkey"
                onHotkey()
            }
            return pass
        case .keyDown:
            break
        default:
            // A mouse button: the cursor may have moved, and a click ends a recording.
            cancelRecording()
            matcher.otherInput()
            engine.reset()
            typist.forgetSpotlight()
            return pass
        }

        if event.getIntegerValueField(.eventSourceUserData) == Typist.tag { return pass }
        if isFromAnotherApp(event) {
            // Their text has moved the cursor on, so the word being tracked is over.
            engine.reset()
            typist.forgetSpotlight()
            return pass
        }
        let held = Self.modifiers(event.flags)
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

        if recorder != nil {
            did = "record"
            let outcome = recorder!.keyPressed(keyCode, held: held)
            finishRecording(outcome)
            return outcome == .pending ? pass : nil
        }
        if matcher.keyPressed(keyCode, held: held) {
            did = "hotkey"
            // Holding the hotkey repeats the key; only the first press toggles.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { onHotkey() }
            return nil
        }
        switch engine.press(keyCode, letter: Self.letter(of: event), held: held, vietnameseOn: vietnameseOn) {
        case .pass:
            return pass
        case .passMaybeSpotlight:
            typist.forgetSpotlight()
            return pass
        case .edit(let edit):
            did = "edit"
            typist.send(edit, through: proxy)
            return nil
        }
    }

    /// A key pressed on the keyboard has no sending process; one typed by an app carries that app's id.
    private func isFromAnotherApp(_ event: CGEvent) -> Bool {
        let sender = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard ignoresOtherApps, sender != 0 else { return false }
        if notedSenders.insert(sender).inserted { Diagnostics.notePassing(pid_t(truncatingIfNeeded: sender)) }
        return true
    }

    private static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var held: Modifiers = []
        if flags.contains(.maskControl) { held.insert(.control) }
        if flags.contains(.maskAlternate) { held.insert(.option) }
        if flags.contains(.maskShift) { held.insert(.shift) }
        if flags.contains(.maskCommand) { held.insert(.command) }
        return held
    }

    /// The typed character if it is a single ASCII letter, with Shift and Caps Lock already applied.
    private static func letter(of event: CGEvent) -> Character? {
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &units)
        guard length == 1, let scalar = Unicode.Scalar(units[0]) else { return nil }
        let character = Character(scalar)
        return character.isASCII && character.isLetter ? character : nil
    }
}
