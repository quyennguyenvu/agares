# Agares Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record what goes wrong in Agares in a 200-line log that is mirrored to the macOS unified log, and add a Copy Diagnostics command that puts a report on the clipboard.

**Architecture:** The ring and the report text are pure logic in the `AgaresEngine` library (`DiagnosticLog`), with unit tests. One `Diagnostics` enum in the app owns the ring, stamps and mirrors each line, and reads the system state for the report's header. `KeyTap`, `Typist`, `AppModel` and `UpdateCheck` call `Diagnostics.note` at the points where something goes wrong or a state changes. Spec: `docs/superpowers/specs/2026-11-27-diagnostics-design.md`.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, AppKit, Carbon (Secure Input and the keyboard input source), `os.Logger`, CoreGraphics event taps, Swift Testing. No third-party dependencies.

**Verified while planning (2026-11-27):** every file under "Write" below was built and tested in a scratch copy of the repo: `swift build` ended with `Build complete!` and `bash scripts/test.sh` with 50 tests passed. `Diagnostics` was also run outside the app and produced the report and the unified-log lines described here. The app itself has not been run with this code.

## Global Constraints

- Minimum macOS 13. Bundle id `com.quyennguyenvu.agares`, which is also the unified-log subsystem. Signing certificate name `Agares Dev`.
- No third-party dependencies. Diagnostics send nothing: the only network request stays the update check.
- `Sources/AgaresEngine` imports nothing: no Foundation, no AppKit. That is why the app, not `DiagnosticLog`, stamps each line with the time.
- A line is written when something goes wrong or a state changes. No line may be written once per keystroke.
- A line never holds a key, a key code, a character, a word, a per-keystroke count or a window title.
- Text Agares did not write (a bundle id, a process name, an error domain) goes through `DiagnosticLog.clean` before it enters a line.
- `Diagnostics` is used on the main thread only. The key hook, the tick and the update check's callback already run there.
- Never run `git commit`. Each task ends with a commit checkpoint: stop and ask the user to run `/grimoire:seal`, offering the suggested message.
- Run `swift build`, `bash scripts/test.sh` and `bash scripts/bundle.sh` one at a time, from the main session only, never inside parallel subagents. This Mac has 16 GB of RAM.
- The test command is `bash scripts/test.sh`.
- Never delete, skip or weaken a test to make a change pass.
- Comments explain why, in one line. No comments that restate the code.
- Any Markdown you touch must pass `npx --yes markdownlint-cli2 "docs/**/*.md" README.md`. Prose is never hard-wrapped.
- Every source file listed under "Write" is given in full. Create or replace it with exactly that content.

## Amendments

This plan ran on 2026-11-27. Changes made afterwards are folded into the code and steps below, so the plan matches the code as it stands:

- The menu bar item keeps its `V` or `E` while Accessibility is missing and shows a small yellow warning sign at the lower right of the letter. The sign is a view of its own laid over the button, so it adds no width and the letter does not move. Until then a plain `⚠` replaced the letter, and the user found it hard to see (hand checklist, step 3). Two earlier versions failed in the real menu bar: beside the letter the sign widened the item and pushed its neighbours along, and as the button's image it moved the letter.
- Task 4 was added: the log is read on a page of the panel, and Copy Diagnostics in the menu bar became Diagnostics…. Once Task 4 has run, the files printed in Tasks 1 and 2 are shown as they stand after it, so Task 1's test file holds Task 4's three tests as well and gives 53 tests where the steps of Tasks 1 and 2 say 50. Task 3's checklist was run before the page existed, which is why it reads the report by pasting it.
- `Typist` also takes an on-screen window owned by "Siri", above the level of ordinary windows, for the search bar. On macOS 27 the Siri AI app shows the search bar and no process called Spotlight runs, so the old check never matched and text typed there came out garbled (hand checklist, step 6). The missing `[typist] spotlight mode on` line is what showed it.

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/AgaresEngine/DiagnosticLog.swift` | New. The ring of the newest 200 lines, the report text, and `clean` for text from outside |
| `Tests/AgaresEngineTests/DiagnosticLogTests.swift` | New |
| `Sources/Agares/Diagnostics.swift` | New. The app's one ring; the time stamp and the unified-log mirror; the launch, wake and Secure Input lines; the report header's probes |
| `Sources/Agares/KeyTap.swift` | Replaced. Notes the disabled events, slow callbacks and keys from other apps; `isEnabled` and `revive()` for the tick |
| `Sources/Agares/Typist.swift` | Replaced. Notes a change of Spotlight mode |
| `Sources/Agares/UpdateCheck.swift` | Replaced. Notes a failed check with its cause |
| `Sources/Agares/AppModel.swift` | Replaced. Notes permission changes and the reset and login-item failures; the tick revives the hook and checks Secure Input; `copyDiagnostics()` |
| `Sources/Agares/StatusMenu.swift` | Replaced. Starts `Diagnostics`; the Copy Diagnostics menu item |
| `scripts/sync-plans.py` | Modified. The copies of the five replaced files in the two older plans become expected differences |
| `README.md` | Modified. A "Reporting a problem" section, the `log show` command, the line count |

---

### Task 1: The log

**Files:**

- Create: `Sources/AgaresEngine/DiagnosticLog.swift`
- Test: `Tests/AgaresEngineTests/DiagnosticLogTests.swift`

**Interfaces:**

- Consumes: nothing.
- Produces: `DiagnosticLog` with `static let capacity: Int` (200), `init()`, `var lines: [String]` (oldest first, read-only outside), `mutating func note(_ line: String)`, `func report(header: [String]) -> String`, and `static func clean(_ text: String) -> String`.

- [x] **Step 1: Write the failing test**

Write `Tests/AgaresEngineTests/DiagnosticLogTests.swift`:

```swift
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
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bash scripts/test.sh 2>&1 | grep -E "error:|Test run with"`

Expected: the build fails, with lines containing `error: cannot find 'DiagnosticLog' in scope`.

- [x] **Step 3: Write the implementation**

Write `Sources/AgaresEngine/DiagnosticLog.swift`:

```swift
/// What went wrong since the app started: the newest lines, and the text a report is made of.
public struct DiagnosticLog {
    /// A burst of trouble rotates the log; it cannot grow it.
    public static let capacity = 200

    /// Oldest first.
    public private(set) var lines: [String] = []

    public init() {}

    public mutating func note(_ line: String) {
        if lines.count == Self.capacity { lines.removeFirst() }
        lines.append(line)
    }

    /// The header, a blank line, then every line, oldest first.
    public func report(header: [String]) -> String {
        (header + [""] + lines).joined(separator: "\n")
    }

    /// A stored line taken apart for display.
    public struct Parts: Equatable {
        public let date: String
        public let time: String
        public let tag: String
        public let text: String

        public init(date: String, time: String, tag: String, text: String) {
            self.date = date
            self.time = time
            self.tag = tag
            self.text = text
        }

        /// The time for a line written today; the day and the time to the minute for an older one.
        public func stamp(today: String) -> String {
            date == today ? time : "\(date.dropFirst(5)) \(time.prefix(5))"
        }
    }

