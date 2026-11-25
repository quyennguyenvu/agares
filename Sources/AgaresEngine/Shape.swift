/// How a word splits into initial consonant, vowel group and final consonant.
struct Shape {
    /// Indices of the vowel group. Leaves out the u of "qu" and the i of "gi" before a vowel.
    let vowels: Range<Int>
    /// Judged on base letters only, ignoring marks.
    let isValid: Bool
    /// Final c, ch, p or t: such a syllable takes only sắc or nặng.
    let endsInStop: Bool
    /// The vowel that carries the tone, nil when the word has no vowel.
    let toneIndex: Int?

    /// `allowsZFWJ` also accepts z, f, w and j as initial consonants.
    init(_ letters: [Letter], allowsZFWJ: Bool = false) {
        let bases = letters.map(\.base)
        var i = bases.firstIndex(where: \.isVowel) ?? bases.count
        if bases.starts(with: "qu") || (bases.starts(with: "gi") && bases.count > 2 && bases[2].isVowel) {
            i = 2
        }
        let start = i
        while i < bases.count, bases[i].isVowel { i += 1 }
        let end = i
        while i < bases.count, !bases[i].isVowel { i += 1 }

        let initial = String(bases[..<start])
        let group = String(bases[start..<end])
        let final = String(bases[end..<i])
        vowels = start..<end
        isValid = i == bases.count
            && (initial.isEmpty || initials.contains(initial) || (allowsZFWJ && ["z", "f", "w", "j"].contains(initial)))
            && groups.contains(group)
            && (final.isEmpty || finals.contains(final))
        endsInStop = ["c", "ch", "p", "t"].contains(final)

        if let marked = vowels.last(where: { letters[$0].mark != .none }) {
            toneIndex = marked
        } else {
            switch vowels.count {
            case 0: toneIndex = nil
            case 1: toneIndex = start
            case 2: toneIndex = end < letters.count ? start + 1 : start
            default: toneIndex = start + 1
            }
        }
    }
}

private let initials: Set<String> = [
    "b", "c", "ch", "d", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "ng", "ngh", "nh",
    "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x",
]

private let groups: Set<String> = [
    "a", "e", "i", "o", "u", "y",
    "ai", "ao", "au", "ay", "eo", "eu", "ia", "ie", "iu", "oa", "oe", "oi", "oo",
    "ua", "ue", "ui", "uo", "uu", "uy", "ye",
    "ieu", "oai", "oao", "oay", "oeo", "uay", "uoi", "uou", "uya", "uye", "uyu", "yeu",
]

private let finals: Set<String> = ["c", "ch", "m", "n", "ng", "nh", "p", "t"]

/// Every vowel group Vietnamese writes with a circumflex. A doubling vowel adds one only if it makes one of these.
let circumflexGroups: Set<String> = [
    "â", "ê", "ô",
    "âu", "ây", "êu", "iê", "ôi", "uâ", "uê", "uô", "yê",
    "iêu", "yêu", "uây", "uôi", "uyê",
]

/// Every vowel group Vietnamese writes with a horn or a breve. A w adds one only if it makes one of these.
let hornGroups: Set<String> = [
    "ă", "ơ", "ư",
    "oă", "ơi", "uơ", "ưa", "ưi", "ưu", "ươ",
    "ươi", "ươu",
]
