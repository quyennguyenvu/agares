/// A change to the text before the cursor: press Backspace `backspaces` times, then type `text`.
public struct Edit: Equatable {
    public let backspaces: Int
    public let text: String
}

extension Edit {
    /// Deletes back to the first character that differs, then types the rest.
    init(from old: String, to new: String) {
        let common = zip(old, new).prefix { $0.0 == $0.1 }.count
        self.init(backspaces: old.count - common, text: String(new.dropFirst(common)))
    }
}
