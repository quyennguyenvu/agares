/// What the key hook does with a key press that is neither the hotkey nor part of a recording.
public enum KeyAction: Equatable {
    /// Let the key reach the app unchanged.
    case pass
    /// Let the key reach the app unchanged. It may have opened or closed Spotlight.
    case passMaybeSpotlight
    /// Swallow the key and make this edit instead.
    case edit(Edit)
}

extension Engine {
    /// Feeds one key press. `letter` is the typed character if it is a single ASCII letter.
    public mutating func press(_ keyCode: UInt16, letter: Character?, held: Modifiers, vietnameseOn: Bool) -> KeyAction {
        // A shortcut such as ⌘S must reach the app as it is, and the word ends with it.
        if !vietnameseOn || !held.isDisjoint(with: [.control, .option, .command]) {
            reset()
            return .passMaybeSpotlight
        }
        if keyCode == 51 {
            return backspace().map(KeyAction.edit) ?? .pass
        }
        if let letter {
            return type(letter).map(KeyAction.edit) ?? .pass
        }
        reset()
        // Space is typed constantly and cannot open or close Spotlight. Any other key might
        // (Return, Escape, a function key).
        return keyCode == 49 ? .pass : .passMaybeSpotlight
    }
}
