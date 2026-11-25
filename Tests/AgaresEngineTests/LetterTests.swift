import Testing
@testable import AgaresEngine

@Test func rendersMarkToneAndCase() {
    #expect(Letter(base: "a").rendered(tone: nil) == "a")
    #expect(Letter(base: "a", mark: .circumflex).rendered(tone: .acute) == "ấ")
    #expect(Letter(base: "a", mark: .breve).rendered(tone: .dot) == "ặ")
    #expect(Letter(base: "o", mark: .horn).rendered(tone: .hook) == "ở")
    #expect(Letter(base: "u", mark: .horn, upper: true).rendered(tone: .tilde) == "Ữ")
    #expect(Letter(base: "d", mark: .stroke, upper: true).rendered(tone: nil) == "Đ")
    #expect(Letter(base: "y").rendered(tone: .grave) == "ỳ")
}

@Test func consonantsIgnoreTheTone() {
    #expect(Letter(base: "t").rendered(tone: .acute) == "t")
}

@Test func knowsVowels() {
    #expect(Letter(base: "y").isVowel)
    #expect(!Letter(base: "d", mark: .stroke).isVowel)
}
