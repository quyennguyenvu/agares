/// The modifier keys a shortcut can use.
public struct Modifiers: OptionSet, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = Modifiers(rawValue: 1)
    public static let option = Modifiers(rawValue: 2)
    public static let shift = Modifiers(rawValue: 4)
    public static let command = Modifiers(rawValue: 8)
}

/// The shortcut that switches Vietnamese on and off: modifiers alone, or modifiers with one key.
public struct Hotkey: Equatable {
    public var modifiers: Modifiers
    /// Virtual key code, nil for a modifiers-only shortcut.
    public var keyCode: UInt16?

    public init(modifiers: Modifiers, keyCode: UInt16? = nil) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    /// The first is the default.
    public static let presets = [
        Hotkey(modifiers: [.control, .shift], keyCode: 49),
        Hotkey(modifiers: [.control, .option], keyCode: 6),
        Hotkey(modifiers: [.control, .option]),
    ]

    /// Modifiers alone need two of them. With a key, Control, Option or Command must be held,
    /// and Command+Tab stays with the app switcher.
    public var isValid: Bool {
        guard let keyCode else { return modifiers.rawValue.nonzeroBitCount >= 2 }
        if keyCode == 48, modifiers.contains(.command) { return false }
        return !modifiers.isDisjoint(with: [.control, .option, .command])
    }

    /// Keycap labels in the order macOS shows them: ⌃ ⌥ ⇧ ⌘, then the key.
    public var keycaps: [String] {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        var caps = symbols.filter { modifiers.contains($0.0) }.map(\.1)
        if let keyCode { caps.append(keyLabels[keyCode] ?? "Key \(keyCode)") }
        return caps
    }

    /// The shortcut in words, for anyone who does not read ⌃ as Control: "Control + Option + Z".
    public var name: String {
        let words: [(Modifiers, String)] = [(.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command")]
        var parts = words.filter { modifiers.contains($0.0) }.map(\.1)
        if let keyCode { parts.append(keyLabels[keyCode] ?? "Key \(keyCode)") }
        return parts.joined(separator: " + ")
    }
}

/// Decides when the shortcut has been pressed.
public struct HotkeyMatcher {
    public var hotkey: Hotkey
    private var held: Modifiers = []
    private var armed = false
    /// This hold has seen a modifier, key or click outside the shortcut. Cleared when every modifier is up.
    private var spoiled = false

    public init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    /// Call on every modifier change. True when a modifiers-only shortcut was pressed and released cleanly.
    public mutating func modifiersChanged(_ now: Modifiers) -> Bool {
        held = now
        defer { if now.isEmpty { spoiled = false } }
        guard hotkey.keyCode == nil, !spoiled else {
            armed = false
            return false
        }
        if now == hotkey.modifiers {
            armed = true
            return false
        }
        // A larger chord such as ⌃⇧⌘4 passes through ⌃⇧ on the way up and again on the way down.
        let inside = now.isSubset(of: hotkey.modifiers)
        let fired = armed && inside
        spoiled = !inside
        armed = false
        return fired
    }

    /// Call on every key press. True when it is the shortcut; the caller swallows the key.
    public mutating func keyPressed(_ keyCode: UInt16, held: Modifiers) -> Bool {
        self.held = held
        if hotkey.keyCode == keyCode, held == hotkey.modifiers { return true }
        otherInput()
        return false
    }

    /// A key or click that is not the shortcut cancels a modifiers-only press in progress.
    public mutating func otherInput() {
        armed = false
        if !held.isEmpty { spoiled = true }
    }
}

/// Captures the next shortcut the user presses.
public struct HotkeyRecorder {
    public enum Outcome: Equatable {
        case pending, cancelled, captured(Hotkey)
    }

    private var seen: Modifiers = []
    /// A key that cannot be a shortcut was pressed during this hold, so its modifiers are not one either.
    private var poisoned = false

    public init() {}

    /// Releasing every modifier captures a modifiers-only shortcut, if two or more were held.
    public mutating func modifiersChanged(_ now: Modifiers) -> Outcome {
        guard now.isEmpty else {
            seen.formUnion(now)
            return .pending
        }
        let hotkey = Hotkey(modifiers: seen)
        let usable = hotkey.isValid && !poisoned
        seen = []
        poisoned = false
        return usable ? .captured(hotkey) : .pending
    }

    /// A key captures a shortcut when it comes with valid modifiers. Escape alone cancels.
    public mutating func keyPressed(_ keyCode: UInt16, held: Modifiers) -> Outcome {
        if keyCode == 53, held.isEmpty { return .cancelled }
        let hotkey = Hotkey(modifiers: held, keyCode: keyCode)
        if hotkey.isValid { return .captured(hotkey) }
        poisoned = !held.isEmpty
        return .pending
    }
}

/// Labels for the keys of an ANSI keyboard, by virtual key code.
private let keyLabels: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
    13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
    24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
    35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
    45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
    118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
]
