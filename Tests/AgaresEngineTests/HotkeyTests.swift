import Testing
@testable import AgaresEngine

private let ctrlShift = Hotkey(modifiers: [.control, .shift])
private let ctrlShiftSpace = Hotkey(modifiers: [.control, .shift], keyCode: 49)

/// Feeds a sequence of held-modifier states and returns which steps fired.
private func fires(_ hotkey: Hotkey, _ steps: [Modifiers]) -> [Bool] {
    var matcher = HotkeyMatcher(hotkey: hotkey)
    return steps.map { matcher.modifiersChanged($0) }
}

@Test func tappingTheModifiersFiresOnRelease() {
    #expect(fires(ctrlShift, [[.control], [.control, .shift], [.control], []]) == [false, false, true, false])
}

@Test func aLargerChordPassingThroughTheShortcutNeverFires() {
    // Ctrl+Shift+Cmd+4, the screenshot-to-clipboard chord, with Cmd released first.
    let steps: [Modifiers] = [
        [.control], [.control, .shift], [.control, .shift, .command], [.control, .shift], [.control], [],
    ]
    #expect(fires(ctrlShift, steps) == [false, false, false, false, false, false])
}

@Test func theNextTapWorksAfterALargerChord() {
    let steps: [Modifiers] = [[.command], [.command, .control, .shift], [], [.shift], [.control, .shift], []]
    #expect(fires(ctrlShift, steps) == [false, false, false, false, false, true])
}

@Test func aKeyPressedDuringTheHoldCancelsIt() {
    var matcher = HotkeyMatcher(hotkey: ctrlShift)
    _ = matcher.modifiersChanged([.control, .shift])
    #expect(matcher.keyPressed(48, held: [.control, .shift]) == false)
    #expect(matcher.modifiersChanged([]) == false)
}

@Test func aClickDuringTheHoldCancelsIt() {
    var matcher = HotkeyMatcher(hotkey: ctrlShift)
    _ = matcher.modifiersChanged([.control, .shift])
    matcher.otherInput()
    #expect(matcher.modifiersChanged([]) == false)
}

@Test func typingBeforehandDoesNotBlockTheTap() {
    var matcher = HotkeyMatcher(hotkey: ctrlShift)
    #expect(matcher.keyPressed(0, held: []) == false)
    _ = matcher.modifiersChanged([.control, .shift])
    #expect(matcher.modifiersChanged([]) == true)
}

@Test func aKeyShortcutFiresOnlyOnItsExactCombination() {
    var matcher = HotkeyMatcher(hotkey: ctrlShiftSpace)
    #expect(matcher.keyPressed(49, held: [.control, .shift]) == true)
    #expect(matcher.keyPressed(49, held: [.control]) == false)
    #expect(matcher.keyPressed(49, held: [.control, .shift, .command]) == false)
    #expect(matcher.keyPressed(21, held: [.control, .shift, .command]) == false)
}

@Test func aKeyShortcutIgnoresBareModifierTaps() {
    #expect(fires(ctrlShiftSpace, [[.control, .shift], []]) == [false, false])
}

@Test func recordsAKeyWithModifiers() {
    var recorder = HotkeyRecorder()
    #expect(recorder.modifiersChanged([.control, .option]) == .pending)
    let expected = Hotkey(modifiers: [.control, .option], keyCode: 6)
    #expect(recorder.keyPressed(6, held: [.control, .option]) == .captured(expected))
}

@Test func recordsModifiersAloneWhenTheyAreReleased() {
    var recorder = HotkeyRecorder()
    _ = recorder.modifiersChanged([.control])
    _ = recorder.modifiersChanged([.control, .option])
    _ = recorder.modifiersChanged([.option])
    #expect(recorder.modifiersChanged([]) == .captured(Hotkey(modifiers: [.control, .option])))
}

@Test func ignoresWhatCannotBeAShortcut() {
    var recorder = HotkeyRecorder()
    #expect(recorder.keyPressed(0, held: []) == .pending)
    #expect(recorder.keyPressed(0, held: [.shift]) == .pending)
    _ = recorder.modifiersChanged([.shift])
    #expect(recorder.modifiersChanged([]) == .pending)
}

@Test func escapeCancelsARecording() {
    var recorder = HotkeyRecorder()
    #expect(recorder.keyPressed(53, held: []) == .cancelled)
}

@Test func commandTabStaysWithTheAppSwitcher() {
    var recorder = HotkeyRecorder()
    _ = recorder.modifiersChanged([.command, .shift])
    #expect(recorder.keyPressed(48, held: [.command, .shift]) == .pending)
    // The modifiers held for it are not captured as a shortcut either.
    #expect(recorder.modifiersChanged([]) == .pending)
}

@Test func showsKeycapsInMacOSOrder() {
    #expect(ctrlShiftSpace.keycaps == ["⌃", "⇧", "Space"])
    #expect(Hotkey(modifiers: [.command, .option, .control], keyCode: 6).keycaps == ["⌃", "⌥", "⌘", "Z"])
    #expect(Hotkey(modifiers: [.control], keyCode: 200).keycaps == ["⌃", "Key 200"])
}

@Test func spellsTheShortcutOutInWords() {
    #expect(ctrlShiftSpace.name == "Control + Shift + Space")
    #expect(Hotkey.presets[1].name == "Control + Option + Z")
    #expect(Hotkey.presets[2].name == "Control + Option")
}

@Test func theControlOptionZPresetNeedsControlNotShift() {
    var matcher = HotkeyMatcher(hotkey: Hotkey.presets[1])
    // Shift + Option + Z is not the shortcut; on the ABC layout it types ¸.
    #expect(matcher.keyPressed(6, held: [.shift, .option]) == false)
    #expect(matcher.keyPressed(6, held: [.control, .option]) == true)
}

@Test func everyPresetIsValid() {
    #expect(Hotkey.presets.map(\.isValid) == [true, true, true])
    #expect(!Hotkey(modifiers: [.shift]).isValid)
    #expect(!Hotkey(modifiers: [.shift], keyCode: 0).isValid)
}
