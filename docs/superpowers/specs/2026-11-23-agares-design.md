# Agares — Vietnamese Telex Input for macOS: Design Spec

**Date:** 2026-11-23 **Status:** Implemented 2026-11-24; amended 2026-11-25 (see Amendments) **Author:** quyennv + Claude

## Amendments

This spec describes v1 as designed on 2026-11-23. Later decisions changed parts of it. The text below is updated in place wherever a statement would otherwise be wrong, and each such place names the document that decided the change.

| Area | What changed | Decided in |
| --- | --- | --- |
| Hotkey | Configurable, with ⌃⇧Space as the default instead of a fixed Ctrl+Shift; the detection no longer fires on larger chords | `2026-11-25-control-panel-design.md`, section 3 |
| Settings | A control panel and a toggle sound; Launch at login moved into the panel | same, sections 4 and 5 |
| Dock and quitting | A Dock icon while the panel is open; only the menu bar item quits | same, section 6 |
| Network | One request for the latest release, made at most once a day and on demand | same, section 7 |
| Distribution | Releases for other Macs, signed with the same certificate as local builds | section 7.1 of this document |
| Spotlight | On macOS 27 the search bar is a panel of the Siri AI app, and the check accepts it too | section 5 of this document, 2026-11-27 |
| Per-app mode | An option remembers Vietnamese or English for each app and brings it back when the app comes to the front | `2026-11-28-per-app-mode-design.md` |

## 1. Summary

Agares is a personal menu-bar tool for macOS that types Vietnamese with Telex in any app, with no underlined composing text. Every keystroke lands in the focused field as real text immediately, so search boxes and live filters react per keystroke, the way they do with OpenKey and GoTiengViet. It is named after the duke in the Ars Goetia who "teaches all languages or tongues".

**Priorities:** types naturally, never blocks typing, small enough to read in one sitting.

## 2. Decisions & alternatives considered

| Decision | Chosen | Rejected alternatives |
| --- | --- | --- |
| Text entry technique | **Event tap + delete-and-retype.** A system-wide key hook sees each key before the focused app; when a mark is needed, Agares deletes the old characters and types the new ones. | Official macOS input method (InputMethodKit): needs no permission but shows underlined composing text, which is the thing this tool exists to avoid. Built-in macOS Telex: zero code, same underline. |
| Language | **Swift**, one language, no dependencies. | Rust: not installed, every macOS call goes through binding crates, worth it only for a Windows or Linux port. C++: OpenKey's choice for a three-platform engine, here it only adds Objective-C++ glue. C and Go: the app layer still needs Objective-C glue. |
| Build | **SwiftPM plus a script that assembles the `.app`.** This Mac has Command Line Tools only. | Xcode project: a multi-gigabyte install for no gain at this size. |
| Signing | **Self-signed certificate "Agares Dev"** in the login keychain. | Ad-hoc signing, as Goetia uses: the signature changes on every build, so macOS would drop the Accessibility grant on every rebuild. Apple Developer ID with notarization: the official route, but it needs the paid Apple Developer Program; it would remove the first-launch warning on downloaded copies and is the planned upgrade (section 7.1). |
| Typing method | **Telex only, precomposed Unicode output.** | VNI, legacy encodings (TCVN3, VNI-Windows). |
| Tone style | **Traditional** (hòa, thủy). | Modern (hoà, thuỷ), or an option for both. |
| Settings | **None beyond the menu, and a fixed hotkey,** for v1. Replaced on 2026-11-25 by a control panel and a configurable hotkey (control-panel spec). | A settings window: rejected for v1, built in the control-panel work. |
| Code reuse | **Fresh implementation.** | Copying OpenKey's engine: it is GPL-3.0, which would put Agares under the same licence. Techniques learned from reading it (section 5) are reimplemented. |

## 3. Architecture

One process, a menu bar app (`LSUIElement`) that shows a Dock icon only while its panel is open, with no telemetry. Its only network request is the update check, made at most once a day and when the user asks for it. Bundle id `com.quyennguyenvu.agares`, minimum macOS 13.

### 3.1 Engine

Pure logic with no OS imports. It tracks only the word under the cursor.