    /// Splits "2026-11-27 13:26:15  [tap] secure input on" into its parts. Nil for any other shape.
    public static func parts(of line: String) -> Parts? {
        let pieces = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard pieces.count == 4, pieces[2].hasPrefix("["), pieces[2].hasSuffix("]") else { return nil }
        return Parts(
            date: String(pieces[0]), time: String(pieces[1]),
            tag: String(pieces[2].dropFirst().dropLast()), text: String(pieces[3]))
    }

    /// For text Agares did not write, such as another app's bundle id: a line break in it would
    /// forge a line in a report that is meant to be sent. Keeps ASCII letters and digits, ".", "-"
    /// and "_", up to 80 characters.
    public static func clean(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-", "_": return true
            default: return false
            }
        }
        return String(String.UnicodeScalarView(kept.prefix(80)))
    }
}
```

`clean` filters Unicode scalars, not characters, on purpose: a character can be a letter followed by any number of combining marks, and only a scalar-by-scalar rule keeps those out.

- [x] **Step 4: Run the test to verify it passes**

Run: `bash scripts/test.sh 2>&1 | grep -E "error:|Test run with"`

Expected: one line, `Test run with 50 tests in 0 suites passed` (44 before this task, six added).

- [ ] **Step 5: Commit checkpoint**

Ask the user to run `/grimoire:seal`. Suggested message: `feat(engine): add the diagnostic log`.

---

### Task 2: Notes, the report and the menu item

**Files:**

- Create: `Sources/Agares/Diagnostics.swift`
- Replace: `Sources/Agares/KeyTap.swift`, `Sources/Agares/Typist.swift`, `Sources/Agares/UpdateCheck.swift`, `Sources/Agares/AppModel.swift`, `Sources/Agares/StatusMenu.swift`
- Modify: `scripts/sync-plans.py`, `README.md`

**Interfaces:**

- Consumes: `DiagnosticLog` from Task 1, exactly as listed there. `UpdateCheck.current: Version?` and `Version.text: String`, `Hotkey.name: String`, which exist already.
- Produces, all `static` on `enum Diagnostics`: `note(_ line: String)`, `start()`, `tick()`, `notePassing(_ pid: pid_t)`, `report(settings: String, accessibility: Bool, tap: String) -> String`. On `KeyTap`: `var isEnabled: Bool` and `func revive()`. On `AppModel`: `func copyDiagnostics()`.

The lines these files write, and when, are the table in section 3 of the spec. Read it before reviewing the code.

- [x] **Step 1: Write the app's side of the log**

Write `Sources/Agares/Diagnostics.swift`:

```swift
import AgaresEngine
import AppKit
import Carbon
import os

/// The app's one diagnostic log, and what its report reads at the moment it is copied.
/// Main thread only: the key hook, the tick and every callback that notes run there.
///
/// A line is written when something goes wrong or a state changes, never once per keystroke, and
/// never holds a key, a character or a word.
enum Diagnostics {
    private static var log = DiagnosticLog()
    private static var launched = Date()
    private static let system = Logger(subsystem: "com.quyennguyenvu.agares", category: "diagnostics")
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// The app most recently in front, other than Agares.
    private static var lastApp = "none"
    private static var secureInput = false
    private static var passed: Set<String> = []

    /// Called after each line is written, so an open diagnostics page can show it.
    static var onNote: () -> Void = {}

    static func note(_ line: String) {
        log.note("\(clock.string(from: Date()))  \(line)")
        // Notice is the lowest level macOS keeps on disk. Public, or the line reads back as <private>.
        system.notice("\(line, privacy: .public)")
        onNote()
    }

    /// What the panel's diagnostics page shows: the state of this moment, and the lines newest first.
    struct Page: Equatable {
        let tap: String
        let secureInput: String
        let inputSource: String
        let otherTools: String
        let lastApp: String
        /// As the lines are stamped, to tell a line written today from an older one.
        let today: String
        let lines: [String]
    }

    static func page(tap: String) -> Page {
        Page(
            tap: tap, secureInput: secureInputNow(), inputSource: inputSource(), otherTools: otherTypingTools(),
            lastApp: lastApp, today: String(clock.string(from: Date()).prefix(10)), lines: log.lines.reversed())
    }

    /// Notes the launch, and starts watching for wake and for the app in front.
    static func start() {
        launched = Date()
        note("[app] started \(UpdateCheck.current?.text ?? "dev")")
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            note("[app] woke from sleep")
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
            remember(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        remember(NSWorkspace.shared.frontmostApplication)
    }

    /// Called every two seconds. While Secure Input is on the key hook receives no keys at all.
    static func tick() {
        let on = IsSecureEventInputEnabled()
        guard on != secureInput else { return }
        secureInput = on
        note(on ? "[tap] secure input on" : "[tap] secure input off")
    }

    /// Once per app: a tool that starts a process for every burst of keys would otherwise fill the log.
    static func notePassing(_ pid: pid_t) {
        let sender = name(of: pid)
        if passed.insert(sender).inserted { note("[tap] passing keys from \(sender)") }
    }

    /// The text the page's Copy button puts on the clipboard.
    static func report(settings: String, accessibility: Bool, tap: String) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let up = Int(Date().timeIntervalSince(launched))
        return log.report(header: [
            "Agares \(UpdateCheck.current?.text ?? "dev") · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · up \(up / 3600)h \(up / 60 % 60)m",
            "Settings: \(settings)",
            "Now: accessibility \(accessibility ? "granted" : "missing") · tap \(tap) · secure input \(secureInputNow()) · input source \(inputSource()) · other typing tools \(otherTypingTools()) · last app \(lastApp)",
        ])
    }

    private static func remember(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != getpid() else { return }
        lastApp = name(of: app.processIdentifier)
    }

    /// An app's bundle id; a process that is not an app is named by its executable.
    private static func name(of pid: pid_t) -> String {
        var name = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        if name.isEmpty {
            var buffer = [CChar](repeating: 0, count: 64)
            proc_name(pid, &buffer, UInt32(buffer.count))
            name = String(cString: buffer)
        }
        let cleaned = DiagnosticLog.clean(name)
        return cleaned.isEmpty ? "unknown" : cleaned
    }

    private static func secureInputNow() -> String {
        guard IsSecureEventInputEnabled() else { return "off" }
        // Not a documented key. Without it the report still says that Secure Input is on.
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        guard let holder = session?["kCGSSessionSecureInputPID"] as? pid_t else { return "ON" }
        return "ON (held by \(name(of: holder)))"
    }

