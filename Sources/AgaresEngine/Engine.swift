/// Telex state for the word under the cursor.
public struct Engine {
    private var letters: [Letter] = []
    private var tone: Tone?
    /// Mark keys undone in this word. They stay plain letters until the word ends.
    private var spent: Set<Character> = []
    private var shown = ""
    private let allowsZFWJ: Bool

    /// `allowsZFWJ` accepts z, f, w and j as initial consonants, so words such as zô and jì take marks.
    public init(allowsZFWJ: Bool = false) {
        self.allowsZFWJ = allowsZFWJ
    }

    /// Feeds one ASCII letter. Returns nil when the key should reach the app unchanged.
    public mutating func type(_ key: Character) -> Edit? {
        guard key.isASCII, key.isLetter else {
            reset()
            return nil
        }
        apply(key)
        completeHornPair()
        let old = shown
        shown = render()
        return shown == old + String(key) ? nil : Edit(from: old, to: shown)
    }

    /// Returns nil when Backspace should reach the app unchanged.
    public mutating func backspace() -> Edit? {
        guard !letters.isEmpty else { return nil }
        // Deleting the vowel that carries the tone deletes the tone with it.
        if parse(letters).toneIndex == letters.count - 1 { tone = nil }
        // Deleting the plain letter that an accidental repeat left behind makes that key a mark key again.
        spent.remove(letters.removeLast().base)
        guard !letters.isEmpty else {
            reset()
            return nil
        }
        let old = shown
        shown = render()
        return shown == String(old.dropLast()) ? nil : Edit(from: old, to: shown)
    }

    /// The word has ended.
    public mutating func reset() {
        self = Engine(allowsZFWJ: allowsZFWJ)
    }

    private func parse(_ letters: [Letter]) -> Shape {
        Shape(letters, allowsZFWJ: allowsZFWJ)
    }

    private func render() -> String {
        let toneIndex = tone == nil ? nil : parse(letters).toneIndex
        return letters.indices.map { letters[$0].rendered(tone: $0 == toneIndex ? tone : nil) }.joined()
    }

    private mutating func apply(_ key: Character) {
        let lower = Character(key.lowercased())
        if !spent.contains(lower) {
            switch lower {
            case "a", "e", "o":
                if circumflex(lower, typed: key) { return }
            case "w":
                if horn(typed: key) { return }
            case "d":
                if stroke(typed: key) { return }
            case "z":
                if tone != nil {
                    tone = nil
                    return
                }
            default:
                if let new = toneKeys[lower], setTone(new, typed: key) { return }
            }
        }
        append(key)
    }

    private mutating func append(_ key: Character) {
        letters.append(Letter(base: Character(key.lowercased()), upper: key.isUppercase))
    }

    /// The key becomes a plain letter, now and for the rest of the word.
    private mutating func undo(_ key: Character) {
        spent.insert(Character(key.lowercased()))
        append(key)
    }

    /// Spec 4.5: a valid shape, and a stop final (c, ch, k, p, t) only with sắc, nặng or no tone.
    private func accepts(_ tone: Tone?, _ shape: Shape) -> Bool {
        shape.isValid && (!shape.endsInStop || tone == nil || tone == .acute || tone == .dot)
    }

    // MARK: aa ee oo

    private mutating func circumflex(_ lower: Character, typed key: Character) -> Bool {
        let shape = parse(letters)
        guard accepts(tone, shape) else { return false }
        let sameVowel = shape.vowels.filter { letters[$0].base == lower }

        // A second press takes the circumflex off again.
        if let marked = sameVowel.first(where: { letters[$0].mark == .circumflex }) {
            letters[marked].mark = .none
            undo(key)
            return true
        }
        // The key marks an earlier vowel wherever that makes a vowel group Vietnamese has, however many
        // letters came in between: lay + a is lây. It is a new vowel otherwise, as in ngoeo, where ôe is no group.
        for target in sameVowel {
            var marked = letters
            marked[target].mark = .circumflex
            if circumflexGroups.contains(String(marked[shape.vowels].map(\.marked))) {
                letters = marked
                return true
            }
        }
        return false
    }

    // MARK: w

