# Agares Control Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the hotkey that fires on larger chords, make the hotkey configurable, and add a control panel, a toggle sound, a Check for Updates command and a Dock icon that shows while the panel is open.

**Architecture:** The hotkey rules and version comparison are pure logic in the `AgaresEngine` library, with unit tests. One observable `AppModel` holds settings and state for both the menu bar item and a SwiftUI panel hosted in an `NSWindow`. Spec: `docs/superpowers/specs/2026-11-25-control-panel-design.md`.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, AppKit, SwiftUI, Combine, CoreGraphics event taps, ServiceManagement, Swift Testing. No third-party dependencies.

## Global Constraints

- Minimum macOS 13. Bundle id `com.quyennguyenvu.agares`. Signing certificate name `Agares Dev`.
- No third-party dependencies. The only network request is the update check, made at most once a day and when the user asks.
- `Sources/AgaresEngine` imports nothing: no Foundation, no AppKit.
- SwiftUI code must not use `@State`: the macro plugin it needs does not ship with Command Line Tools. All view state lives in `AppModel` (`@Published` properties read through `@ObservedObject`).
- Never run `git commit`. Each task ends with a commit checkpoint: stop and ask the user to run `/grimoire:seal`, offering the suggested message.
- Run `swift build`, `bash scripts/test.sh` and `scripts/bundle.sh` one at a time, from the main session only, never inside parallel subagents. This Mac has 16 GB of RAM.
- The test command is `bash scripts/test.sh`.
- Until the stale Command Line Tools files are removed (v1 plan, Task 0), prefix every `swift` command and script with `SWIFTPM_CUSTOM_LIBS_DIR="$HOME/.cache/agares-pm"`.
- OpenKey is GPL-3.0. Do not copy code from it.
- Never delete, skip or weaken a test to make a change pass.
- Comments explain why, in one line. No comments that restate the code.
- Any Markdown you touch must pass `npx --yes markdownlint-cli2 "docs/**/*.md"`. Prose is never hard-wrapped.
- Every source file listed under "Write" is given in full. Create or replace it with exactly that content.

## Amendments

This plan ran on 2026-11-25. Thirteen changes made afterwards are folded into the code and steps below, so the plan matches the code as it stands:

- The hotkey is also spelled out in words under the chips ("Press Control + Option + Z to switch."), and each chip carries the words as its tooltip and its VoiceOver label. The symbol ⌃ alone was read as Shift, and Shift + Option + Z types ¸ instead of switching.

- A fourth checkbox, Leave text typed by other apps alone, on by default. `KeyTap` passes through any key whose sending process is not the keyboard, so auto-type is never converted and cannot trigger the hotkey (v1 spec, 3.2).
- Nothing in the toggle waits. Settings are written on a background queue, and `StatusMenu` is told of a state change directly, so the menu bar letter changes at once; the first version listened through Combine and updated on the next turn of the run loop.
- The toggle sound is started on a background queue. Started on the main thread it blocked the key hook for up to four seconds when the audio output was asleep, so the hotkey seemed not to work (spec, section 4).
- The menu bar item has a fixed width. Sized to its letter, it changed by a point between `V` and `E` and visibly shook on every switch.
- `KeyTap` tells `Typist` to forget its cached "is Spotlight open?" answer whenever Spotlight could have opened or closed: a key with Command, Control or Option, any key that is not a letter, Space or Backspace, a click, an app switch (v1 spec, 5.1).
- The panel has a third checkbox, Allow z, w, j, f as consonants, off by default. `AppModel` saves it and `KeyTap` hands it to the engine (v1 spec, 4.8). The engine tests grew by one with it, and the hotkey tests later by two, so the counts below are 40 and 43 where they were first 37 and 40.
- A quiet update check runs at most once a day. A waiting update shows as a dot on the menu bar item, a Version … Available… menu item and a Get … button in the panel. The original plan checked only on demand.
- ⌘Q closes the panel through an unlisted second shortcut on Close Panel. With no Quit item in the main menu, ⌘Q did nothing at all in the original plan.