    private static func inputSource() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "unknown" }
        return DiagnosticLog.clean(Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String)
    }

    /// Running tools that would convert the same keys a second time.
    private static func otherTypingTools() -> String {
        let found = NSWorkspace.shared.runningApplications
            .compactMap(\.bundleIdentifier)
            .filter { id in ["openkey", "gotiengviet", "evkey"].contains { id.lowercased().contains($0) } }
        return found.isEmpty ? "none" : found.map(DiagnosticLog.clean).joined(separator: ", ")
    }
}
```

Three things here are easy to get wrong:

- `launched` is set in `start()`. A `static let` holding `Date()` would be made on first use, which is the first report, and the uptime would always read zero.
- `passed` holds names, not process ids. A command-line tool that types starts a new process each time it is run, and one line per process would fill the log.
- `kCGSSessionSecureInputPID` names the app macOS holds responsible, which for a command-line tool is the app that launched it.

- [x] **Step 2: Replace the key hook**

Changes from the file as it stands: `notedSenders`; `isEnabled` and `revive()`; in `handle`, the timing with `did` and its `defer`, the line for the two disabled events, and `did = …` before the hotkey, a recording and an edit; `isFromAnotherApp` reports each sending process once.

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
    /// The other apps whose keys have been reported to Diagnostics, so each lookup is made once.
    private var notedSenders: Set<Int64> = []

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

    /// False while macOS has the hook switched off, and while it is not running.
    var isEnabled: Bool {
        tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    /// Switches the hook back on if macOS switched it off without sending the event that says so.
    func revive() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        engine.reset()
        Diagnostics.note("[tap] found disabled, re-enabled")
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
        // What this run did that could have waited, for the line written if it was slow.
        var did = "pass"
        let began = DispatchTime.now().uptimeNanoseconds
        defer {
            let ms = (DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
            if ms > 50 { Diagnostics.note("[tap] slow callback: \(ms) ms (\(did))") }
        }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Diagnostics.note(type == .tapDisabledByTimeout ? "[tap] disabled by timeout" : "[tap] disabled by user input")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Keys typed while the tap was off never reached the engine, so its word is stale.
            engine.reset()
            return pass
        case .flagsChanged:
            if isFromAnotherApp(event) { return pass }
            let held = Self.modifiers(event.flags)
            if recorder != nil {
                did = "record"
                finishRecording(recorder!.modifiersChanged(held))
            } else if matcher.modifiersChanged(held) {
                did = "hotkey"
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
            did = "record"
            let outcome = recorder!.keyPressed(keyCode, held: held)
            finishRecording(outcome)
            return outcome == .pending ? pass : nil
        }
        if matcher.keyPressed(keyCode, held: held) {
            did = "hotkey"
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
        did = "edit"
        typist.send(edit, through: proxy)
        return nil
    }

    /// A key pressed on the keyboard has no sending process; one typed by an app carries that app's id.
    private func isFromAnotherApp(_ event: CGEvent) -> Bool {
        let sender = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard ignoresOtherApps, sender != 0 else { return false }
        if notedSenders.insert(sender).inserted { Diagnostics.notePassing(pid_t(truncatingIfNeeded: sender)) }
        return true
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

- [x] **Step 3: Replace the typist**

Changes: `notedSpotlight`, and the line written in `spotlightIsOpen` when a fresh lookup's answer differs from it.

Write `Sources/Agares/Typist.swift`:

```swift
import AgaresEngine
import AppKit

/// Replays an Edit in the focused app as synthetic key events.
final class Typist {
    /// Marks our own events so KeyTap lets them through.
    static let tag: Int64 = 0x4147_4152

    // A private source keeps physically held modifiers (Shift while typing capitals) off our events.
    private let source = CGEventSource(stateID: .privateState)

    func send(_ edit: Edit, through proxy: CGEventTapProxy) {
        if edit.backspaces > 0 {
            if spotlightIsOpen() {
                // Select the old characters; the text typed next replaces them.
                for _ in 0..<edit.backspaces { press(123, flags: .maskShift, proxy) }
            } else {
                // An invisible character first: in a field with inline autocomplete it replaces the
                // highlighted suggestion, so the backspaces then delete real text.
                type("\u{202F}", proxy)
                for _ in 0...edit.backspaces { press(51, flags: [], proxy) }
            }
        }
        type(edit.text.precomposedStringWithCanonicalMapping, proxy)
    }

    private func press(_ keyCode: CGKeyCode, flags: CGEventFlags, _ proxy: CGEventTapProxy) {
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { continue }
            event.flags.formUnion(flags)
            post(event, proxy)
        }
    }

    private func type(_ text: String, _ proxy: CGEventTapProxy) {
        guard !text.isEmpty else { return }
        let units = Array(text.utf16)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(event, proxy)
        }
    }

    // Posting through the tap keeps our events in order with the keys still queued behind them.
    private func post(_ event: CGEvent, _ proxy: CGEventTapProxy) {
        event.setIntegerValueField(.eventSourceUserData, value: Typist.tag)
        event.tapPostEvent(proxy)
    }

    /// The last answer of `spotlightIsOpen`, and when it was found. Asking macOS for its windows costs
    /// about a millisecond, far too much for every keystroke, so the answer is reused.
    private var spotlightOpen: Bool?
    private var spotlightCheckedAt = 0.0
    /// The answer last written to Diagnostics, which outlives `forgetSpotlight`.
    private var notedSpotlight = false

    /// Call when Spotlight may have opened or closed: a shortcut, an unusual key, a click, an app switch.
    func forgetSpotlight() {
        spotlightOpen = nil
    }

    private func spotlightIsOpen() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        // The two seconds cover ways of opening Spotlight that the key hook never sees.
        if let spotlightOpen, now - spotlightCheckedAt < 2 { return spotlightOpen }
        let open = lookForSpotlight()
        spotlightOpen = open
        spotlightCheckedAt = now
        if open != notedSpotlight {
            notedSpotlight = open
            Diagnostics.note(open ? "[typist] spotlight mode on" : "[typist] spotlight mode off")
        }
        return open
    }

    private func lookForSpotlight() -> Bool {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Spotlight" { return true }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return (windows as? [[String: Any]] ?? []).contains { window in
            switch window[kCGWindowOwnerName as String] as? String {
            case "Spotlight": return true
            // On macOS 27 the Siri AI app shows the search bar, as a panel above ordinary windows
            // that never becomes the front app. That app's ordinary windows are not the search bar.
            case "Siri": return (window[kCGWindowLayer as String] as? Int ?? 0) > 0
            default: return false
            }
        }
    }
}
```

- [x] **Step 4: Replace the update check**

Changes: `latest` keeps the response and the error it used to discard, and notes a check that named no version; `cause` is new.

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
        URLSession.shared.dataTask(with: url) { data, response, error in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let latest = (json?["tag_name"] as? String).flatMap(Version.init)
            let status = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                if latest == nil { Diagnostics.note("[update] check failed: \(cause(error, status))") }
                done(latest)
            }
        }.resume()
    }

    /// Why a check named no version, from codes alone.
    private static func cause(_ error: Error?, _ status: Int?) -> String {
        if let error = error as NSError? { return "\(DiagnosticLog.clean(error.domain)) \(error.code)" }
        if let status, status != 200 { return "HTTP \(status)" }
        return "no version in the response"
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

- [x] **Step 5: Replace the model**

Changes: `tapRefused`; `tick` revives the hook and calls `Diagnostics.tick()`; `copyDiagnostics()` is new; `setLaunchAtLogin`, `resetPermission` and `checkPermission` note their failures and changes.

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

    /// What the diagnostics page shows while it is open; nil while the settings show.
    @Published private(set) var diagnostics: Diagnostics.Page?

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
    /// Accessibility is granted but macOS will not start the hook. Kept so it is noted once, not every tick.
    private var tapRefused = false

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
        Diagnostics.onNote = { [weak self] in
            guard self?.diagnostics != nil else { return }
            // Later, not now: the line may have been written inside the key hook, which must not wait.
            DispatchQueue.main.async { self?.refreshDiagnostics() }
        }
    }

    /// Asks for Accessibility once, then starts the key hook as soon as it is granted.
    func start() {
        requestPermission()
        tick()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        checkPermission()
        keyTap.revive()
        Diagnostics.tick()
        refreshDiagnostics()
        checkForUpdatesIfDue()
    }

    func showDiagnostics() {
        diagnostics = Diagnostics.page(tap: tapState)
    }

    func hideDiagnostics() {
        diagnostics = nil
    }

    /// Keeps an open page current. Called when a line is written and on every tick.
    private func refreshDiagnostics() {
        guard diagnostics != nil else { return }
        let page = Diagnostics.page(tap: tapState)
        if page != diagnostics { diagnostics = page }
    }

    private var tapState: String {
        !trusted ? "not started" : keyTap.isEnabled ? "enabled" : "DISABLED"
    }

    /// Puts the diagnostics report on the clipboard.
    func copyDiagnostics() {
        func word(_ on: Bool) -> String { on ? "on" : "off" }
        let settings = [
            "Vietnamese \(word(vietnameseOn))", "hotkey \(hotkey.name)", "z, w, j, f \(word(allowsZFWJ))",
            "leave other apps' keys \(word(ignoresOtherApps))", "sound \(word(soundOn))",
            "launch at login \(word(launchAtLogin))",
        ].joined(separator: " · ")
        let report = Diagnostics.report(settings: settings, accessibility: AXIsProcessTrusted(), tap: tapState)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
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
            let cause = error as NSError
            Diagnostics.note("[login] launch at login failed: \(DiagnosticLog.clean(cause.domain)) \(cause.code)")
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
            Diagnostics.note("[perm] reset failed")
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
        if !granted { tapRefused = false }
        if granted, !trusted {
            trusted = keyTap.start()
            if trusted {
                Diagnostics.note("[perm] accessibility granted")
            } else if !tapRefused {
                Diagnostics.note("[perm] granted, but macOS refused the tap")
            }
            tapRefused = !trusted
        } else if !granted, trusted {
            keyTap.stop()
            trusted = false
            Diagnostics.note("[perm] accessibility withdrawn")
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

- [x] **Step 6: Replace the menu bar item and app delegate**

Changes: `Diagnostics.start()` before `model.start()`, so `[app] started` comes before `[perm] accessibility granted`; the Copy Diagnostics menu item and its action.

Write `Sources/Agares/StatusMenu.swift`:

```swift
import AppKit
import CoreServices