```swift
struct Edit: Equatable {
    let backspaces: Int
    let text: String
}

struct Engine {
    init(allowsZFWJ: Bool = false)                 // the option of 4.8
    mutating func type(_ key: Character) -> Edit?  // nil: let the key through unchanged
    mutating func backspace() -> Edit?             // nil: let Backspace through unchanged
    mutating func reset()                          // the word has ended
}
```

State: the letters of the current word (base letter, mark, case), one tone for the whole word, and the mark keys already undone in this word.

After each call the engine renders the word and compares it with the previous rendering. If the only change is the typed key appended at the end (or, for Backspace, the last character removed), it returns `nil` and the real key event reaches the app untouched. Otherwise it returns the `Edit` that turns the old rendering into the new one: delete back to the first character that differs, then type the rest.

### 3.2 KeyTap

A session-level `CGEventTap` listening for key-down, modifier-change and mouse-down events. For each key-down:

1. Events Agares posted itself, recognised by a tag on the event, pass through untouched.
2. A key that another app typed passes through untouched and ends the tracked word. It is neither converted nor taken for the hotkey. A key pressed on the keyboard has no sending process (`eventSourceUnixProcessID` is 0), while a key typed by an app carries that app's process id, so the test is one field read. This is what keeps a password manager's auto-type, or a text expander, from being converted. It is an option, on by default (control-panel spec, section 5), because an on-screen keyboard types this way too.
3. While the panel is recording a new hotkey, the key goes to the recorder instead (control-panel spec, 3.4).
4. If the key is the hotkey, it toggles Vietnamese and is swallowed. This comes before the next step, so the hotkey also works while Vietnamese is off.
5. If Vietnamese is off, or Cmd, Ctrl or Option is held, call `reset()` and pass the event through.
6. Backspace calls `backspace()`. A letter a–z or A–Z calls `type(_:)`; the letter is read from the event's Unicode string, so Shift and Caps Lock are already applied. Anything else calls `reset()` and passes through.
7. A `nil` result passes the event through. An `Edit` swallows the event and goes to Typist.

Mouse-down events and app-switch notifications call `reset()`. Modifier-change events drive a modifiers-only hotkey (control-panel spec, 3.1 and 3.2); those sent by another app are ignored in the same way as its keys. Steps 2 to 4 were added after v1, which had a fixed Ctrl+Shift hotkey.

KeyTap assumes the active macOS input source is a plain Latin layout (ABC or US).

### 3.3 Typist

Turns an `Edit` into synthetic key events, posted through the tap so they keep their place in the key stream. The sequence depends on the focused app (section 5).

### 3.4 StatusMenu

An `NSStatusItem` showing `V` or `E`, or a warning mark when permission is missing, followed by a dot when a newer release is known. The menu holds:

- Open Accessibility Settings… (only while permission is missing)
- Version 0.2.0 Available…, naming the newer release (only when one is known)
- Vietnamese (checkmark)
- Open Agares…
- Check for Updates…
- Diagnostics…, which opens the panel on its diagnostics page (see the diagnostics design)
- Quit Agares

Launch at login, backed by `SMAppService.mainApp`, lives in the panel. The hotkey is ⌃⇧Space by default and configurable. The settings and state that the menu and the panel share are held by `AppModel` and saved in `UserDefaults`. The control-panel spec has the details; v1 had a fixed Ctrl+Shift hotkey and kept Launch at login in this menu.

### 3.5 Data flow

```text
key press
   │
 KeyTap ── recording a new hotkey ──▶ recorder (a captured shortcut or Esc is swallowed)
   │    ── the hotkey ─────────────▶ toggle Vietnamese (key swallowed)
   │    ── Vietnamese off / shortcut held / not a letter ──▶ app (engine reset)
   │
 Engine.type("s")
   ├─ nil ────────────────────────────▶ original key event ─▶ app
   └─ Edit(backspaces: 1, text: "ế") ─▶ Typist ─▶ synthetic events ─▶ app
```

## 4. Telex rules

### 4.1 Letter marks

| Keys | Result | Notes |
| --- | --- | --- |
| `aa` `ee` `oo` | â ê ô | The second key may come anywhere later in the word, after other vowels or after the final consonant: `layas` gives lấy, `tiene` gives tiên. |
| `aw` | ă | |
| `ow` `uw` | ơ ư | |
| `uow` | ươ | With a letter after it: `muown` gives mươn. At the end of the word the `u` stays plain: `thuow` gives thuơ. |
| `uwo` + letter | ươ | `luwong` gives lương. |
| `w` with no vowel to mark | ư | `tw` gives tư, `nhw` gives như. |
| `dd` | đ | Only the first letter of the word; the second `d` may come later: `dod` gives đo. |