- The whole circle of the seal takes clicks, not only the drawn ring and letter.
- The seal is left out of the keyboard focus order, so it no longer takes a square focus ring when the panel opens.
- While Accessibility is missing, the panel offers a Reset Permission button next to Grant Accessibility.
- The app is `LSUIElement` again and shows a Dock icon only while the panel is open; the original plan made it a regular app with a permanent Dock icon.

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/AgaresEngine/Hotkey.swift` | New. `Modifiers`, `Hotkey`, `HotkeyMatcher` (when the hotkey fires), `HotkeyRecorder` (capturing a new one) |
| `Sources/AgaresEngine/Version.swift` | New. Three-number versions and their ordering |
| `Sources/Agares/AppModel.swift` | New. Settings, state and actions shared by the menu bar item and the panel |
| `Sources/Agares/Panel.swift` | New. The window and its SwiftUI views; switches the Dock icon on and off with the window |
| `Sources/Agares/UpdateCheck.swift` | New. The GitHub request and the alert that answers a manual check; `AppModel` schedules the daily one |
| `Sources/Agares/KeyTap.swift` | Replaced. Uses `HotkeyMatcher`; adds recording mode |
| `Sources/Agares/StatusMenu.swift` | Replaced. Menu, Dock and quit rules; state moves to `AppModel` |
| `Sources/Agares/main.swift`, `Resources/Info.plist` | Replaced. Still a menu bar app at launch; `Info.plist` is in the layout `plutil` writes |
| `Tests/AgaresEngineTests/HotkeyTests.swift`, `VersionTests.swift` | New |

---

### Task 1: Hotkey model, matcher and recorder

**Files:**

- Create: `Sources/AgaresEngine/Hotkey.swift`
- Test: `Tests/AgaresEngineTests/HotkeyTests.swift`

**Interfaces:**

- Consumes: nothing.
- Produces:
  - `public struct Modifiers: OptionSet, Hashable` with `.control`, `.option`, `.shift`, `.command` (raw values 1, 2, 4, 8)
  - `public struct Hotkey: Equatable` with `var modifiers: Modifiers`, `var keyCode: UInt16?`, `init(modifiers:keyCode:)`, `var isValid: Bool`, `var keycaps: [String]`, `var name: String` (the shortcut in words), `static let presets: [Hotkey]` (the first is the default)
  - `public struct HotkeyMatcher` with `var hotkey`, `init(hotkey:)`, `mutating func modifiersChanged(_ now: Modifiers) -> Bool`, `mutating func keyPressed(_ keyCode: UInt16, held: Modifiers) -> Bool`, `mutating func otherInput()`
  - `public struct HotkeyRecorder` with `enum Outcome: Equatable { case pending, cancelled, captured(Hotkey) }`, `init()`, `mutating func modifiersChanged(_ now: Modifiers) -> Outcome`, `mutating func keyPressed(_ keyCode: UInt16, held: Modifiers) -> Outcome`

Background for the implementer: the v1 hotkey (Ctrl+Shift alone) fired when the user released Ctrl+Shift+Cmd+4, because the code armed itself whenever the held modifiers became exactly Ctrl+Shift, including on the way down from a larger chord. The second test below is that exact sequence and must stay. Virtual key codes used here: Space 49, Z 6, Tab 48, Escape 53, the digit 4 is 21.

- [ ] **Step 1: Write the failing test**

Write `Tests/AgaresEngineTests/HotkeyTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/test.sh`

Expected: build fails with `cannot find 'Hotkey' in scope`.

- [ ] **Step 3: Write the implementation**

Write `Sources/AgaresEngine/Hotkey.swift`:

```swift
/// The modifier keys a shortcut can use.
public struct Modifiers: OptionSet, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = Modifiers(rawValue: 1)
    public static let option = Modifiers(rawValue: 2)
    public static let shift = Modifiers(rawValue: 4)
    public static let command = Modifiers(rawValue: 8)
}

/// The shortcut that switches Vietnamese on and off: modifiers alone, or modifiers with one key.
public struct Hotkey: Equatable {
    public var modifiers: Modifiers
    /// Virtual key code, nil for a modifiers-only shortcut.
    public var keyCode: UInt16?

    public init(modifiers: Modifiers, keyCode: UInt16? = nil) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    /// The first is the default.
    public static let presets = [
        Hotkey(modifiers: [.control, .shift], keyCode: 49),
        Hotkey(modifiers: [.control, .option], keyCode: 6),
        Hotkey(modifiers: [.control, .option]),
    ]

    /// Modifiers alone need two of them. With a key, Control, Option or Command must be held,
    /// and Command+Tab stays with the app switcher.
    public var isValid: Bool {
        guard let keyCode else { return modifiers.rawValue.nonzeroBitCount >= 2 }
        if keyCode == 48, modifiers.contains(.command) { return false }
        return !modifiers.isDisjoint(with: [.control, .option, .command])
    }

    /// Keycap labels in the order macOS shows them: ⌃ ⌥ ⇧ ⌘, then the key.
    public var keycaps: [String] {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        var caps = symbols.filter { modifiers.contains($0.0) }.map(\.1)
        if let keyCode { caps.append(keyLabels[keyCode] ?? "Key \(keyCode)") }
        return caps
    }

