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
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .flagsChanged:
            if isFromAnotherApp(event) { return pass }
            let held = Self.modifiers(event.flags)
            if recorder != nil {
                finishRecording(recorder!.modifiersChanged(held))
            } else if matcher.modifiersChanged(held) {
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
            let outcome = recorder!.keyPressed(keyCode, held: held)
            finishRecording(outcome)
            return outcome == .pending ? pass : nil
        }
        if matcher.keyPressed(keyCode, held: held) {
            // Holding the hotkey repeats the key; only the first press toggles.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { onHotkey() }
            return nil
        }
        if !vietnameseOn || !held.isDisjoint(with: [.control, .option, .command]) {
            engine.reset()
            typist.forgetSpotlight()
            return pass
        }

        let edit: Edit?
        if keyCode == 51 {
            edit = engine.backspace()
        } else if let letter = Self.letter(of: event) {
            edit = engine.type(letter)
        } else {
            engine.reset()
            // Space is typed constantly and cannot open or close Spotlight. Any other key might
            // (Return, Escape, a function key), so the cached answer is dropped.
            if keyCode != 49 { typist.forgetSpotlight() }
            return pass
        }
        guard let edit else { return pass }
        typist.send(edit, through: proxy)
        return nil
    }

    /// A key pressed on the keyboard has no sending process; one typed by an app carries that app's id.
    private func isFromAnotherApp(_ event: CGEvent) -> Bool {
        ignoresOtherApps && event.getIntegerValueField(.eventSourceUnixProcessID) != 0
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