/// The warning badge. Clicks pass through it to the menu bar button underneath.
private final class Badge: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

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
        Diagnostics.start()
        model.start()
        refreshTitle()
        if !model.trusted { panel.show() }
    }

    private func refreshTitle() {
        let state = model.vietnameseOn ? "V" : "E"
        // The dot says a newer release is waiting.
        let title = model.availableVersion == nil ? state : state + " •"
        // A fixed width: V is a point wider than E, and a width that follows the letter nudges the
        // item and everything beside it in the menu bar on every switch.
        let length = model.availableVersion == nil ? NSStatusItem.squareLength : NSStatusBar.system.thickness + 10
        // This runs on every model change, so nothing is set that has not changed.
        if statusItem.length != length { statusItem.length = length }
        if statusItem.button?.title != title { statusItem.button?.title = title }
        if warningBadge.isHidden != model.trusted { warningBadge.isHidden = model.trusted }
    }

    /// A small yellow sign at the lower right of the letter while Accessibility is missing. It is a
    /// view of its own laid over the button, so it takes no room and the letter stays where it is:
    /// set as the button's image, it moved the letter.
    private lazy var warningBadge: NSView = {
        let size = NSImage.SymbolConfiguration(pointSize: 8, weight: .black)
        // Its own colours: left as a template it would take the menu bar's text colour.
        let colors = NSImage.SymbolConfiguration(paletteColors: [.black, .systemYellow])
        let badge = Badge()
        badge.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Accessibility permission missing")?
            .withSymbolConfiguration(size.applying(colors))
        badge.translatesAutoresizingMaskIntoConstraints = false
        if let button = statusItem.button {
            button.addSubview(badge)
            // From the middle of the letter, which sits half a bar's height from the leading edge
            // whatever the item's width: as far down as to the right, on the diagonal.
            NSLayoutConstraint.activate([
                badge.centerXAnchor.constraint(equalTo: button.leadingAnchor, constant: NSStatusBar.system.thickness / 2 + 5.5),
                badge.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: 5.5),
            ])
        }
        return badge
    }()

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
        add("Diagnostics…", #selector(openDiagnostics), to: menu)
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

    @objc private func openDiagnostics() {
        model.showDiagnostics()
        panel.show()
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

- [x] **Step 7: Build and run the tests**

Run: `swift build 2>&1 | grep -E "error|Build complete"`

Expected: one line, `Build complete!` with a time after it.

Run: `bash scripts/test.sh 2>&1 | grep -E "error:|Test run with"`

Expected: one line, `Test run with 50 tests in 0 suites passed`.

- [x] **Step 8: Mark the older plans' copies as expected differences**

The two older plans print the five files this task replaced, and `scripts/release.sh` refuses to release while `scripts/sync-plans.py` finds a copy that differs. Those copies stay as their plans built them, the way the v1 copies did when the control panel plan replaced them.

In `scripts/sync-plans.py`, replace this:

```python
# Meant to differ: Package.swift in Task 1 is an earlier stage, the rest are kept as the v1 versions.
EXPECTED = {
    "2026-11-24-agares-v1.md::" + block
    for block in (
        "Package.swift#1",
        "Sources/Agares/KeyTap.swift#1",
        "Sources/Agares/StatusMenu.swift#1",
        "Sources/Agares/main.swift#1",
        "Resources/Info.plist#1",
    )
}
```

with this:

```python
# Meant to differ: Package.swift in the v1 plan's Task 1 is an earlier stage, and the rest are files
# a later plan replaced, kept as the plan that printed them built them.
EXPECTED = {
    f"{plan}::{path}#1"
    for plan, kept in (
        ("2026-11-24-agares-v1.md", (
            "Package.swift",
            "Sources/Agares/KeyTap.swift",
            "Sources/Agares/StatusMenu.swift",
            "Sources/Agares/Typist.swift",
            "Sources/Agares/main.swift",
            "Resources/Info.plist",
        )),
        ("2026-11-25-control-panel.md", (
            "Sources/Agares/AppModel.swift",
            "Sources/Agares/KeyTap.swift",
            "Sources/Agares/StatusMenu.swift",
            "Sources/Agares/UpdateCheck.swift",
        )),
    )
    for path in kept
}
```

Run: `python3 scripts/sync-plans.py; echo "exit $?"`

Expected: ten lines that each start with `EXPECTED`, no line that starts with `DIFFERS`, then `exit 0`:

```text
EXPECTED  2026-11-24-agares-v1.md::Package.swift#1 (1 changed lines)
EXPECTED  2026-11-24-agares-v1.md::Sources/Agares/Typist.swift#1 (6 changed lines)
EXPECTED  2026-11-24-agares-v1.md::Sources/Agares/KeyTap.swift#1 (142 changed lines)
EXPECTED  2026-11-24-agares-v1.md::Sources/Agares/StatusMenu.swift#1 (159 changed lines)
EXPECTED  2026-11-24-agares-v1.md::Sources/Agares/main.swift#1 (2 changed lines)
EXPECTED  2026-11-24-agares-v1.md::Resources/Info.plist#1 (36 changed lines)
EXPECTED  2026-11-25-control-panel.md::Sources/Agares/AppModel.swift#1 (29 changed lines)
EXPECTED  2026-11-25-control-panel.md::Sources/Agares/KeyTap.swift#1 (33 changed lines)
EXPECTED  2026-11-25-control-panel.md::Sources/Agares/UpdateCheck.swift#1 (15 changed lines)
EXPECTED  2026-11-25-control-panel.md::Sources/Agares/StatusMenu.swift#1 (6 changed lines)
```

A `DIFFERS` line that names this plan means a file was not written exactly as printed here. Fix the file, not the plan.

- [x] **Step 9: Update the README**

Three edits to `README.md`.

In the "Small and local" paragraph, replace `About 1,300 lines of Swift` with `About 1,700 lines of Swift`. The sources come to 1,677 lines with this plan.

After the last bullet under "If something looks off" (`- **Letters doubled or garbled:** …`), add a blank line and this section:

```markdown
### Reporting a problem

Click the menu bar item, choose **Copy Diagnostics**, and paste the text into an [issue](https://github.com/quyennguyenvu/agares/issues). It holds three things:

- **What went wrong since Agares started:** the key hook switched off by macOS, the permission withdrawn, an update check that failed, and the like.
- **Your settings:** the hotkey and the checkboxes.
- **What is true right now:** the keyboard input source, whether macOS Secure Input is on, other typing tools that are running, and the last app you were in.

It never holds a key, a letter or a word you typed. It does name apps: the last one in front, one holding Secure Input, other typing tools, and any app whose own typing Agares left alone. Nothing is sent anywhere. The report leaves your Mac only when you paste it.
```

Under "Developing", directly before the paragraph that starts `Builds are signed with the self-signed "Agares Dev" certificate`, add:

````markdown
Every diagnostics line also goes to the macOS unified log, so the history outlives a crash or a restart of the app:

```sh
/usr/bin/log show --predicate 'subsystem == "com.quyennguyenvu.agares"' --last 1d --style compact
```
````

Run: `npx --yes markdownlint-cli2 "docs/**/*.md" README.md 2>&1 | tail -1`

Expected: `Summary: 0 issues in 0 files`.

- [x] **Step 10: Install and read the first lines back**

Run: `bash scripts/bundle.sh install`

Expected: output ends with `build/Agares.app: satisfies its Designated Requirement`, and the menu bar item shows `V` or `E` again within a few seconds (no new Accessibility prompt, since the signer is unchanged).

Then read the unified log. `/usr/bin/log` is spelled out because zsh has a `log` builtin of its own.

Run: `sleep 5; /usr/bin/log show --predicate 'subsystem == "com.quyennguyenvu.agares" AND process == "Agares"' --last 2m --style compact | tail -4`

Expected: among the last lines, `[app] started 0.1.0` followed by `[perm] accessibility granted`, each after `[com.quyennguyenvu.agares:diagnostics]`. The version is whatever `Resources/Info.plist` holds.

- [ ] **Step 11: Commit checkpoint**

Ask the user to run `/grimoire:seal`. Suggested message: `feat(app): record diagnostics and add a Copy Diagnostics command`.

---

### Task 3: Hand checklist

**Files:**

- Modify: only what a failing check requires.

**Interfaces:**

- Consumes: `/Applications/Agares.app` from Task 2, running with Accessibility granted.
- Produces: each line of the spec's section 3 that can be provoked by hand, seen in a real report.

This task needs the user at the keyboard. After each step, choose Copy Diagnostics from the menu bar item and paste into any text editor to read the report. For each failure, write down what was done and what the report showed, then find the cause with superpowers:systematic-debugging before changing code.

- [x] **Step 1: The report** — choose Copy Diagnostics and paste. Expected: three header lines (`Agares …`, `Settings: …`, `Now: …`), a blank line, then lines that start with a date and time, the first being `[app] started` and `[perm] accessibility granted`. The `Settings:` line matches the panel. With the menu opened from another app, `last app` names that app.
- [x] **Step 2: Other typing tools** — read `other typing tools` on the `Now:` line. Expected: `none`. OpenKey's login helper, `com.tuyenmai.OpenKeyHelper`, showed up here while planning on 2026-11-27 and was removed the same day.
- [x] **Step 3: Permission** — run `open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"`, which opens the list of apps allowed to control the Mac. By hand it is System Settings, Privacy & Security in the sidebar, then the Accessibility row inside that pane. The Accessibility item in the sidebar itself, which is also what searching for "accessibility" opens first, is a different pane (VoiceOver, Zoom) and has no such list. Switch Agares off in the list, wait for the small yellow warning sign at the lower right of the letter in the menu bar, and switch it on again. Expected: `[perm] accessibility withdrawn`, then `[perm] accessibility granted`, and while it is off the `Now:` line reads `accessibility missing · tap not started`.
- [x] **Step 4: Secure Input** — click into a password field (the lock screen does not count; a web login form does), stay for five seconds, and click out. Expected: `[tap] secure input on`, then `[tap] secure input off`. Copying while still in the field shows `secure input ON (held by …)` naming the browser.
- [x] **Step 5: Keys from another app** — run `osascript -e 'tell application "System Events" to keystroke "a"'` twice in Terminal. macOS may first ask to let Terminal control System Events. Expected: one `[tap] passing keys from …` line, not two.
- [x] **Step 6: Spotlight** — with Vietnamese on, open Spotlight and type `tieengs`, close it, then type `tieengs` in a text editor. Expected: `[typist] spotlight mode on`, then `[typist] spotlight mode off`, and `tiếng` in both places. Run on 2026-11-27: it failed at first, with `tieếếng` or `tiêếng` depending on typing speed and no line at all, and passed after the change to `Typist` described under Amendments.
- [x] **Step 7: A failed update check** — turn Wi-Fi off, choose Check for Updates…, dismiss the alert, turn Wi-Fi back on. Expected: `[update] check failed: NSURLErrorDomain -1009`.
- [x] **Step 8: A hook switched off** — run `kill -STOP "$(pgrep -x Agares)"`, press a few letter keys in a text editor, then run `kill -CONT "$(pgrep -x Agares)"`. Typing freezes for about a second while Agares is stopped; that is the test. Expected: `[tap] found disabled, re-enabled`, and typing converts again without restarting Agares. Run on 2026-11-27: that line appeared and `[tap] disabled by timeout` did not, so macOS switched the hook off without sending the event that says so. The first version of this step expected the timeout line.
- [x] **Step 9: Sleep** — put the Mac to sleep and wake it. Expected: `[app] woke from sleep`, and typing still converts.
- [x] **Step 10: History across launches** — choose Quit Agares, open it again, and run the `log show` command from the README. Expected: the lines of the steps above from the earlier launch, then a second `[app] started`. A fresh Copy Diagnostics holds only the new launch.
- [x] **Step 11: Nothing typed is recorded** — type a sentence in Vietnamese, copy the report, and search it for any word of the sentence. Expected: none of them is there.

Not provoked by hand: `[tap] slow callback`, `[tap] disabled by user input`, `[perm] granted, but macOS refused the tap`, `[perm] reset failed` and `[login] launch at login failed`. Each is one `Diagnostics.note` call behind a condition that needs a fault to be true.

- [x] **Step 12: Mark the spec as implemented**

In `docs/superpowers/specs/2026-11-27-diagnostics-design.md`, change the status in the second line to `Implemented` with the date, and correct risk 6 with what Step 8 showed.

- [ ] **Step 13: Commit checkpoint**

Ask the user to run `/grimoire:seal`. Suggested message: `docs: mark the diagnostics spec as implemented`.

---

### Task 4: The page in the panel

Added on 2026-11-27, after Tasks 1 to 3 had run. It builds section 4.1 of the spec: the log is read on a page of the panel, and the menu bar's Copy Diagnostics item becomes Diagnostics…, which opens that page.

**Files:**

- Modify: `Tests/AgaresEngineTests/DiagnosticLogTests.swift`, `Sources/AgaresEngine/DiagnosticLog.swift`, `Sources/Agares/Diagnostics.swift`, `Sources/Agares/AppModel.swift`, `Sources/Agares/Panel.swift`, `Sources/Agares/StatusMenu.swift`, `scripts/sync-plans.py`, `README.md`

**Interfaces:**

- Consumes: Tasks 1 and 2 as built, with the Amendments folded in.
- Produces: `DiagnosticLog.Parts` (`date`, `time`, `tag`, `text`, all `String`, and `stamp(today: String) -> String`) and `DiagnosticLog.parts(of: String) -> Parts?`. On `Diagnostics`: `static var onNote: () -> Void`, `struct Page: Equatable` and `static func page(tap: String) -> Page`. On `AppModel`: `diagnostics: Diagnostics.Page?` (published, read-only outside), `showDiagnostics()` and `hideDiagnostics()`.

Each change is a patch against the file as it stood before this task. Save a patch to a file and run `git apply <file>` from the repo root, or make the same edits by hand.

**Verified while planning (2026-11-27):** with these patches a scratch copy of the repo built and passed 53 tests, and the page was rendered to an image from that copy, with lines from today and with lines from an earlier day. The page has not been clicked or typed into.

- [x] **Step 1: Write the failing tests**

Patch `Tests/AgaresEngineTests/DiagnosticLogTests.swift`:

```diff
--- a/Tests/AgaresEngineTests/DiagnosticLogTests.swift
+++ b/Tests/AgaresEngineTests/DiagnosticLogTests.swift
@@ -40,3 +40,19 @@
 @Test func cleanClipsAtEightyCharacters() {
     #expect(DiagnosticLog.clean(String(repeating: "a", count: 200)) == String(repeating: "a", count: 80))
 }
+
+@Test func takesAStoredLineApart() throws {
+    let parts = try #require(DiagnosticLog.parts(of: "2026-11-27 13:26:15  [tap] passing keys from org.keepassxc.keepassxc"))
+    #expect(parts == DiagnosticLog.Parts(date: "2026-11-27", time: "13:26:15", tag: "tap", text: "passing keys from org.keepassxc.keepassxc"))
+}
+
+@Test(arguments: ["", "[tap] no stamp", "2026-11-27 13:26:15", "2026-11-27 13:26:15  no tag here", "2026-11-27 13:26:15  [tap]"])
+func refusesALineOfAnotherShape(line: String) {
+    #expect(DiagnosticLog.parts(of: line) == nil)
+}
+
+@Test func stampsTodayWithTheTimeAndOlderLinesWithTheDay() throws {
+    let parts = try #require(DiagnosticLog.parts(of: "2026-11-26 09:05:59  [app] started 0.2.0"))
+    #expect(parts.stamp(today: "2026-11-26") == "09:05:59")
+    #expect(parts.stamp(today: "2026-11-27") == "11-26 09:05")
+}
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/test.sh 2>&1 | grep -E "error:|Test run with"`

Expected: the build fails, with lines containing `error: type 'DiagnosticLog' has no member 'parts'`.

- [x] **Step 3: Take a stored line apart**

Patch `Sources/AgaresEngine/DiagnosticLog.swift`:

```diff
--- a/Sources/AgaresEngine/DiagnosticLog.swift
+++ b/Sources/AgaresEngine/DiagnosticLog.swift
@@ -18,6 +18,35 @@
         (header + [""] + lines).joined(separator: "\n")
     }
 
+    /// A stored line taken apart for display.
+    public struct Parts: Equatable {
+        public let date: String
+        public let time: String
+        public let tag: String
+        public let text: String
+
+        public init(date: String, time: String, tag: String, text: String) {
+            self.date = date
+            self.time = time
+            self.tag = tag
+            self.text = text
+        }
+
+        /// The time for a line written today; the day and the time to the minute for an older one.
+        public func stamp(today: String) -> String {
+            date == today ? time : "\(date.dropFirst(5)) \(time.prefix(5))"
+        }
+    }
+
+    /// Splits "2026-11-27 13:26:15  [tap] secure input on" into its parts. Nil for any other shape.
+    public static func parts(of line: String) -> Parts? {
+        let pieces = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
+        guard pieces.count == 4, pieces[2].hasPrefix("["), pieces[2].hasSuffix("]") else { return nil }
+        return Parts(
+            date: String(pieces[0]), time: String(pieces[1]),
+            tag: String(pieces[2].dropFirst().dropLast()), text: String(pieces[3]))
+    }
+
     /// For text Agares did not write, such as another app's bundle id: a line break in it would
     /// forge a line in a report that is meant to be sent. Keeps ASCII letters and digits, ".", "-"
     /// and "_", up to 80 characters.
```

The two spaces between the time and the tag are why the split leaves out empty pieces.

- [x] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/test.sh 2>&1 | grep -E "error:|Test run with"`

Expected: one line, `Test run with 53 tests in 0 suites passed`.

- [x] **Step 5: Give the page its content**

Patch `Sources/Agares/Diagnostics.swift`:

```diff
--- a/Sources/Agares/Diagnostics.swift
+++ b/Sources/Agares/Diagnostics.swift
@@ -24,12 +24,34 @@
     private static var secureInput = false
     private static var passed: Set<String> = []
 
+    /// Called after each line is written, so an open diagnostics page can show it.
+    static var onNote: () -> Void = {}
+
     static func note(_ line: String) {
         log.note("\(clock.string(from: Date()))  \(line)")
         // Notice is the lowest level macOS keeps on disk. Public, or the line reads back as <private>.
         system.notice("\(line, privacy: .public)")
+        onNote()
     }
 
+    /// What the panel's diagnostics page shows: the state of this moment, and the lines newest first.
+    struct Page: Equatable {
+        let tap: String
+        let secureInput: String
+        let inputSource: String
+        let otherTools: String
+        let lastApp: String
+        /// As the lines are stamped, to tell a line written today from an older one.
+        let today: String
+        let lines: [String]
+    }
+
+    static func page(tap: String) -> Page {
+        Page(
+            tap: tap, secureInput: secureInputNow(), inputSource: inputSource(), otherTools: otherTypingTools(),
+            lastApp: lastApp, today: String(clock.string(from: Date()).prefix(10)), lines: log.lines.reversed())
+    }
+
     /// Notes the launch, and starts watching for wake and for the app in front.
     static func start() {
         launched = Date()
```

Patch `Sources/Agares/AppModel.swift`:

```diff
--- a/Sources/Agares/AppModel.swift
+++ b/Sources/Agares/AppModel.swift
@@ -53,6 +53,9 @@
         didSet { stateChanged() }
     }
 
+    /// What the diagnostics page shows while it is open; nil while the settings show.
+    @Published private(set) var diagnostics: Diagnostics.Page?
+
     /// Flipped once when the panel appears, to start the seal's breathing animation.
     @Published var breathing = false
     @Published var tryText = ""
@@ -85,6 +88,11 @@
         keyTap.ignoresOtherApps = ignoresOtherApps
         keyTap.hotkey = hotkey
         keyTap.onHotkey = { [weak self] in self?.toggle() }
+        Diagnostics.onNote = { [weak self] in
+            guard self?.diagnostics != nil else { return }
+            // Later, not now: the line may have been written inside the key hook, which must not wait.
+            DispatchQueue.main.async { self?.refreshDiagnostics() }
+        }
     }
 
     /// Asks for Accessibility once, then starts the key hook as soon as it is granted.
@@ -98,9 +106,29 @@
         checkPermission()
         keyTap.revive()
         Diagnostics.tick()
+        refreshDiagnostics()
         checkForUpdatesIfDue()
     }
 