    /// The shortcut in words, for anyone who does not read ⌃ as Control: "Control + Option + Z".
    public var name: String {
        let words: [(Modifiers, String)] = [(.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command")]
        var parts = words.filter { modifiers.contains($0.0) }.map(\.1)
        if let keyCode { parts.append(keyLabels[keyCode] ?? "Key \(keyCode)") }
        return parts.joined(separator: " + ")
    }
}

/// Decides when the shortcut has been pressed.
public struct HotkeyMatcher {
    public var hotkey: Hotkey
    private var held: Modifiers = []
    private var armed = false
    /// This hold has seen a modifier, key or click outside the shortcut. Cleared when every modifier is up.
    private var spoiled = false

    public init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    /// Call on every modifier change. True when a modifiers-only shortcut was pressed and released cleanly.
    public mutating func modifiersChanged(_ now: Modifiers) -> Bool {
        held = now
        defer { if now.isEmpty { spoiled = false } }
        guard hotkey.keyCode == nil, !spoiled else {
            armed = false
            return false
        }
        if now == hotkey.modifiers {
            armed = true
            return false
        }
        // A larger chord such as ⌃⇧⌘4 passes through ⌃⇧ on the way up and again on the way down.
        let inside = now.isSubset(of: hotkey.modifiers)
        let fired = armed && inside
        spoiled = !inside
        armed = false
        return fired
    }

    /// Call on every key press. True when it is the shortcut; the caller swallows the key.
    public mutating func keyPressed(_ keyCode: UInt16, held: Modifiers) -> Bool {
        self.held = held
        if hotkey.keyCode == keyCode, held == hotkey.modifiers { return true }
        otherInput()
        return false
    }

    /// A key or click that is not the shortcut cancels a modifiers-only press in progress.
    public mutating func otherInput() {
        armed = false
        if !held.isEmpty { spoiled = true }
    }
}

/// Captures the next shortcut the user presses.
public struct HotkeyRecorder {
    public enum Outcome: Equatable {
        case pending, cancelled, captured(Hotkey)
    }

    private var seen: Modifiers = []
    /// A key that cannot be a shortcut was pressed during this hold, so its modifiers are not one either.
    private var poisoned = false

    public init() {}

    /// Releasing every modifier captures a modifiers-only shortcut, if two or more were held.
    public mutating func modifiersChanged(_ now: Modifiers) -> Outcome {
        guard now.isEmpty else {
            seen.formUnion(now)
            return .pending
        }
        let hotkey = Hotkey(modifiers: seen)
        let usable = hotkey.isValid && !poisoned
        seen = []
        poisoned = false
        return usable ? .captured(hotkey) : .pending
    }

    /// A key captures a shortcut when it comes with valid modifiers. Escape alone cancels.
    public mutating func keyPressed(_ keyCode: UInt16, held: Modifiers) -> Outcome {
        if keyCode == 53, held.isEmpty { return .cancelled }
        let hotkey = Hotkey(modifiers: held, keyCode: keyCode)
        if hotkey.isValid { return .captured(hotkey) }
        poisoned = !held.isEmpty
        return .pending
    }
}

/// Labels for the keys of an ANSI keyboard, by virtual key code.
private let keyLabels: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
    13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
    24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
    35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
    45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
    118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
]
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/test.sh`

Expected: exit code 0 and a line containing `Test run with 40 tests in 0 suites passed`.

- [ ] **Step 5: Commit checkpoint**

Ask the user to run `/grimoire:seal`. Suggested message: `feat(engine): add hotkey model, matcher and recorder`.

---

### Task 2: Version comparison

**Files:**

- Create: `Sources/AgaresEngine/Version.swift`
- Test: `Tests/AgaresEngineTests/VersionTests.swift`

**Interfaces:**

- Consumes: nothing.
- Produces: `public struct Version: Comparable` with `init?(_ text: String)` (accepts `0.2.0` and `v0.2.0`, refuses anything else) and `var text: String`.

- [ ] **Step 1: Write the failing test**

Write `Tests/AgaresEngineTests/VersionTests.swift`:

```swift
import Testing
@testable import AgaresEngine

@Test func readsPlainVersionsAndReleaseTags() {
    #expect(Version("0.2.0")?.text == "0.2.0")
    #expect(Version("v1.10.3")?.text == "1.10.3")
}

@Test(arguments: ["", "1.2", "1.2.3.4", "1.2.x", "v1.2.3-beta", "1..3", "-1.2.3", "latest"])
func refusesAnythingElse(text: String) {
    #expect(Version(text) == nil)
}

@Test func ordersByNumberNotByText() throws {
    #expect(try #require(Version("0.9.0")) < #require(Version("0.10.0")))
    #expect(try #require(Version("1.0.0")) > #require(Version("0.99.99")))
    #expect(try #require(Version("v0.2.0")) == #require(Version("0.2.0")))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/test.sh`

Expected: build fails with `cannot find 'Version' in scope`.

- [ ] **Step 3: Write the implementation**

Write `Sources/AgaresEngine/Version.swift`:

```swift
/// A plain three-number version such as 0.2.0. Anything else is refused rather than guessed at.
public struct Version: Comparable {
    private let parts: [Int]

    /// Accepts "0.2.0" or a release tag "v0.2.0".
    public init?(_ text: String) {
        let bare = text.hasPrefix("v") ? text.dropFirst() : text[...]
        let pieces = bare.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { piece -> Int? in
            piece.allSatisfy { ("0"..."9" as ClosedRange<Character>).contains($0) } ? Int(piece) : nil
        }
        guard pieces.count == 3, numbers.count == 3 else { return nil }
        parts = numbers
    }

    public var text: String {
        parts.map(String.init).joined(separator: ".")
    }

    public static func < (a: Version, b: Version) -> Bool {
        a.parts.lexicographicallyPrecedes(b.parts)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/test.sh`

Expected: exit code 0 and a line containing `Test run with 43 tests in 0 suites passed`.

- [ ] **Step 5: Commit checkpoint**

Ask the user to run `/grimoire:seal`. Suggested message: `feat(engine): add version comparison`.

---

### Task 3: App model, panel, updates and Dock

**Files:**

- Create: `Sources/Agares/AppModel.swift`, `Sources/Agares/Panel.swift`, `Sources/Agares/UpdateCheck.swift`
- Replace: `Sources/Agares/KeyTap.swift`, `Sources/Agares/StatusMenu.swift`, `Sources/Agares/main.swift`, `Resources/Info.plist`

**Interfaces:**

- Consumes: `Engine`, `Edit`, `Hotkey`, `Modifiers`, `HotkeyMatcher`, `HotkeyRecorder`, `Version` from `AgaresEngine`; `Typist` (unchanged) from v1.
- Produces: the `Agares` executable, a menu bar app with a panel and a Dock icon while the panel is open.

Background for the implementer: these files depend on each other and only compile together, so they are one task. `AppModel` owns the `KeyTap` and every setting; `StatusMenu` (the app delegate) and `Panel` both read it. There are no automated tests for this layer; Task 4 checks it by hand.

- [ ] **Step 1: Write the model**

Write `Sources/Agares/AppModel.swift`:

```swift
import AgaresEngine
import AppKit
import Combine
import ServiceManagement

/// The settings, state and actions that the menu bar item and the panel share.
final class AppModel: ObservableObject {
    @Published var vietnameseOn: Bool {
        didSet {
            keyTap.vietnameseOn = vietnameseOn
            stateChanged()
            save(vietnameseOn, as: "vietnameseOn")
        }
    }

    @Published var soundOn: Bool {
        didSet { save(soundOn, as: "soundOn") }
    }

    /// Lets words that start with z, f, w or j take marks (zô, jì).
    @Published var allowsZFWJ: Bool {
        didSet {
            keyTap.allowsZFWJ = allowsZFWJ
            save(allowsZFWJ, as: "allowsZFWJ")
        }
    }

    /// Leaves alone keys that another app typed, such as a password manager's auto-type.
    @Published var ignoresOtherApps: Bool {
        didSet {
            keyTap.ignoresOtherApps = ignoresOtherApps
            save(ignoresOtherApps, as: "ignoresOtherApps")
        }
    }

    @Published var hotkey: Hotkey {
        didSet {
            keyTap.hotkey = hotkey
            save(Int(hotkey.modifiers.rawValue), as: "hotkeyModifiers")
            save(hotkey.keyCode.map(Int.init) ?? -1, as: "hotkeyKeyCode")
        }
    }

    /// Accessibility is granted and the key hook is running.
    @Published private(set) var trusted = false {
        didSet { stateChanged() }
    }

    @Published private(set) var recording = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// A release newer than the running app, once a check has found one.
    @Published private(set) var availableVersion: Version? {
        didSet { stateChanged() }
    }

    /// Flipped once when the panel appears, to start the seal's breathing animation.
    @Published var breathing = false
    @Published var tryText = ""

    /// Called at once, on the main thread, when what the menu bar item shows has changed.
    var stateChanged: () -> Void = {}

    private let defaults = UserDefaults.standard
    private let keyTap = KeyTap()
    /// Nothing the toggle does may wait, because it runs inside the key hook. Settings are written on
    /// one queue (a write costs about 80 µs) and sounds are started on another: with the audio output
    /// asleep, Bluetooth headphones especially, starting one blocked its caller for up to four seconds.
    private let saveQueue = DispatchQueue(label: "com.quyennguyenvu.agares.save", qos: .utility)
    private let soundQueue = DispatchQueue(label: "com.quyennguyenvu.agares.sound", qos: .userInitiated)
    private var pendingSound: DispatchWorkItem?

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["vietnameseOn": true, "soundOn": true, "ignoresOtherApps": true])
        vietnameseOn = defaults.bool(forKey: "vietnameseOn")
        soundOn = defaults.bool(forKey: "soundOn")
        allowsZFWJ = defaults.bool(forKey: "allowsZFWJ")
        ignoresOtherApps = defaults.bool(forKey: "ignoresOtherApps")
        hotkey = Self.storedHotkey(in: defaults)

        keyTap.vietnameseOn = vietnameseOn
        keyTap.allowsZFWJ = allowsZFWJ
        keyTap.ignoresOtherApps = ignoresOtherApps
        keyTap.hotkey = hotkey
        keyTap.onHotkey = { [weak self] in self?.toggle() }
    }

    /// Asks for Accessibility once, then starts the key hook as soon as it is granted.
    func start() {
        requestPermission()
        tick()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        checkPermission()
        checkForUpdatesIfDue()
    }

    /// A check the user asked for: always answered with an alert.
    func checkForUpdates() {
        UpdateCheck.latest { [weak self] latest in
            self?.note(latest)
            UpdateCheck.report(latest: latest)
        }
    }

    func openReleasePage() {
        guard let availableVersion else { return }
        NSWorkspace.shared.open(UpdateCheck.releasePage(for: availableVersion))
    }

    /// The quiet daily check. It only switches the update dot and the "available" lines on or off.
    private func checkForUpdatesIfDue() {
        let now = Date().timeIntervalSince1970
        guard now >= defaults.double(forKey: "nextUpdateCheck") else { return }
        // Booked a day ahead before the request goes out: a check that fails waits for the next day's.
        defaults.set(now + 86_400, forKey: "nextUpdateCheck")
        UpdateCheck.latest { [weak self] latest in self?.note(latest) }
    }

    /// A check that named no version leaves what is already known alone.
    private func note(_ latest: Version?) {
        guard let latest, let current = UpdateCheck.current else { return }
        availableVersion = latest > current ? latest : nil
    }

    private func save(_ value: Any, as key: String) {
        saveQueue.async { UserDefaults.standard.set(value, forKey: key) }
    }

    func toggle() {
        vietnameseOn.toggle()
        // A sound still waiting behind a slow start is dropped, so the wait cannot end in a burst of them.
        pendingSound?.cancel()
        guard soundOn else { return }
        let name = vietnameseOn ? "Tink" : "Pop"
        let sound = DispatchWorkItem { NSSound(named: name)?.play() }
        pendingSound = sound
        soundQueue.async(execute: sound)
    }

    /// The next shortcut pressed becomes the hotkey. Escape, a click, or leaving the panel cancels.
    func record() {
        guard trusted, !recording else { return }
        recording = true
        keyTap.record { [weak self] captured in
            self?.recording = false
            if let captured { self?.hotkey = captured }
        }
    }

    func cancelRecording() {
        keyTap.cancelRecording()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Clears a grant left behind by a build from another signer, which macOS still lists as
    /// switched on but no longer honours, then asks again.
    func resetPermission() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.quyennguyenvu.agares"]
        var cleared = false
        do {
            try reset.run()
            reset.waitUntilExit()
            cleared = reset.terminationStatus == 0
        } catch {
            cleared = false
        }
        if !cleared {
            let alert = NSAlert()
            alert.messageText = "Couldn't reset the permission"
            alert.informativeText = "In System Settings → Privacy & Security → Accessibility, select Agares, remove it with the − button, then grant it again."
            alert.runModal()
        }
        requestPermission()
        openAccessibilitySettings()
    }

    /// Shows the system prompt if Accessibility is not granted, and lists Agares in System Settings.
    private func requestPermission() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(prompt)
    }

    /// Starts the hook once Accessibility is granted, and stops it if the grant is withdrawn.
    private func checkPermission() {
        let granted = AXIsProcessTrusted()
        if granted, !trusted {
            trusted = keyTap.start()
        } else if !granted, trusted {
            keyTap.stop()
            trusted = false
        }
    }

    private static func storedHotkey(in defaults: UserDefaults) -> Hotkey {
        guard defaults.object(forKey: "hotkeyModifiers") != nil else { return Hotkey.presets[0] }
        let keyCode = defaults.integer(forKey: "hotkeyKeyCode")
        let stored = Hotkey(
            modifiers: Modifiers(rawValue: UInt8(truncatingIfNeeded: defaults.integer(forKey: "hotkeyModifiers"))),
            keyCode: keyCode < 0 ? nil : UInt16(truncatingIfNeeded: keyCode))
        return stored.isValid ? stored : Hotkey.presets[0]
    }
}
```

- [ ] **Step 2: Replace the key hook**

Write `Sources/Agares/KeyTap.swift`:

```swift
import AgaresEngine
import AppKit

/// The system-wide key hook. Everything it does not handle passes through untouched.
final class KeyTap {
    var vietnameseOn = true {
        didSet { engine.reset() }
    }

    /// Whether z, f, w and j count as initial consonants. Changing it starts a fresh word.
    var allowsZFWJ = false {
        didSet { engine = Engine(allowsZFWJ: allowsZFWJ) }
    }

    /// Leaves alone keys that another app typed, such as a password manager's auto-type: they are
    /// neither converted nor taken for the hotkey.
    var ignoresOtherApps = true

    var hotkey: Hotkey {
        get { matcher.hotkey }
        set { matcher.hotkey = newValue }
    }

    /// Called when the hotkey is pressed.
    var onHotkey: () -> Void = {}

    private var engine = Engine()
    private var matcher = HotkeyMatcher(hotkey: Hotkey.presets[0])
    private var recorder: HotkeyRecorder?
    private var onRecorded: (Hotkey?) -> Void = { _ in }
    private let typist = Typist()
    private var tap: CFMachPort?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.engine.reset()
            self?.typist.forgetSpotlight()
        }
    }

    /// False when macOS refuses the tap, which means Accessibility is not granted.
    func start() -> Bool {
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue().handle(proxy, type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    func stop() {
        guard let tap else { return }
        CFMachPortInvalidate(tap)
        self.tap = nil
        cancelRecording()
        engine.reset()
    }

    /// Hands the next shortcut the user presses to `done`, or nil if they cancel.
    func record(_ done: @escaping (Hotkey?) -> Void) {
        recorder = HotkeyRecorder()
        onRecorded = done
    }

    func cancelRecording() {
        finishRecording(.cancelled)
    }

    private func finishRecording(_ outcome: HotkeyRecorder.Outcome) {
        guard recorder != nil, outcome != .pending else { return }
        recorder = nil
        if case .captured(let hotkey) = outcome {
            onRecorded(hotkey)
        } else {
            onRecorded(nil)
        }
    }

    private func handle(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Keys typed while the tap was off never reached the engine, so its word is stale.
            engine.reset()
            return pass
        case .flagsChanged:
            if isFromAnotherApp(event) { return pass }
            let held = Self.modifiers(event.flags)
            if recorder != nil {
                finishRecording(recorder!.modifiersChanged(held))
            } else if matcher.modifiersChanged(held) {
                onHotkey()
            }
            return pass
        case .keyDown:
            break
        default:
            // A mouse button: the cursor may have moved, and a click ends a recording.
            cancelRecording()
            matcher.otherInput()
            engine.reset()
            typist.forgetSpotlight()
            return pass
        }

        if event.getIntegerValueField(.eventSourceUserData) == Typist.tag { return pass }
        if isFromAnotherApp(event) {
            // Their text has moved the cursor on, so the word being tracked is over.
            engine.reset()
            typist.forgetSpotlight()
            return pass
        }
        let held = Self.modifiers(event.flags)
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

        if recorder != nil {
            let outcome = recorder!.keyPressed(keyCode, held: held)
            finishRecording(outcome)
            return outcome == .pending ? pass : nil
        }
        if matcher.keyPressed(keyCode, held: held) {
            // Holding the hotkey repeats the key; only the first press toggles.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { onHotkey() }
            return nil
        }
        if !vietnameseOn || !held.isDisjoint(with: [.control, .option, .command]) {
            engine.reset()
            typist.forgetSpotlight()
            return pass
        }

        let edit: Edit?
        if keyCode == 51 {
            edit = engine.backspace()
        } else if let letter = Self.letter(of: event) {
            edit = engine.type(letter)
        } else {
            engine.reset()
            // Space is typed constantly and cannot open or close Spotlight. Any other key might
            // (Return, Escape, a function key), so the cached answer is dropped.
            if keyCode != 49 { typist.forgetSpotlight() }
            return pass
        }
        guard let edit else { return pass }
        typist.send(edit, through: proxy)
        return nil
    }

    /// A key pressed on the keyboard has no sending process; one typed by an app carries that app's id.
    private func isFromAnotherApp(_ event: CGEvent) -> Bool {
        ignoresOtherApps && event.getIntegerValueField(.eventSourceUnixProcessID) != 0
    }

    private static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var held: Modifiers = []
        if flags.contains(.maskControl) { held.insert(.control) }
        if flags.contains(.maskAlternate) { held.insert(.option) }
        if flags.contains(.maskShift) { held.insert(.shift) }
        if flags.contains(.maskCommand) { held.insert(.command) }
        return held
    }

    /// The typed character if it is a single ASCII letter, with Shift and Caps Lock already applied.
    private static func letter(of event: CGEvent) -> Character? {
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &units)
        guard length == 1, let scalar = Unicode.Scalar(units[0]) else { return nil }
        let character = Character(scalar)
        return character.isASCII && character.isLetter ? character : nil
    }
}
```

- [ ] **Step 3: Write the update check**

Write `Sources/Agares/UpdateCheck.swift`:

```swift
import AgaresEngine
import AppKit

/// Asks GitHub for the latest release. The app's only network request: at most once a day, and on demand.
enum UpdateCheck {
    /// Hardcoded on purpose: the page we open is built from this, never from the response.
    private static let repo = "quyennguyenvu/agares"

    static var current: Version? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(Version.init)
    }

    /// Calls back on the main thread with the latest release's version, if the response named one.
    static func latest(_ done: @escaping (Version?) -> Void) {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let latest = (json?["tag_name"] as? String).flatMap(Version.init)
            DispatchQueue.main.async { done(latest) }
        }.resume()
    }

    static func releasePage(for version: Version) -> URL {
        URL(string: "https://github.com/\(repo)/releases/tag/v\(version.text)")!
    }

    /// The answer to a check the user asked for.
    static func report(latest: Version?) {
        let current = Self.current
        let alert = NSAlert()
        var page: URL?
        if let latest, let current, latest > current {
            alert.messageText = "Agares \(latest.text) is available"
            alert.informativeText = "You have \(current.text)."
            alert.addButton(withTitle: "Open Release Page")
            alert.addButton(withTitle: "Later")
            page = releasePage(for: latest)
        } else if let latest, let current {
            alert.messageText = "Agares is up to date"
            alert.informativeText = "You have \(current.text). The latest release is \(latest.text)."
        } else {
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = "GitHub could not be reached, or no release has been published yet."
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let page {
            NSWorkspace.shared.open(page)
        }
    }
}
```

- [ ] **Step 4: Write the panel**

Write `Sources/Agares/Panel.swift`:

```swift
import AgaresEngine
import AppKit
import SwiftUI

/// The control panel window. Closing it only hides it.
final class Panel: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let window: NSWindow

    init(model: AppModel) {
        self.model = model
        window = NSWindow(contentViewController: NSHostingController(rootView: PanelView(model: model)))
        super.init()
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "Agares"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Palette.bg0)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    func show() {
        // The Dock icon exists only while the panel is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    // A recording left running would capture the next shortcut pressed in another app.
    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }
}

/// Goetia's dark tokens.
private enum Palette {
    static let bg0 = rgb(0x0F1115)
    static let bg1 = rgb(0x161A20)
    static let bg2 = rgb(0x1E232B)
    static let border = rgb(0x2A303A)
    static let text1 = rgb(0xE7EAEF)
    static let text2 = rgb(0x9AA3AF)
    static let accent = rgb(0xFF9E2C)
    static let ok = rgb(0x34C77B)
    static let warn = rgb(0xF5A623)
    static let ember = LinearGradient(colors: [accent, rgb(0xE8590C)], startPoint: .topLeading, endPoint: .bottomTrailing)

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

private struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            Seal(model: model)
            tryField
            hotkeySection
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Allow z, w, j, f as consonants", isOn: $model.allowsZFWJ)
                    .help("Words such as zô and jì can then take marks. So can English words that start with these letters.")
                Toggle("Leave text typed by other apps alone", isOn: $model.ignoresOtherApps)
                    .help("A password manager's auto-type or a text expander sends keys of its own. Agares then passes them through unconverted. Turn this off if you type with an on-screen keyboard.")
                Toggle("Play a sound when toggling", isOn: $model.soundOn)
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
        .padding(EdgeInsets(top: 40, leading: 28, bottom: 24, trailing: 28))
        .frame(width: 420)
        .background(Palette.bg0)
        .foregroundColor(Palette.text1)
        .tint(Palette.accent)
    }

    private var tryField: some View {
        TextField("Try it here: tieengs vieejt", text: $model.tryText)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Palette.bg1)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.border))
    }

    private var hotkeySection: some View {
        // A recorded hotkey that is not a preset gets its own chip in front.
        let shown = Hotkey.presets.contains(model.hotkey) ? Hotkey.presets : [model.hotkey] + Hotkey.presets
        return VStack(alignment: .leading, spacing: 12) {
            Text("HOTKEY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.text2)
            HStack(spacing: 8) {
                ForEach(shown.indices, id: \.self) { index in
                    Button {
                        model.hotkey = shown[index]
                    } label: {
                        Keycaps(keys: shown[index].keycaps, lit: shown[index] == model.hotkey)
                    }
                    .buttonStyle(.plain)
                    .help(shown[index].name)
                    .accessibilityLabel(shown[index].name)
                }
            }
            // In words as well: at this size ⌃, the Control key, is easily read as an arrow for Shift.
            Text(model.hotkey.keyCode == nil
                ? "Press and release \(model.hotkey.name) to switch."
                : "Press \(model.hotkey.name) to switch.")
                .font(.system(size: 12))
                .foregroundColor(Palette.text2)
            HStack(spacing: 10) {
                Button(model.recording ? "Press the new shortcut…" : "Record…", action: model.record)
                    .disabled(!model.trusted || model.recording)
                if model.recording {
                    Text("Esc or a click cancels")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.text2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.bg1)
        .cornerRadius(10)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.trusted ? Palette.ok : Palette.warn)
                    .frame(width: 8, height: 8)
                if model.trusted {
                    Text("Accessibility granted").foregroundColor(Palette.text2)
                } else {
                    Button("Grant Accessibility…", action: model.openAccessibilitySettings)
                    Button("Reset Permission", action: model.resetPermission)
                }
                Spacer()
            }
            if !model.trusted {
                Text("Already switched on in Settings but still not working? Reset it, then grant again.")
                    .foregroundColor(Palette.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Agares \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .foregroundColor(Palette.text2)
                if let version = model.availableVersion {
                    Text("\(version.text) available").foregroundColor(Palette.accent)
                    Spacer()
                    Button("Get \(version.text)…", action: model.openReleasePage)
                } else {
                    Spacer()
                    Button("Check for Updates…", action: model.checkForUpdates)
                }
            }
        }
        .font(.system(size: 12))
    }
}

/// The app's seal. It glows and breathes while Vietnamese is on; clicking it switches.
private struct Seal: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let on = model.vietnameseOn
        Button(action: model.toggle) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(on ? AnyShapeStyle(Palette.ember) : AnyShapeStyle(Palette.border), lineWidth: 7)
                        .shadow(color: Palette.accent.opacity(on ? 0.7 : 0), radius: model.breathing ? 26 : 10)
                    Text(on ? "â" : "a")
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .foregroundStyle(on ? AnyShapeStyle(Palette.ember) : AnyShapeStyle(Palette.text2))
                }
                .frame(width: 132, height: 132)
                // Without this only the drawn ring and letter take clicks, not the space between them.
                .contentShape(Circle())
                .scaleEffect(on ? 1 : 0.94)
                Text(on ? "Vietnamese · Telex" : "English")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        // Kept out of the keyboard focus order: as the first control it took the focus ring, a square
        // around the round seal, whenever the panel opened. The hotkey is the keyboard way to toggle.
        .focusable(false)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: on)
        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: model.breathing)
        .onAppear { model.breathing = true }
        .accessibilityLabel("Vietnamese typing")
        .accessibilityValue(on ? "On" : "Off")
    }
}

/// A shortcut drawn as keys.
private struct Keycaps: View {
    let keys: [String]
    let lit: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(minWidth: 16)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Palette.bg2)
                    .cornerRadius(6)
            }
        }
        .padding(5)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(lit ? AnyShapeStyle(Palette.ember) : AnyShapeStyle(Palette.border), lineWidth: lit ? 1.5 : 1))
    }
}
```

- [ ] **Step 5: Replace the menu bar item and app delegate**

Write `Sources/Agares/StatusMenu.swift`:

```swift
import AppKit
import CoreServices

/// The menu bar item, the Dock behaviour, and the rule that only the menu bar item can quit the app.
final class StatusMenu: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private lazy var panel = Panel(model: model)
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var quitFromMenu = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        NSApp.mainMenu = Self.mainMenu()

        // Called by the model at the moment the state changes, so the letter switches without waiting for anything.
        model.stateChanged = { [weak self] in self?.refreshTitle() }
        model.start()
        refreshTitle()
        if !model.trusted { panel.show() }
    }

    private func refreshTitle() {
        let state = !model.trusted ? "⚠" : model.vietnameseOn ? "V" : "E"
        // The dot says a newer release is waiting.
        let title = model.availableVersion == nil ? state : state + " •"
        // A fixed width: V is a point wider than E, and a width that follows the letter nudges the
        // item and everything beside it in the menu bar on every switch.
        let length = model.availableVersion == nil ? NSStatusItem.squareLength : NSStatusBar.system.thickness + 10
        // This runs on every model change, so nothing is set that has not changed.
        if statusItem.length != length { statusItem.length = length }
        if statusItem.button?.title != title { statusItem.button?.title = title }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !model.trusted {
            add("Open Accessibility Settings…", #selector(openAccessibilitySettings), to: menu)
            menu.addItem(.separator())
        }
        if let version = model.availableVersion {
            add("Version \(version.text) Available…", #selector(openReleasePage), to: menu)
            menu.addItem(.separator())
        }
        add("Vietnamese", #selector(toggleVietnamese), to: menu).state = model.vietnameseOn ? .on : .off
        menu.addItem(.separator())
        add("Open Agares…", #selector(openPanel), to: menu)
        add("Check for Updates…", #selector(checkForUpdates), to: menu)
        menu.addItem(.separator())
        add("Quit Agares", #selector(quit), to: menu)
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleVietnamese() {
        model.toggle()
    }

    @objc private func openPanel() {
        panel.show()
    }

    @objc private func checkForUpdates() {
        model.checkForUpdates()
    }

    @objc private func openReleasePage() {
        model.openReleasePage()
    }

    @objc private func openAccessibilitySettings() {
        model.openAccessibilitySettings()
    }

    @objc private func quit() {
        quitFromMenu = true
        NSApp.terminate(nil)
    }

    // MARK: Dock and quitting

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitFromMenu || Self.systemIsShuttingDown() { return .terminateNow }
        // The Dock's Quit, like any other request to quit, only puts the panel away.
        panel.close()
        return .terminateCancel
    }

    /// Logout, restart and shutdown must still be able to quit the app.
    private static func systemIsShuttingDown() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        guard let reason = event?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue else { return false }
        let systemWide = [kAELogOut, kAEReallyLogOut, kAERestart, kAEShutDown, kAEShowRestartDialog, kAEShowShutdownDialog]
        return systemWide.map { OSType($0) }.contains(reason)
    }

    /// No Quit item on purpose. The Edit menu makes copy and paste work in the panel's text field.
    private static func mainMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(withTitle: "Hide Agares", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Close Panel", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        // With no Quit item, ⌘Q would do nothing at all. An unlisted second shortcut makes it close the panel.
        let alsoClose = app.addItem(withTitle: "Close Panel", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "q")
        alsoClose.isHidden = true
        alsoClose.allowsKeyEquivalentWhenHidden = true
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let main = NSMenu()
        for menu in [app, edit] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }
}
```

- [ ] **Step 6: Keep it a menu bar app at launch**

Write `Sources/Agares/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let statusMenu = StatusMenu()
app.delegate = statusMenu
// Menu bar only until the panel opens; Panel switches the Dock icon on and off.
app.setActivationPolicy(.accessory)
app.run()
```

Write `Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Agares</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.quyennguyenvu.agares</string>
	<key>CFBundleName</key>
	<string>Agares</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.2.0</string>
	<key>CFBundleVersion</key>
	<string>0.2.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 7: Build and run the tests**

Run: `swift build`

Expected: `Build complete!` with no errors.

Run: `bash scripts/test.sh`

Expected: exit code 0 and a line containing `Test run with 43 tests in 0 suites passed`.

- [ ] **Step 8: Install and confirm the key hook is live**

Run: `bash scripts/bundle.sh install`

Expected: output ends with `build/Agares.app: satisfies its Designated Requirement`, the menu bar item shows `V` or `E`, and there is no Dock icon until the panel opens (no new Accessibility prompt, since the signer is unchanged).

Then confirm the new process owns an enabled event tap:

```bash
cat > "$TMPDIR/agares-tapcheck.swift" <<'EOF'
import CoreGraphics
import Foundation

guard let pid = Int32(CommandLine.arguments.dropFirst().first ?? "") else {
    print("usage: agares-tapcheck <pid>")
    exit(2)
}
// Waits up to 12 s for an enabled event tap owned by the given process.
for _ in 0..<24 {
    var count: UInt32 = 0
    CGGetEventTapList(0, nil, &count)
    var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
    CGGetEventTapList(count, &taps, &count)
    if let tap = taps.prefix(Int(count)).first(where: { $0.tappingProcess == pid }) {
        print("tap owned by pid \(pid): enabled=\(tap.enabled)")
        exit(0)
    }
    usleep(500_000)
}
print("no event tap owned by pid \(pid)")
exit(1)
EOF
swift "$TMPDIR/agares-tapcheck.swift" "$(pgrep -x Agares)"; rm -f "$TMPDIR/agares-tapcheck.swift"
```

Expected: `tap owned by pid <n>: enabled=true`.

- [ ] **Step 9: Commit checkpoint**

Ask the user to run `/grimoire:seal`. Suggested message: `feat(app): add control panel, configurable hotkey, toggle sound and update check`.

---

### Task 4: Hand checklist

**Files:**

- Modify: only what a failing check requires.

**Interfaces:**

- Consumes: `/Applications/Agares.app` running with Accessibility granted.
- Produces: the new features confirmed by the user.

This task needs the user at the keyboard. For each failure, write down what was done and what happened, then find the cause with superpowers:systematic-debugging before changing code. A hotkey bug gets a new test in `Tests/AgaresEngineTests/HotkeyTests.swift` first.

- [ ] **Step 1: Hotkey** — press ⌃⇧Space (Control + Shift + Space) in any app. Expected: the menu bar item flips between `V` and `E`, with a sound.
- [ ] **Step 2: Screenshot chord** — press ⌃⇧⌘4 and cancel with Esc. Expected: no flip. Repeat with the ⌃⌥ preset selected and ⌃⌥⌘ plus any key.
- [ ] **Step 3: Panel** — choose Open Agares… from the menu bar item. Expected: the panel opens with no focus ring around the seal, and a Dock icon appears; the seal glows while Vietnamese is on and goes grey when off; a click anywhere inside the circle toggles.
- [ ] **Step 4: Try-it field** — type `tieengs vieejt`. Expected: `tiếng việt`.
- [ ] **Step 5: Presets** — click each preset chip, then use it. Expected: the line under the chips names the chosen hotkey in words (for the middle chip, "Press Control + Option + Z to switch."); each one toggles; the previous one no longer does. ⌃ is the Control key: Shift + Option + Z types `¸` and is not the hotkey.
- [ ] **Step 6: Record** — click Record…, press ⌃⌥V. Expected: a new chip `⌃ ⌥ V`, outlined, and it toggles. Click Record… again and press Esc, then again and click elsewhere. Expected: both cancel, the hotkey is unchanged.
- [ ] **Step 7: Sound** — untick the sound checkbox and toggle. Expected: silent.
- [ ] **Step 8: Close and quit** — close the panel with the red button, then reopen and press ⌘W, then ⌘Q, then Dock ▸ Quit. Expected: each closes the panel and takes the Dock icon away, and the menu bar item stays. Open Agares again from Launchpad or Spotlight. Expected: the panel reopens. Then choose Quit Agares from the menu bar item. Expected: the app quits.
- [ ] **Step 9: Launch at login** — tick it. Expected: Agares appears in System Settings, General, Login Items.
- [ ] **Step 10: Updates** — choose Check for Updates…. Expected: "Couldn't check for updates" until the repository is public with a release; afterwards "up to date" or the newer version. Once a release newer than the installed version exists, within a day and with nothing clicked, the menu bar item gains a dot, the menu a Version … Available… item, and the panel footer a Get … button; each opens the release page.
- [ ] **Step 11: Restart** — restart the Mac at a convenient time. Expected: Agares does not block the restart.
- [ ] **Step 12: Reset Permission** — quit Agares, switch it off under System Settings, Privacy & Security, Accessibility, and open it again. Expected: the panel opens with Grant Accessibility… and Reset Permission. Press Reset Permission and switch Agares on in the Settings page that opens. Expected: the menu bar item goes from `⚠` to `V` within two seconds.
- [ ] **Step 13: z, w, j, f as consonants** — with the checkbox off, type `zaayj` and `was` in the try-it field. Expected: `zaayj` and `ứa`. Tick the checkbox and type them again. Expected: `zậy` and `wá`.
- [ ] **Step 14: Text typed by other apps** — with Vietnamese on, type `tieengs` on the keyboard. Expected: `tiếng`, which shows keyboard keys are still converted. Then have a password manager auto-type an entry whose user name or password would be changed by Telex (for example one containing `aa` or `dd`). Expected: it arrives exactly as stored, and the menu bar letter does not flip.

- [ ] **Step 15: Commit checkpoint**

If any fix was made, ask the user to run `/grimoire:seal`. Suggested message: `fix: <what the checklist found>`.
