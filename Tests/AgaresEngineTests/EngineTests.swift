import Testing
@testable import AgaresEngine

/// Plays keys into a fresh engine and returns what a text field would show. "⌫" is Backspace.
func typed(_ keys: String, allowsZFWJ: Bool = false) -> String {
    var engine = Engine(allowsZFWJ: allowsZFWJ)
    var field = ""
    for key in keys {
        let isBackspace = key == "⌫"
        if let edit = isBackspace ? engine.backspace() : engine.type(key) {
            field.removeLast(edit.backspaces)
            field += edit.text
        } else if isBackspace {
            field = String(field.dropLast())
        } else {
            field.append(key)
        }
    }
    return field
}

// Spec 4.7, in order.
@Test(arguments: [
    ("tieengs", "tiếng"), ("tieesng", "tiếng"), ("vieejt", "việt"), ("dduowngf", "đường"),
    ("nguowif", "người"), ("thuowr", "thuở"), ("luwong", "lương"), ("muaw", "mưa"),
    ("hoawcj", "hoặc"), ("ruowuj", "rượu"), ("tw", "tư"), ("hoaf", "hòa"),
    ("hoafn", "hoàn"), ("thuyr", "thủy"), ("khuyur", "khuỷu"), ("ngoaif", "ngoài"),
    ("quaf", "quà"), ("quys", "quý"), ("gif", "gì"), ("giuwax", "giữa"),
    ("asf", "à"), ("asz", "a"), ("aaa", "aa"), ("ass", "as"),
    ("ddd", "dd"), ("ww", "w"), ("DDaij", "Đại"), ("VIEEJT", "VIỆT"),
    ("css", "css"), ("class", "class"), ("catf", "catf"), ("data", "dât"),
    ("test", "tét"),
])
func specExamples(keys: String, expected: String) {
    #expect(typed(keys) == expected)
}

// Rules from spec 4.1 to 4.5 that the examples above do not reach.
@Test(arguments: [
    ("tiene", "tiên"), ("muown", "mươn"), ("thuow", "thuơ"), ("nhw", "như"),
    ("dod", "đo"), ("aww", "aw"), ("uww", "uw"), ("thuoww", "thuow"),
    ("ngoeo", "ngoeo"), ("xooong", "xoong"), ("oooo", "ooo"), ("nuocws", "nước"),
    ("nuwowcs", "nước"), ("gieets", "giết"), ("quoocs", "quốc"), ("muoons", "muốn"),
    ("toans", "toán"), ("xoays", "xoáy"), ("az", "az"), ("expect", "ẽpect"),
    ("add", "add"), ("huuw", "hưu"), ("huuww", "huuw"), ("teew", "têw"),
    ("muawa", "mưaa"), ("xuaan", "xuân"), ("viejte", "việt"), ("wow", "ươ"),
    // A doubling vowel reaches back over other vowels when that makes a real vowel group.
    ("layas", "lấy"), ("ddayas", "đấy"), ("dauaf", "dầu"), ("lieuej", "liệu"), ("tuoior", "tuổi"),
    // It stays a plain letter when it does not, and a second press still undoes it.
    ("khoee", "khoee"), ("hoaa", "hoaa"), ("layaa", "laya"),
    // w, too, marks a vowel only when that makes a real vowel group.
    ("aiw", "aiw"), ("aow", "aow"), ("auw", "auw"), ("eow", "eow"), ("uyw", "uyw"), ("oaiw", "oaiw"),
    ("muoonw", "muônw"),
])
func moreRules(keys: String, expected: String) {
    #expect(typed(keys) == expected)
}

@Test(arguments: [
    ("hoafn⌫", "hòa"), ("hoafn⌫n", "hoàn"), ("toans⌫", "tóa"),
    ("tieengs⌫⌫⌫⌫", "t"), ("vieejt⌫⌫", "vi"), ("dduowngf⌫⌫", "đườ"),
    ("as⌫a", "a"), ("⌫a", "a"),
    // Deleting the letter left by an accidental repeat makes the key work again.
    ("ddieenfe", "điène"), ("ddieenfe⌫", "đièn"), ("ddieenfe⌫e", "điền"),
    ("aaa⌫a", "â"), ("ass⌫s", "á"), ("aww⌫w", "ă"), ("ddd⌫d", "đ"), ("layaa⌫a", "lây"),
    ("ddieeen⌫⌫en", "điên"),
])
func backspace(keys: String, expected: String) {
    #expect(typed(keys) == expected)
}

// z, f, w and j as initial consonants: what the same keys give with the option off, then on.
@Test(arguments: [
    ("zaayj", "zaayj", "zậy"), ("zoo", "zoo", "zô"), ("fair", "fair", "fải"), ("jif", "jif", "jì"),
    ("was", "ứa", "wá"), ("wa", "ưa", "wa"), ("tw", "tư", "tư"), ("zasz", "zasz", "za"),
])
func zfwjAsConsonants(keys: String, off: String, on: String) {
    #expect(typed(keys) == off)
    #expect(typed(keys, allowsZFWJ: true) == on)
}

@Test func plainLettersPassThrough() {
    var engine = Engine()
    #expect(engine.type("t") == nil)
    #expect(engine.type("a") == nil)
}

@Test func aMarkRewritesFromTheFirstChangedCharacter() {
    var engine = Engine()
    for key in "tieeng" { _ = engine.type(key) }
    #expect(engine.type("s") == Edit(backspaces: 3, text: "ếng"))
}

@Test func bareWNeedsNoBackspace() {
    var engine = Engine()
    _ = engine.type("t")
    #expect(engine.type("w") == Edit(backspaces: 0, text: "ư"))
}

@Test func backspaceOnAnEmptyWordPassesThrough() {
    var engine = Engine()
    #expect(engine.backspace() == nil)
}

@Test func backspaceThatMovesTheToneIsAnEdit() {
    var engine = Engine()
    for key in "hoafn" { _ = engine.type(key) }
    #expect(engine.backspace() == Edit(backspaces: 3, text: "òa"))
}

@Test func resetStartsANewWord() {
    var engine = Engine()
    _ = engine.type("a")
    engine.reset()
    // No vowel in the new word, so s is a plain letter.
    #expect(engine.type("s") == nil)
}

@Test func anythingButALetterEndsTheWord() {
    var engine = Engine()
    _ = engine.type("a")
    #expect(engine.type("1") == nil)
    #expect(engine.type("s") == nil)
}