`w` picks its target in this order: `uo` becomes ươ or uơ, `ua` becomes ưa, `a` becomes ă, `o` becomes ơ, `u` becomes ư. It takes the first of these that makes one of the horn and breve groups of 4.5, so `aiw` stays `aiw` because ăi is not a group. In a word with no vowel yet it adds a new ư, if that leaves a valid syllable. Otherwise it is a plain letter.

A doubling vowel (`a`, `e`, `o`) marks an earlier vowel of the same letter, however many letters came in between, whenever that makes one of the circumflex groups of 4.5: `lay` plus `a` is lây, `lieu` plus `e` is liêu, `tuoi` plus `o` is tuôi. Otherwise it is a new vowel: `ngoeo` stays `ngoeo` because ôe is not a group, and `khoee` stays `khoee`. Until 2026-11-25 the key only worked right after its vowel or after the final consonant, which left `layas` and `ddayas` unconverted.

A vowel group holds one kind of mark: a circumflex, or the marks `w` makes (horn and breve), never both. A key that would add the other kind is a plain letter: `teew` gives têw.

A marked letter keeps the case of its base letter.

### 4.2 Tones

`s` sắc, `f` huyền, `r` hỏi, `x` ngã, `j` nặng, `z` removes the tone. A tone key applies when the word has a vowel and passes the validity check (4.5). A different tone key replaces the current tone: `asf` gives à. `z` with no tone to remove is a plain letter.

### 4.3 Tone placement

The position is recomputed after every change, so the tone moves as the word grows.

1. In `qu` and in `gi` followed by a vowel, the `u` or `i` belongs to the consonant and never carries the tone: quà, già. When `gi` has no other vowel, the `i` is the vowel: gì.
2. If a vowel has a mark (â ă ê ô ơ ư), the tone goes on it. With two marked vowels (ươ), it goes on the second: người, được.
3. Otherwise, with three vowels it goes on the middle one (ngoài, khuỷu). With two vowels it goes on the second if a consonant follows (hoàn, toán) and on the first if not (hòa, thủy, mái). With one vowel it goes on that vowel.

### 4.4 Undo

Repeating a mark key that already took effect removes the mark and types the key as a plain letter: `aaa` gives aa, `ass` gives as, `ddd` gives dd, `aww` gives aw, `ww` gives w. The repeat need not be next to the first press: `layaa` gives laya. That key then stays a plain letter for the rest of the word, unless the plain letter it left is deleted: Backspace makes the key a mark key again. After `ddieenfe` (điène, from an accidental extra `e`), Backspace and `e` give điền.

### 4.5 Validity check

A mark or tone applies only when the word, ignoring marks, has the shape *initial consonant (optional), vowel group, final consonant (optional)*, drawn from three fixed tables:

- **Initials:** b c ch d đ g gh gi h k kh kr l m n ng ngh nh p ph qu r s t th tr v x
- **Vowel groups (base letters):** a e i o u y, ai ao au ay eo eu ia ie iu oa oe oi oo ua ue ui uo uu uy ye, ieu oai oao oay oeo uay uoi uou uya uye uyu yeu
- **Finals:** c ch k m n ng nh p t

The initial kr and the final k are not in everyday Vietnamese. They are there for highland place names: Krông, Đắk Lắk.

A mark is added only when the vowel group then reads as one of the groups Vietnamese writes with that kind of mark:

- **Circumflex groups:** â ê ô, âu ây êu iê ôi uâ uê uô yê, iêu yêu uây uôi uyê
- **Horn and breve groups:** ă ơ ư, oă ơi uơ ưa ưi ưu ươ, ươi ươu

With the option of 4.8 switched on, z, f, w and j are initials too.

Syllables ending in c, ch, k, p or t accept only sắc and nặng.

The check runs when a mark key is pressed. Nothing already typed is ever restored, so a word that becomes invalid later keeps its marks (see section 9).

### 4.6 Word tracking