+    func showDiagnostics() {
+        diagnostics = Diagnostics.page(tap: tapState)
+    }
+
+    func hideDiagnostics() {
+        diagnostics = nil
+    }
+
+    /// Keeps an open page current. Called when a line is written and on every tick.
+    private func refreshDiagnostics() {
+        guard diagnostics != nil else { return }
+        let page = Diagnostics.page(tap: tapState)
+        if page != diagnostics { diagnostics = page }
+    }
+
+    private var tapState: String {
+        !trusted ? "not started" : keyTap.isEnabled ? "enabled" : "DISABLED"
+    }
+
     /// Puts the diagnostics report on the clipboard.
     func copyDiagnostics() {
         func word(_ on: Bool) -> String { on ? "on" : "off" }
@@ -109,8 +137,7 @@
             "leave other apps' keys \(word(ignoresOtherApps))", "sound \(word(soundOn))",
             "launch at login \(word(launchAtLogin))",
         ].joined(separator: " · ")
-        let tap = !trusted ? "not started" : keyTap.isEnabled ? "enabled" : "DISABLED"
-        let report = Diagnostics.report(settings: settings, accessibility: AXIsProcessTrusted(), tap: tap)
+        let report = Diagnostics.report(settings: settings, accessibility: AXIsProcessTrusted(), tap: tapState)
         NSPasteboard.general.clearContents()
         NSPasteboard.general.setString(report, forType: .string)
     }
