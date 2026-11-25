import Testing
@testable import AgaresEngine

@Test func editDeletesBackToTheFirstChangedCharacter() {
    #expect(Edit(from: "tiêng", to: "tiếng") == Edit(backspaces: 3, text: "ếng"))
    #expect(Edit(from: "hoàn", to: "hòa") == Edit(backspaces: 3, text: "òa"))
}

@Test func editOnlyAppendsWhenNothingChanged() {
    #expect(Edit(from: "t", to: "tư") == Edit(backspaces: 0, text: "ư"))
}
