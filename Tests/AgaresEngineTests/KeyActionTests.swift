import Testing
@testable import AgaresEngine

private let backspace: UInt16 = 51
private let space: UInt16 = 49
private let returnKey: UInt16 = 36

/// An engine that has seen the word "a", so a following s would make it á.
private func afterA() -> Engine {
    var engine = Engine()
    _ = engine.type("a")
    return engine
}

@Test(arguments: [Modifiers.command, .control, .option])
func aShortcutReachesTheAppAndEndsTheWord(modifier: Modifiers) {
    var engine = afterA()
    #expect(engine.press(1, letter: "s", held: modifier, vietnameseOn: true) == .passMaybeSpotlight)
    #expect(engine.press(1, letter: "s", held: [], vietnameseOn: true) == .pass)
}

@Test func shiftAloneIsTyping() {
    var engine = afterA()
    #expect(engine.press(1, letter: "S", held: .shift, vietnameseOn: true) == .edit(Edit(backspaces: 1, text: "á")))
}

@Test func backspaceGoesToTheEngine() {
    var engine = Engine()
    for key in "hoafn" { _ = engine.type(key) }
    #expect(engine.press(backspace, letter: nil, held: [], vietnameseOn: true) == .edit(Edit(backspaces: 3, text: "òa")))
    #expect(engine.press(backspace, letter: nil, held: .shift, vietnameseOn: true) == .pass)
}

@Test func spaceEndsTheWordAndKeepsTheSpotlightAnswer() {
    var engine = afterA()
    #expect(engine.press(space, letter: nil, held: [], vietnameseOn: true) == .pass)
    #expect(engine.press(1, letter: "s", held: [], vietnameseOn: true) == .pass)
}

@Test func anotherKeyEndsTheWordAndMayMoveSpotlight() {
    var engine = afterA()
    #expect(engine.press(returnKey, letter: nil, held: [], vietnameseOn: true) == .passMaybeSpotlight)
    #expect(engine.press(1, letter: "s", held: [], vietnameseOn: true) == .pass)
}

@Test func englishModeLeavesEveryKeyAlone() {
    var engine = Engine()
    #expect(engine.press(0, letter: "a", held: [], vietnameseOn: false) == .passMaybeSpotlight)
    #expect(engine.press(1, letter: "s", held: [], vietnameseOn: false) == .passMaybeSpotlight)
}