```

Two rules these patches keep:

- A line can be written inside the key hook, and reading the page's state asks macOS for its running apps. So `onNote` only schedules the refresh for the next turn of the run loop.
- While the page is closed, `diagnostics` is nil, nothing is read and nothing is published. A refresh that finds nothing changed does not publish either.

- [x] **Step 6: Draw the page**

Patch `Sources/Agares/Panel.swift`:

```diff
--- a/Sources/Agares/Panel.swift
+++ b/Sources/Agares/Panel.swift
@@ -36,6 +36,8 @@
 
     func windowWillClose(_ notification: Notification) {
         NSApp.setActivationPolicy(.accessory)
+        // The panel opens on its settings next time, and an unseen page stops being refreshed.
+        model.hideDiagnostics()
     }
 
     // A recording left running would capture the next shortcut pressed in another app.
@@ -66,6 +68,25 @@
     @ObservedObject var model: AppModel
 
     var body: some View {
+        // The settings stay in place under the diagnostics page and keep setting the window's size,
+        // so the window does not jump when the page opens or closes.
+        settings
+            .opacity(model.diagnostics == nil ? 1 : 0)
+            .disabled(model.diagnostics != nil)
+            .accessibilityHidden(model.diagnostics != nil)
+            .overlay {
+                if let page = model.diagnostics {
+                    DiagnosticsPage(page: page, back: model.hideDiagnostics, copy: model.copyDiagnostics)
+                }
+            }
+            .padding(EdgeInsets(top: 40, leading: 28, bottom: 24, trailing: 28))
+            .frame(width: 420)
+            .background(Palette.bg0)
+            .foregroundColor(Palette.text1)
+            .tint(Palette.accent)
+    }
+
+    private var settings: some View {
         VStack(spacing: 22) {
             Seal(model: model)
             tryField
@@ -82,11 +103,12 @@
             .frame(maxWidth: .infinity, alignment: .leading)
             footer
         }
-        .padding(EdgeInsets(top: 40, leading: 28, bottom: 24, trailing: 28))
-        .frame(width: 420)
-        .background(Palette.bg0)
-        .foregroundColor(Palette.text1)
-        .tint(Palette.accent)
+        // In the corner beside the seal: the footer's rows are full while Accessibility is missing.
+        .overlay(alignment: .topTrailing) {
+            Button("Diagnostics ›", action: model.showDiagnostics)
+                .buttonStyle(.link)
+                .font(.system(size: 12))
+        }
     }
 
     private var tryField: some View {
@@ -171,11 +193,81 @@
                 } else {
                     Spacer()
                     Button("Check for Updates…", action: model.checkForUpdates)
+                }
+            }
+        }
+        .font(.system(size: 12))
+    }
+}
+
+/// What Agares noticed going wrong, and what is true right now. Laid over the settings.
+private struct DiagnosticsPage: View {
+    let page: Diagnostics.Page
+    let back: () -> Void
+    let copy: () -> Void
+
+    var body: some View {
+        VStack(alignment: .leading, spacing: 14) {
+            HStack(spacing: 12) {
+                Button("‹ Back", action: back)
+                Text("DIAGNOSTICS")
+                    .font(.system(size: 11, weight: .semibold))
+                    .foregroundColor(Palette.text2)
+                Spacer()
+                Button("Copy", action: copy)
+                    .help("Copies these lines, with the settings and the state above, as text.")
+            }
+            VStack(alignment: .leading, spacing: 7) {
+                // Amber marks what would explain typing that does not convert.
+                fact("Key hook", page.tap, fine: page.tap == "enabled")
+                fact("Secure Input", page.secureInput, fine: page.secureInput == "off")
+                fact("Input source", page.inputSource, fine: ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].contains(page.inputSource))
+                fact("Other typing tools", page.otherTools, fine: page.otherTools == "none")
+                fact("Last app", page.lastApp, fine: nil)
+            }
+            .frame(maxWidth: .infinity, alignment: .leading)
+            .padding(12)
+            .background(Palette.bg1)
+            .cornerRadius(10)
+            ScrollView {
+                LazyVStack(alignment: .leading, spacing: 7) {
+                    ForEach(page.lines.indices, id: \.self) { index in
+                        line(page.lines[index])
+                    }
                 }
+                .frame(maxWidth: .infinity, alignment: .leading)
             }
         }
         .font(.system(size: 12))
     }