    private mutating func horn(typed key: Character) -> Bool {
        let shape = parse(letters)
        let group = shape.vowels
        if group.isEmpty {
            // With z, f, w and j allowed as consonants, a w that starts the word is one of them.
            if allowsZFWJ, letters.isEmpty { return false }
            // Otherwise a bare w is a new ư, if that leaves a valid syllable.
            let bare = Letter(base: "u", mark: .horn, upper: key.isUppercase, fromW: true)
            guard parse(letters + [bare]).isValid else { return false }
            letters.append(bare)
            return true
        }
        guard accepts(tone, shape) else { return false }

        let targets = hornTargets(in: group)
        if !targets.isEmpty {
            for i in targets { letters[i].mark = letters[i].base == "a" ? .breve : .horn }
        } else if group.contains(where: { letters[$0].mark == .horn || letters[$0].mark == .breve }) {
            undoHorn(typed: key)
        } else {
            return false
        }
        return true
    }

    /// The vowels a w would newly mark: the first choice, in the priority order of spec 4.1, that
    /// makes a vowel group Vietnamese has. Empty when there is none.
    private func hornTargets(in group: Range<Int>) -> [Int] {
        func plain(_ i: Int) -> Bool { letters[i].mark == .none }
        func makesGroup(_ targets: [Int]) -> Bool {
            var marked = letters
            for i in targets { marked[i].mark = marked[i].base == "a" ? .breve : .horn }
            return !targets.isEmpty && hornGroups.contains(String(marked[group].map(\.marked)))
        }

        var choices: [[Int]] = []
        for i in group.dropLast() where letters[i].base == "u" {
            let next = i + 1
            if letters[next].base == "o" {
                // uo becomes uơ at the end of the word, ươ once a letter follows. Nothing else is tried.
                var pair = plain(next) ? [next] : []
                if plain(i), next < letters.count - 1 { pair.insert(i, at: 0) }
                return makesGroup(pair) ? pair : []
            }
            if letters[next].base == "a", plain(i) { choices.append([i]) }
        }
        for base in ["a", "o", "u"] as [Character] {
            choices += group.filter { letters[$0].base == base && plain($0) }.map { [$0] }
        }
        return choices.first(where: makesGroup) ?? []
    }

    private mutating func undoHorn(typed key: Character) {
        spent.insert("w")
        let endsWithBareW = letters.last?.fromW == true
        for i in letters.indices where letters[i].mark == .horn || letters[i].mark == .breve {
            if letters[i].fromW {
                letters[i] = Letter(base: "w", upper: letters[i].upper)
            } else {
                letters[i].mark = .none
            }
        }
        // "ww" is one w: the ư goes back to being the first w, and the second is dropped.
        if !endsWithBareW { append(key) }
    }

    /// uơ and ưo become ươ once a letter follows: mươn, lương, người.
    private mutating func completeHornPair() {
        let group = parse(letters).vowels
        for i in group.dropLast() where letters[i].base == "u" && letters[i + 1].base == "o" && i + 1 < letters.count - 1 {
            let marks = (letters[i].mark, letters[i + 1].mark)
            if marks == (.horn, .none) || marks == (.none, .horn) {
                letters[i].mark = .horn
                letters[i + 1].mark = .horn
            }
        }
    }

    // MARK: dd

    private mutating func stroke(typed key: Character) -> Bool {
        guard let first = letters.first, first.base == "d" else { return false }
        if first.mark == .stroke {
            letters[0].mark = .none
            undo(key)
        } else if letters.count == 1 || accepts(tone, parse(letters)) {
            letters[0].mark = .stroke
        } else {
            return false
        }
        return true
    }

    // MARK: s f r x j

    private mutating func setTone(_ new: Tone, typed key: Character) -> Bool {
        let shape = parse(letters)
        guard !shape.vowels.isEmpty else { return false }
        if tone == new {
            tone = nil
            undo(key)
            return true
        }
        guard accepts(new, shape) else { return false }
        tone = new
        return true
    }
}

private let toneKeys: [Character: Tone] = ["s": .acute, "f": .grave, "r": .hook, "x": .tilde, "j": .dot]
