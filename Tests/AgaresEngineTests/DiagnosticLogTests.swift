import Testing
@testable import AgaresEngine

@Test func keepsTheNewestLinesAndDropsTheOldest() {
    var log = DiagnosticLog()
    for number in 1...DiagnosticLog.capacity + 5 { log.note("line \(number)") }
    #expect(log.lines.count == DiagnosticLog.capacity)
    #expect(log.lines.first == "line 6")
    #expect(log.lines.last == "line 205")
}

@Test func reportPutsTheHeaderFirstThenTheLinesOldestFirst() {
    var log = DiagnosticLog()
    log.note("09:14:02  [app] started 0.2.0")
    log.note("14:03:22  [tap] disabled by timeout")
    let report = log.report(header: ["Agares 0.2.0", "Now: tap enabled"])
    #expect(report == "Agares 0.2.0\nNow: tap enabled\n\n09:14:02  [app] started 0.2.0\n14:03:22  [tap] disabled by timeout")
}

@Test func reportOfAnEmptyLogIsTheHeaderAlone() {
    #expect(DiagnosticLog().report(header: ["Agares 0.2.0"]) == "Agares 0.2.0\n")
}

@Test func cleanLeavesABundleIdAsItIs() {
    #expect(DiagnosticLog.clean("com.keepassxc.keepassxc") == "com.keepassxc.keepassxc")
    #expect(DiagnosticLog.clean("org.pqrs.Karabiner-Elements_2") == "org.pqrs.Karabiner-Elements_2")
}

@Test(arguments: [
    ("evil\n2026-11-27 09:00:00  [tap] forged", "evil2026-11-27090000tapforged"),
    ("tab\there\r\n", "tabhere"),
    ("right-to-left\u{202E}override", "right-to-leftoverride"),
    ("tiếng việt", "tingvit"),
    ("", ""),
])
func cleanDropsWhatCouldForgeALine(text: String, cleaned: String) {
    #expect(DiagnosticLog.clean(text) == cleaned)
}

@Test func cleanClipsAtEightyCharacters() {
    #expect(DiagnosticLog.clean(String(repeating: "a", count: 200)) == String(repeating: "a", count: 80))
}

@Test func takesAStoredLineApart() throws {
    let parts = try #require(DiagnosticLog.parts(of: "2026-11-27 13:26:15  [tap] passing keys from org.keepassxc.keepassxc"))
    #expect(parts == DiagnosticLog.Parts(date: "2026-11-27", time: "13:26:15", tag: "tap", text: "passing keys from org.keepassxc.keepassxc"))
}

@Test(arguments: ["", "[tap] no stamp", "2026-11-27 13:26:15", "2026-11-27 13:26:15  no tag here", "2026-11-27 13:26:15  [tap]"])
func refusesALineOfAnotherShape(line: String) {
    #expect(DiagnosticLog.parts(of: line) == nil)
}

@Test func stampsTodayWithTheTimeAndOlderLinesWithTheDay() throws {
    let parts = try #require(DiagnosticLog.parts(of: "2026-11-26 09:05:59  [app] started 0.2.0"))
    #expect(parts.stamp(today: "2026-11-26") == "09:05:59")
    #expect(parts.stamp(today: "2026-11-27") == "11-26 09:05")
}