- Letters a–z and A–Z extend the word.
- Backspace removes the last letter. Because the tone position is recomputed, this can itself produce an `Edit` (hoàn becomes hòa). Deleting the vowel that carries the tone deletes the tone with it (việ becomes vi).
- Everything else ends the word: space, digits, punctuation, Enter, Tab, Escape, arrow keys, any key with Cmd, Ctrl or Option, a mouse click, an app switch, turning Vietnamese off.
- A finished word is never re-entered. Moving the cursor back into an old word and typing there starts a new word.

### 4.7 Examples

These rows are the seed of the engine's test table.

| Typed | Result | Shows |
| --- | --- | --- |
| `tieengs` | tiếng | Tone after the final consonant |
| `tieesng` | tiếng | Tone before the final consonant |
| `vieejt` | việt | |
| `dduowngf` | đường | đ and ươ |
| `nguowif` | người | ươ before i, tone on ơ |
| `thuowr` | thuở | uơ at the end of the word |
| `luwong` | lương | ưo completed to ươ |
| `muaw` | mưa | `w` on ua |
| `hoawcj` | hoặc | `w` on oa |
| `ruowuj` | rượu | |
| `tw` | tư | Bare `w` |
| `hoaf` | hòa | First of two vowels |
| `hoafn` | hoàn | Tone moves when a consonant follows |
| `thuyr` | thủy | Traditional style |
| `khuyur` | khuỷu | Middle of three vowels |
| `ngoaif` | ngoài | |
| `quaf` | quà | `qu` |
| `quys` | quý | |
| `gif` | gì | `gi` with no other vowel |
| `giuwax` | giữa | `gi` before a vowel |
| `asf` | à | Tone replaced |
| `asz` | a | Tone removed |
| `aaa` | aa | Undo |
| `ass` | as | |
| `ddd` | dd | |
| `ww` | w | |
| `DDaij` | Đại | Case |
| `VIEEJT` | VIỆT | |
| `css` | css | No vowel |
| `class` | class | `cl` is not a Vietnamese initial |
| `catf` | catf | A word ending in t takes only sắc or nặng |
| `data` | dât | Standard Telex behaviour, no auto-restore in v1 |
| `test` | tét | Same |

### 4.8 z, f, w and j as consonants (option)

Added on 2026-11-25, off by default, and set with a checkbox in the panel. When it is on:

- z, f, w and j count as initial consonants in the validity check, so `zaayj` gives zậy, `fair` gives fải and `jif` gives jì. With it off those words stay as typed.
- A `w` typed as the first letter of a word is the consonant w, not ư: `was` gives wá, where with the option off it gives ứa. After another consonant `w` is still ư: `tw` gives tư either way.
- What these keys do after a vowel does not change: f and j are tones, z removes the tone, w marks.

It is an option because English words that start with these letters then pick up marks too.

## 5. Replacing text in the focused app

Given `Edit(backspaces: n, text: s)`, Typist sends one of three sequences.

| Situation | Sequence | Why |
| --- | --- | --- |
| Default, n > 0 | Type U+202F (an invisible character), press Backspace n + 1 times, type s | In a field with inline autocomplete, such as a browser address bar, a bare Backspace deletes the highlighted suggestion instead of a letter. Typing a character first replaces the suggestion, so the backspaces then hit real text. |
| Spotlight is open, n > 0 | Press Shift+Left n times, type s | The invisible-character trick misbehaves in Spotlight. Selecting the old characters and typing over them works there. |
| n = 0 | Type s | Nothing to delete. |

Spotlight counts as open when the front app's bundle id is `com.apple.Spotlight` or a window owned by Spotlight is on screen. On macOS 27 neither ever holds: the Siri AI app shows the search bar and no process called Spotlight runs. There it counts as open when a window owned by "Siri" is on screen above the level of ordinary windows; with the bar open the front app does not change (measured on 2026-11-27: `Siri@23 640x467`). The check is needed only when an `Edit` with n > 0 is about to be sent, and its answer is cached (5.1).

Text is sent as precomposed Unicode (NFC) through the key event's Unicode string.

This mirrors OpenKey's default behaviour, learned from reading its source and reimplemented. OpenKey's optional Chromium variant (Shift+Left selection in Chrome-family browsers, off by default there) is not in v1.

### 5.1 Speed

Typing must never wait on Agares. Measured on this Mac on 2026-11-25, in an optimised build:

| Step | Time |
| --- | --- |
| Engine, per key | about 2 µs |
| Spotlight check, asking macOS for its on-screen windows | 1.1 to 1.4 ms |
| Spotlight check, cached answer | under 0.1 µs |
| Toggle, when the sound was started on the main thread and the audio output was asleep | up to 3,959 ms |
| Toggle, with the sound and the settings write moved to background queues | about 10 µs, about 100 µs with the sound on |
| Telling a key from another app from one from the keyboard | one field read per key |

Until 2026-11-25 the window query ran for every edit that deletes text, which made it nearly all of the time Agares added to a converting keystroke. The answer is now kept, and dropped only when Spotlight could have opened or closed: a key pressed with Command, Control or Option; any key that is not a letter, Space or Backspace; a mouse click; an app switch; and in any case after two seconds, to cover ways of opening Spotlight that the key hook never sees.

The toggle sound was the second such cost, found the same day (control-panel spec, section 4): starting a sound waits for the audio output, for seconds if it is a sleeping Bluetooth device. With that gone, the largest remaining piece of the toggle was writing the setting (about 80 µs), which now happens on a background queue as well, and the menu bar letter is changed at the moment the state changes instead of on the next turn of the run loop.

The rule for future changes: nothing that runs inside the key hook may wait on the system. A question that costs more than a few microseconds is cached and invalidated by events, and anything that can block (audio, files, the network) is started on another thread.

## 6. Permissions and failure handling

| Condition | Behaviour |
| --- | --- |
| Accessibility not granted at launch | macOS is asked to show its prompt once. The menu bar shows the warning mark and the Open Accessibility Settings… item, and the panel opens with Grant Accessibility… and Reset Permission buttons (control-panel spec, section 5). Agares re-checks every 2 seconds and starts the tap when granted, with no relaunch. |
| Grant withdrawn while running | The tap is stopped at the next 2-second check and the warning state returns. |
| macOS disables the tap (timeout or user input) | Re-enabled immediately on the tap-disabled event. The word being tracked is dropped, because keys typed while the tap was off never reached the engine. |
| Tap cannot be created | Back to the warning state above; the next 2-second check tries again. |
| Password fields (secure input) | macOS withholds keys from taps. Agares does nothing and typing is unmodified. |
| Any doubt inside the tap callback | The original event is returned. A typed key is swallowed only when a complete `Edit` is ready to send. The only other keys swallowed are the hotkey itself and, while a hotkey is being recorded, the captured shortcut or Esc. |

## 7. Build, signing and install

```text
agares/
  Package.swift
  Sources/AgaresEngine/      pure logic, no imports: Engine, Hotkey, Version
  Sources/Agares/            KeyTap, Typist, AppModel, StatusMenu, Panel, UpdateCheck, main
  Tests/AgaresEngineTests/
  Resources/                 Info.plist, icon.svg
  scripts/test.sh            runs the tests
  scripts/make-cert.sh       one-time creation of the signing certificate
  scripts/bundle.sh          release build → build/Agares.app → codesign; install or dmg
  scripts/release.sh         test, bump the version, tag, push
  scripts/sync-plans.py      keeps the source printed in the plans equal to the real files
  .github/                   release workflow and the header of the release notes
```

- **Signing certificate:** created once, self-signed, named "Agares Dev", stored in the login keychain. The first signing shows a keychain prompt; choose Always Allow. Goetia needs no certificate because ad-hoc signing is enough for notifications; Agares needs one because the Accessibility grant is tied to the signer.
- **Install:** `scripts/bundle.sh install` copies `build/Agares.app` to `/Applications` and relaunches it.
- **Icon:** an ember ring in Goetia's palette (`#FF9E2C` to `#E8590C` on graphite `#1A1F28`) around the letter â. One SVG, converted with `sips` and `iconutil`, both part of macOS.
- **Other Macs:** out of scope for v1; releases were added on 2026-11-25 (7.1).

### 7.1 Releases (added 2026-11-25)

`scripts/release.sh <version>` runs the tests, writes the version into `Resources/Info.plist`, commits, tags `v<version>` and pushes. The tag starts `.github/workflows/release.yml`, which re-runs the tests, builds a universal app (Apple silicon and Intel), packages `Agares-<version>.dmg`, attaches a build provenance attestation and `SHA256SUMS.txt`, and publishes the GitHub release with `.github/release-body.md` on top of the generated notes. The structure mirrors Goetia's.

