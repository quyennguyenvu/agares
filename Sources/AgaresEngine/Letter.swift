enum Mark {
    case none, circumflex, breve, horn, stroke
}

/// Raw value is the column in `toneRows`.
enum Tone: Int {
    case acute = 1, grave, hook, tilde, dot
}

extension Character {
    var isVowel: Bool { "aeiouy".contains(self) }
}

struct Letter: Equatable {
    /// Lowercase ASCII.
    var base: Character
    var mark = Mark.none
    var upper = false
    /// A ư typed as a bare w. Undo turns it back into the w it was.
    var fromW = false

    var isVowel: Bool { base.isVowel }

    /// The lowercase letter with its mark and no tone.
    var marked: Character {
        switch (base, mark) {
        case ("a", .circumflex): return "â"
        case ("a", .breve): return "ă"
        case ("e", .circumflex): return "ê"
        case ("o", .circumflex): return "ô"
        case ("o", .horn): return "ơ"
        case ("u", .horn): return "ư"
        case ("d", .stroke): return "đ"
        default: return base
        }
    }

    /// The letter as shown: mark and case applied, plus the tone if this letter carries it.
    func rendered(tone: Tone?) -> String {
        var shown = marked
        if let tone, let row = toneRows.first(where: { $0[0] == shown }) {
            shown = row[tone.rawValue]
        }
        return upper ? shown.uppercased() : String(shown)
    }
}

/// Each row: no tone, sắc, huyền, hỏi, ngã, nặng.
private let toneRows: [[Character]] = [
    "aáàảãạ", "ăắằẳẵặ", "âấầẩẫậ", "eéèẻẽẹ", "êếềểễệ", "iíìỉĩị",
    "oóòỏõọ", "ôốồổỗộ", "ơớờởỡợ", "uúùủũụ", "ưứừửữự", "yýỳỷỹỵ",
].map(Array.init)
