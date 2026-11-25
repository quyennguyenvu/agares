import Testing
@testable import AgaresEngine

private func shape(_ word: String) -> Shape {
    Shape(word.map { Letter(base: $0) })
}

@Test(arguments: ["a", "tieng", "nguoi", "qua", "gi", "gin", "gia", "quyen", "khuyu", "nghieng", "xoong", "uong"])
func acceptsVietnameseShapes(word: String) {
    #expect(shape(word).isValid)
}

@Test(arguments: ["css", "class", "tieb", "taa", "stu", "expect", "qu", "tr"])
func rejectsOtherShapes(word: String) {
    #expect(!shape(word).isValid)
}

@Test func vowelGroupLeavesOutTheGlideOfQuAndGi() {
    #expect(shape("qua").vowels == 2..<3)
    #expect(shape("gia").vowels == 2..<3)
    #expect(shape("gi").vowels == 1..<2)
    #expect(shape("gin").vowels == 1..<2)
    #expect(shape("nguoi").vowels == 2..<5)
}

@Test func onlyStopFinalsRestrictTheTone() {
    #expect(shape("cat").endsInStop)
    #expect(shape("cach").endsInStop)
    #expect(!shape("can").endsInStop)
    #expect(!shape("ca").endsInStop)
}

@Test(arguments: [
    ("a", 0), ("hoa", 1), ("hoan", 2), ("thuy", 2), ("mai", 1),
    ("ngoai", 3), ("khuyu", 3), ("qua", 2), ("gi", 1), ("gia", 2),
])
func plainVowelsPlaceTheToneByCount(word: String, index: Int) {
    #expect(shape(word).toneIndex == index)
}

@Test func aMarkedVowelTakesTheTone() {
    // người: the second of the two marked vowels
    let nguoi = [
        Letter(base: "n"), Letter(base: "g"), Letter(base: "u", mark: .horn),
        Letter(base: "o", mark: .horn), Letter(base: "i"),
    ]
    #expect(Shape(nguoi).toneIndex == 3)
    // giữa: the only marked vowel, though it comes first
    let giua = [Letter(base: "g"), Letter(base: "i"), Letter(base: "u", mark: .horn), Letter(base: "a")]
    #expect(Shape(giua).toneIndex == 2)
}

@Test func noVowelMeansNoTone() {
    #expect(shape("css").toneIndex == nil)
}