| Decision | Chosen | Rejected alternatives |
| --- | --- | --- |
| Release signing | **The same self-signed "Agares Dev" certificate as local builds**, read from the repository secrets `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD`. The Accessibility permission then survives updates. | Ad hoc signing, as Goetia's releases use: every update would make users remove and re-grant the permission by hand. Developer ID with notarization: needs the paid Apple Developer Program; planned for later, at the cost of one re-grant for every user when the signer changes. |
| Wrong signer | **The workflow fails** when the secret is missing, and refuses a build whose signing requirement does not name the certificate's fingerprint. | Falling back to ad hoc signing: it would silently cost every user their permission. |
| Package | **A `.dmg`** holding the app and an Applications shortcut. | A `.zip`: nothing nudges the user to move the app into Applications. |
| Version tags | **`v` plus three plain numbers.** | Pre-release suffixes: the in-app update check refuses them. |
| Release tooling | **A script, as Goetia has.** | A Makefile. |

Downloaded copies still meet the Gatekeeper warning on first launch, as Goetia's do, because the certificate is not Apple's. The README's Install section walks through it.

## 8. Testing

**Engine:** table-driven tests with Swift Testing, run by `bash scripts/test.sh`. The same test target now also covers the hotkey rules and version comparison (control-panel spec, section 9). A key-order test types 119 words, at least one for every vowel group plus the `gi` and `qu` initials, in every order in which each mark or tone key comes after its letter: 862 orders, each in lower case, in capitals and capitalised. Every order must give the same word. The table starts from 4.7 and adds Backspace cases (hoàn then Backspace gives hòa; tiếng then Backspace four times gives t).

**KeyTap and Typist:** no automated tests in v1, since they need the Accessibility grant and a real text field. They are checked by hand:

| Where | Check |
| --- | --- |
| TextEdit | Every row of 4.7; Backspace in the middle of a word |
| Safari address bar, Chrome address bar | `vieejt` while a history suggestion is highlighted: no duplicated or eaten letters |
| Spotlight | `tieengs vieejt` |
| Finder search, VS Code search | Results update per keystroke |
| Terminal prompt | `tieengs` |
| Goetia chat box | `tieengs`, then Enter sends |
| A password field | Typing is untouched |
| Hotkey | ⌃⇧Space toggles; ⌃⇧⌘4 does not (control-panel spec, section 9) |

## 9. Out of scope for v1

- VNI and legacy encodings
- Macros (text shortcuts)
- Remembering Vietnamese or English per app (added on 2026-11-28 as an option that is off by default; see the per-app spec)
- Automatic restore of English words: with Vietnamese on, `test` becomes tét and `expect` becomes ẽpect. Toggle with the hotkey. This is the first candidate for a follow-up.
- Modern tone style, and any typing option other than the one in 4.8
- A settings window and a configurable hotkey (both added on 2026-11-25; see the control-panel spec)
- Auto-update. An update check (quiet once a day, and on demand) and releases for other Macs were added on 2026-11-25 (control-panel spec, section 7; section 7.1 here)
- OpenKey's Chromium Shift+Left variant
- Editing inside a finished word

## 10. Risks

1. **Autocomplete trick and Spotlight detection: verified by hand on 2026-11-25.** They come from OpenKey's source and had not been tried on macOS 27 or current browsers. The hand checklist (plan Task 7) passed in every app it lists, Safari, Chrome and Spotlight included. On 2026-11-27, on the same macOS 27.2.1, Spotlight was found failing because the detection never matched (section 5); why it passed two days earlier is not known.
2. **Self-signed signing: verified on 2026-11-24.** `codesign` accepts the certificate without any trust setting, and the Accessibility grant survived a build with a different code hash signed by it. Not yet tried: a downloaded release replacing an installed copy.
3. **The Swift package tooling on this Mac needs a one-time repair.** Four leftover Swift 5.10 interface files inside the Command Line Tools make every package manifest fail to link; the plan's first task removes them. With them out of the way, Swift Testing works without Xcode, through `scripts/test.sh`, which passes the test macro plugin path explicitly (the first test build after a clean otherwise leaves it out).
4. **Removing Agares from Accessibility while it runs can stall keyboard input** until it quits. Quit Agares first.
5. **Some apps handle synthetic key events badly** (certain remote-desktop and Java apps). Such apps get a per-app fix when found.