+
+    /// Wide enough for the day as well only when a line from an earlier day is on show.
+    private var stampWidth: CGFloat {
+        page.lines.allSatisfy { $0.hasPrefix(page.today) } ? 60 : 82
+    }
+
+    private func fact(_ name: String, _ value: String, fine: Bool?) -> some View {
+        HStack(alignment: .firstTextBaseline, spacing: 8) {
+            Circle()
+                .fill(fine.map { $0 ? Palette.ok : Palette.warn } ?? Color.clear)
+                .frame(width: 7, height: 7)
+            Text(name).foregroundColor(Palette.text2)
+            Text(value).textSelection(.enabled)
+        }
+    }
+
+    private func line(_ stored: String) -> some View {
+        let parts = DiagnosticLog.parts(of: stored)
+        return HStack(alignment: .firstTextBaseline, spacing: 10) {
+            Text(parts?.stamp(today: page.today) ?? "")
+                .foregroundColor(Palette.text2)
+                .frame(width: stampWidth, alignment: .leading)
+            (Text(parts.map { "[\($0.tag)] " } ?? "").foregroundColor(Palette.text2) + Text(parts?.text ?? stored))
+                .textSelection(.enabled)
+                .fixedSize(horizontal: false, vertical: true)
+        }
+        .font(.system(size: 11, design: .monospaced))
+    }
 }
 
 /// The app's seal. It glows and breathes while Vietnamese is on; clicking it switches.
```

Three things here are easy to get wrong:

- The page is an overlay on the settings, not a sibling beside them in a stack. An overlay takes the size of what it covers; a sibling holding a scroll view would stretch the window to the height of 200 lines.
- The hidden settings are also switched off, so a click or the Tab key cannot reach a control that is not shown.
- The link sits in the top corner. In the footer it left no room for the Grant Accessibility… button while the permission is missing.

- [x] **Step 7: Open the page from the menu bar**

Patch `Sources/Agares/StatusMenu.swift`:

```diff
--- a/Sources/Agares/StatusMenu.swift
+++ b/Sources/Agares/StatusMenu.swift
@@ -77,7 +77,7 @@
         menu.addItem(.separator())
         add("Open Agares…", #selector(openPanel), to: menu)
         add("Check for Updates…", #selector(checkForUpdates), to: menu)
-        add("Copy Diagnostics", #selector(copyDiagnostics), to: menu)
+        add("Diagnostics…", #selector(openDiagnostics), to: menu)
         menu.addItem(.separator())
         add("Quit Agares", #selector(quit), to: menu)
     }
@@ -101,8 +101,9 @@
         model.checkForUpdates()
     }
 
-    @objc private func copyDiagnostics() {
-        model.copyDiagnostics()
+    @objc private func openDiagnostics() {
+        model.showDiagnostics()
+        panel.show()
     }
 
     @objc private func openReleasePage() {
```

- [x] **Step 8: Build and run the tests**

Run: `swift build 2>&1 | grep -E "error|Build complete"`

Expected: one line, `Build complete!` with a time after it.

Run: `bash scripts/test.sh 2>&1 | grep -E "error:|Test run with"`

Expected: one line, `Test run with 53 tests in 0 suites passed`.

- [x] **Step 9: Bring the plans back in step**

The control panel plan prints `Sources/Agares/Panel.swift`, which this task changed. In `scripts/sync-plans.py`, add that file to the control panel plan's list in `EXPECTED`, after `"Sources/Agares/KeyTap.swift",`:

```python
            "Sources/Agares/Panel.swift",
```

This plan prints five of the files as Tasks 1 and 2 wrote them. Rewrite those copies from the repo:

```bash
python3 scripts/sync-plans.py --apply \
  "2026-11-27-diagnostics.md::Tests/AgaresEngineTests/DiagnosticLogTests.swift#1" \
  "2026-11-27-diagnostics.md::Sources/AgaresEngine/DiagnosticLog.swift#1" \
  "2026-11-27-diagnostics.md::Sources/Agares/Diagnostics.swift#1" \
  "2026-11-27-diagnostics.md::Sources/Agares/AppModel.swift#1" \
  "2026-11-27-diagnostics.md::Sources/Agares/StatusMenu.swift#1"
```

Expected: five lines that start with `REWRITTEN`.

Run: `python3 scripts/sync-plans.py; echo "exit $?"`

Expected: eleven lines that each start with `EXPECTED`, none that starts with `DIFFERS`, then `exit 0`.

- [x] **Step 10: Update the README**

In the "Small and local" paragraph, replace `About 1,700 lines of Swift` with `About 1,900 lines of Swift`. The sources come to 1,885 lines with this task.

Under "Reporting a problem", replace the sentence that starts `Click the menu bar item, choose **Copy Diagnostics**` with:

```markdown
Click the menu bar item and choose **Diagnostics…**. The panel shows what Agares noticed going wrong and what is true right now. To send it to someone, press **Copy** and paste the text into an [issue](https://github.com/quyennguyenvu/agares/issues). It holds three things:
```

Three more places named the old menu item, found while running this step. In `Sources/Agares/Diagnostics.swift`, the comment on `report` now reads `The text the page's Copy button puts on the clipboard.`, and that file's copy in this plan was rewritten once more with `--apply`. Section 4 of the diagnostics spec says the same of the page's Copy button. The menu list in section 3.4 of the first design gained a `Diagnostics…` line.

Run: `npx --yes markdownlint-cli2 "docs/**/*.md" README.md 2>&1 | tail -1`

Expected: `Summary: 0 issues in 0 files`.

- [x] **Step 11: Install and confirm the app is live**

Run: `bash scripts/bundle.sh install`

Expected: output ends with `build/Agares.app: satisfies its Designated Requirement`, and the menu bar item shows `V` or `E` again within a few seconds.

Run: `sleep 5; /usr/bin/log show --predicate 'subsystem == "com.quyennguyenvu.agares" AND process == "Agares"' --last 1m --style compact | tail -2`

Expected: `[app] started` followed by `[perm] accessibility granted`.

- [ ] **Step 12: Hand checks**

These need the user at the keyboard.

1. Choose Diagnostics… from the menu bar item. Expected: the panel opens on the page, with five state rows (four with a green dot when all is well) and the lines newest first.
2. Press Back, then the Diagnostics link in the panel's top right corner. Expected: the settings, then the page again, and the window keeps its size and place both times.
3. With the page open, run `osascript -e 'tell application "System Events" to keystroke "a"'` from a Terminal that has not done so since Agares started, or put the Mac to sleep and wake it. Expected: the new line appears at the top of the list without reopening the page.
4. With the page open, type a few letters, then press Back. Expected: the try-it field is as it was before.
5. Press Copy and paste into a text editor. Expected: the report of the spec's section 4.
6. Close the panel and choose Open Agares…. Expected: the settings, not the page.
7. Switch Agares off in the Accessibility list and open the panel. Expected: both footer buttons show their whole label, and the page's Key hook row reads `not started` with an amber dot.

- [ ] **Step 13: Commit checkpoint**

In the spec, change the status line to say the page is built. Then ask the user to run `/grimoire:seal`. Suggested message: `feat(app): show diagnostics on a page of the panel`.
