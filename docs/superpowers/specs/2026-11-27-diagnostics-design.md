# Agares — Diagnostics: Design Spec

**Date:** 2026-11-27 **Status:** Implemented 2026-11-27, hand checklist run the same day. The page of section 4.1 was designed and built later that day; its hand checks are still to run **Author:** quyennv + Claude

## 1. Summary

Agares gains a diagnostics log: a short record of what went wrong since it started, and a Diagnostics page in the panel that shows it and copies it as text. Each line is also written to the macOS unified log, so the history survives a crash and can be read from Terminal.

The log exists for debugging. Every hard bug Agares has had (the key hook switched off by a slow sound start, the stale Accessibility grant, the hotkey that needed several presses) left no trace, and each would have been one line here.

The model is Goetia's Diagnostics pane, cut down to what a typing tool needs. Agares writes perhaps ten lines a day, so the page is a plain list: no filter, no tags to pick from, and no file of its own.

This spec extends `2026-11-25-control-panel-design.md`. It changes one behaviour outside logging: the two-second tick now re-enables a key hook it finds dead (section 7).

## 2. Decisions & alternatives considered

| Decision | Chosen | Rejected alternatives |
| --- | --- | --- |
| What earns a line | **Something going wrong, or a state changing.** Never a routine success, never anything per keystroke. | Logging every toggle, setting change and successful update check: they bury the lines that matter, and the current settings are in the report's header anyway. |
| What is never recorded | **No key, key code, character, word, per-keystroke count or window title, and no history of which apps were in front.** | An opt-in "record my keys for 30 seconds" trace: the most useful thing for a conversion bug, and a keylogger feature in a tool that already reads every keystroke. |
| Store | **A 200-line ring in memory, mirrored line by line to the unified log.** The mirror gives history across launches and crashes for free. | A JSON file flushed on quit, as Goetia has: a quit that was a crash or a force-quit loses it. The unified log alone, read back with `OSLogStore`: the app can only read its own current process, and reading is slow. |
| Where the log is shown | **On a page of the panel** that takes the place of the settings, with a Back button (user decision, 2026-11-27). The first version showed it nowhere and had only a Copy Diagnostics menu item; copying and pasting elsewhere to read the log proved slower than looking. | A section at the foot of the settings: open, it makes the window about 130 points taller, which is tight on a 13-inch screen. A submenu of the menu bar item: a dozen lines, no scrolling back, no state. A second window: the Dock icon follows the panel's window, and a second one complicates that. A filter and tag chips, as in Goetia: too much for ten lines a day. |
| How the page is reached | **Diagnostics… in the menu bar menu**, which replaces Copy Diagnostics, and a link in the panel's top corner. The report is read before it is copied. | Keeping both menu items. A link in the footer: with Accessibility missing the footer's row is full, and the link cut the Grant Accessibility… button short. |
| Where each line is written | **In place, on the main thread.** | Handing the unified-log write to a background queue, as the toggle sound is: measured slower (section 8). |
| A hook found dead | **Re-enabled on the tick, and noted.** | Only noting it: the user would have to restart Agares to type again. |
| Text that Agares did not write | **Cleaned before it enters a line.** A bundle id comes from another app's `Info.plist`, and a line break in it would forge a line in a report meant to be sent. | Trusting it. |

## 3. The lines

Each line is a tag in brackets and a short text.

| Line | Written when |
| --- | --- |
| `[app] started 0.2.0` | Once per launch. |
| `[app] woke from sleep` | The Mac wakes. |
| `[perm] accessibility granted` | The tick finds the grant and the hook starts. |
| `[perm] accessibility withdrawn` | The tick finds the grant gone. |
| `[perm] granted, but macOS refused the tap` | The grant is there and the hook will not start. Written once, not on every tick, until the hook starts or the grant goes. |
| `[perm] reset failed` | Reset Permission could not run `tccutil`, or it exited with an error. |
| `[tap] disabled by timeout` | macOS switched the hook off for answering too slowly. |
| `[tap] disabled by user input` | macOS switched the hook off for the other reason it reports. |
| `[tap] found disabled, re-enabled` | The tick found the hook off with no event having said so (section 7). |
| `[tap] slow callback: 412 ms (hotkey)` | One run of the hook took more than 50 ms. The word in brackets is what that run did: `hotkey` (it toggled), `record` (it finished recording a hotkey), `edit` (it sent a conversion) or `pass`. |
| `[tap] secure input on` / `off` | macOS Secure Input changed, checked on the tick. While it is on the hook receives no keys, so typing stops converting. |
| `[tap] passing keys from com.keepassxc.keepassxc` | A key typed by another app was left alone (the "Leave text typed by other apps alone" option). Written once per app per launch. An app without a bundle id is named by its process name. |
| `[typist] spotlight mode on` / `off` | The way text is replaced changed between the Spotlight method and the ordinary one. |
| `[update] check failed: NSURLErrorDomain -1009` | An update check, daily or asked for, got no version. The cause is the error's domain and code, `HTTP 403` for a refused request, or `no version in the response`. |
| `[login] launch at login failed: <domain> <code>` | Registering or unregistering the login item threw. |

A `[tap] disabled by timeout` with no `slow callback` line before it means the main thread was held up outside the hook.

## 4. The report

The page's Copy button puts this on the clipboard as plain text: three header lines taken at that moment, a blank line, then the ring, oldest line first, each stamped with the local date and time it was written.

```text
Agares 0.2.0 · macOS 27.2.1 · up 3h 12m
Settings: Vietnamese on · hotkey Control + Shift + Space · z, w, j, f off · leave other apps' keys on · sound on · launch at login on
Now: accessibility granted · tap enabled · secure input off · input source com.apple.keylayout.ABC · other typing tools none · last app com.google.Chrome

2026-11-27 09:14:02  [app] started 0.2.0
2026-11-27 09:14:02  [perm] accessibility granted
2026-11-27 11:40:31  [tap] passing keys from com.keepassxc.keepassxc
2026-11-27 14:03:22  [tap] slow callback: 412 ms (hotkey)
2026-11-27 14:03:22  [tap] disabled by timeout
```

The `Now:` line holds what a line in the ring cannot say, because it is only true at the moment of copying.

- **tap:** `enabled`, `DISABLED`, or `not started` while Accessibility is missing.
- **secure input:** `off`, or `ON (held by com.apple.Terminal)`. The holder comes from the window server's session dictionary (`kCGSSessionSecureInputPID`); without that key the line says only `ON`. A stuck Secure Input, left on by an app that never released it, is the usual cause of typing that stops everywhere.
- **input source:** the active macOS keyboard input source. With the built-in Vietnamese source active, text is converted twice.
- **other typing tools:** running apps whose bundle id contains `openkey`, `gotiengviet` or `evkey`, in any letter case; `none` otherwise. The same double conversion.
- **last app:** the app most recently in front, other than Agares. One value, not a history. It answers "which app was the text wrong in".

The page's Copy button puts it there. It replaces the clipboard and shows no confirmation. There is no Clear: the ring lasts only until Agares quits.

### 4.1 The page

The page is laid over the panel's settings. The settings stay in place underneath, hidden and switched off, and keep setting the window's size, so the window neither jumps nor resizes when the page opens or closes. It is reached from Diagnostics… in the menu bar menu, under Check for Updates…, and from a Diagnostics link in the panel's top right corner. Closing the panel puts it back on its settings.

```text
┌──────────────────────────────────────────┐
│ [‹ Back]  DIAGNOSTICS             [Copy] │
│ ┌──────────────────────────────────────┐ │
│ │ ● Key hook  enabled                  │ │
│ │ ● Secure Input  off                  │ │
│ │ ● Input source  com.apple.keylayout… │ │
│ │ ● Other typing tools  none           │ │
│ │   Last app  com.google.Chrome        │ │
│ └──────────────────────────────────────┘ │
│ 14:03:22  [tap] disabled by timeout      │
│ 14:03:22  [tap] slow callback: 412 ms    │
│           (hotkey)                       │
│ 11:40:31  [tap] passing keys from        │
│           com.keepassxc.keepassxc        │
│ 09:14:02  [perm] accessibility granted   │
│ 09:14:02  [app] started 0.2.0            │
└──────────────────────────────────────────┘
```

- **State:** the facts of the report's `Now:` line, one to a row. The dot is green when the fact is as it should be and amber when it would explain typing that does not convert: the hook disabled or not started, Secure Input on, an input source other than ABC or U.S., another typing tool running. The last app has no dot.
- **Lines:** every line in the ring, newest first, in a list that scrolls. The time stands in a column of its own, the tag is dimmed, a long line wraps, and the text can be selected. A line written today shows its time; one from an earlier day shows the day and the time to the minute, and the column widens to fit only when such a line is on show.
- **Live:** a line written while the page is open appears at once. The state is read again on the two-second tick. While the page is closed nothing is read and nothing is published.

A line may be written inside the key hook, so the page is refreshed on the next turn of the run loop, never in the hook: reading the state asks macOS for its running apps.

## 5. The store and the mirror

`DiagnosticLog`, in `AgaresEngine`, is the ring and the report text. It keeps the newest 200 lines and drops the oldest. Like the rest of the engine it imports nothing, so the existing tests cover it, and the app stamps each line with the time before handing it over.

`DiagnosticLog.clean` is applied to any text Agares did not write, which means bundle ids and process names. It keeps ASCII letters and digits, `.`, `-` and `_`, drops everything else, and clips the result to 80 characters. A name with nothing left is written as `unknown`.

`Diagnostics`, in the app, owns the one ring. `Diagnostics.note` stamps the line, appends it to the ring and writes the same line to the unified log: subsystem `com.quyennguyenvu.agares`, category `diagnostics`, level notice, marked public. Notice is the lowest level macOS keeps on disk, and without the public mark the line reads back as `<private>`.

To read the history from Terminal, across launches:

```sh
/usr/bin/log show --predicate 'subsystem == "com.quyennguyenvu.agares"' --last 1d --style compact
```

Every note is made on the main thread, so the ring needs no lock. The key hook runs on the main run loop, the tick is a main-thread timer, and the update check hops to the main thread before it calls back.

## 6. The rule that keeps it cheap

No line may be written once per keystroke. Every line in section 3 is tied to a change of state, or capped at once per app per launch. A line added later must meet the same rule.

The one thing added to every run of the hook is its timing: two clock reads and a comparison.

## 7. Reviving a dead hook

Seen on 2026-11-27, in the hand checklist: with Agares stopped by `kill -STOP` while keys were pressed, macOS switched the hook off, and after `kill -CONT` no event arrived to say so. The tick found the hook off and re-enabled it within two seconds. Without the tick's check, nothing would have converted until Agares was restarted.

Today the hook is re-enabled only when macOS delivers an event saying it was switched off. A hook can also end up off without that event, and then nothing converts until Agares is restarted.

The tick now asks whether the hook is enabled. If it is running and found off, the tick re-enables it, starts a fresh word (as the disabled events already do), and notes `[tap] found disabled, re-enabled`.

## 8. Cost

Measured on 2026-11-27 on this Mac (arm64, macOS 27.2.1) with a standalone benchmark, not inside the real hook.

| What | When | Cost |
| --- | --- | --- |
| Timing the hook | Every key, modifier and click | about 40 ns |
| Has this app's key been noted | Only keys typed by another app | 10 to 20 ns |
| Secure Input check | Every 2 seconds | 160 to 560 ns |
| Writing one line | Only on a change | about 10 µs at the median (5.7 µs for the ring, 4.4 µs for the unified log), about 90 µs at the 99th percentile, 1 ms worst of 500 |

The line cost was measured cold, with 2 ms of idle before each write, which is how a real line arrives. Handing the unified-log write to a background queue cost 11 µs at the median against 4.4 µs in place, so lines are written in place. For scale, the toggle costs about 10 µs, and the stall that made macOS switch the hook off was 3,959 ms.

The ring holds about 20 KB. macOS rotates the unified log itself.

## 9. Code layout

| File | Change |
| --- | --- |
| `Sources/AgaresEngine/DiagnosticLog.swift` | New: the ring, the report text, `clean`, and a stored line taken apart for the page |
| `Sources/Agares/Diagnostics.swift` | New: the one ring, the unified-log mirror, the `Now:` probes (Secure Input and its holder, input source, other typing tools, last app), the wake observer |
| `Sources/Agares/KeyTap.swift` | Notes the disabled events, slow callbacks and keys from other apps; says whether the hook is enabled and revives it for the tick |
| `Sources/Agares/Typist.swift` | Notes a change of Spotlight mode |
| `Sources/Agares/AppModel.swift` | Notes permission changes and the reset and login-item failures; the tick checks Secure Input and the hook; builds the `Settings:` line; `copyDiagnostics()`; holds the page's content while it is open, since SwiftUI's `@State` is not available (control-panel spec, section 2) |
| `Sources/Agares/Panel.swift` | The Diagnostics page, laid over the settings; the link in the top corner |
| `Sources/Agares/UpdateCheck.swift` | Keeps the response and the error it now discards, and notes a failed check with its cause |
| `Sources/Agares/StatusMenu.swift` | The Diagnostics… menu item; `[app] started` |
| `Tests/AgaresEngineTests/DiagnosticLogTests.swift` | New |
| `README.md` | A short "Reporting a problem" section: where the command is, what the report holds, and that it leaves the Mac only when pasted somewhere. The `log show` command under Developing, and the line count |
| `scripts/sync-plans.py` | The two older plans' copies of the five files replaced here become expected differences |

## 10. Testing

Unit tests for `DiagnosticLog`: the ring keeps the newest 200 and drops the oldest; the report puts the header first and the lines oldest first with their date and time; `clean` removes line breaks, control characters and anything outside its set, and clips at 80; a stored line is taken apart into date, time, tag and text, a line of another shape is refused, and the stamp shows the time for today and the day for an earlier date.

By hand, each expected line read on the Diagnostics page:

| Step | Expected |
| --- | --- |
| Launch | `[app] started`, `[perm] accessibility granted` |
| Switch Agares off under System Settings, Privacy & Security, Accessibility (the row inside that pane, not the Accessibility pane in the sidebar), then on | `withdrawn`, then `granted` |
| `kill -STOP` the app, press a few keys, `kill -CONT` | `[tap] found disabled, re-enabled` |
| Stay in a password field for more than 2 seconds, then leave | `secure input on`, then `off` |
| `osascript -e 'tell application "System Events" to keystroke "a"'` | `[tap] passing keys from …`, once however often it is run |
| Type a Vietnamese word in Spotlight, then in another app | `spotlight mode on`, then `off` |
| Check for Updates… with the network off | `[update] check failed: NSURLErrorDomain -1009` |
| The `log show` command in section 5 | The same lines, from this launch and earlier ones |
| Choose Diagnostics… from the menu bar item | The panel opens on the page, the same size as the settings; Back returns to them |
| With the page open, provoke any line above | It appears at the top of the list without reopening the page |
| With the page open, type a few letters | Nothing lands in the hidden try-it field |
| Press Copy, paste elsewhere | The report of section 4 |

A slow callback cannot be provoked by hand without a debugging hook; its only logic is the 50 ms comparison.

## 11. Out of scope

- A filter or tag chips on the page, and colours for how serious a line is
- A confirmation after Copy
- A file of Agares's own that keeps the ring across launches
- A Clear command
- Recording keys, even by choice and for a short time
- Lines for toggles, setting changes and successful update checks
- Sending the report anywhere

## 12. Risks

1. **The report covers the current launch only.** After a crash or a force-quit the earlier lines are in the unified log, and reading them needs Terminal.
2. **Secure Input lines can crowd the ring.** Someone who uses Terminal's Secure Keyboard Entry gets a pair of lines for each visit to Terminal that lasts past a tick, and 200 lines of those push older ones out.
3. **The report names apps.** A tool whose keys were left alone and the last app in front appear by bundle id. The user reads the text before sharing it, and the README says what it holds.
4. **`kCGSSessionSecureInputPID` is not a documented key.** On this Mac it was present on 2026-11-27 and named the responsible app (a command-line probe that turned Secure Input on was reported as VS Code, which had launched it). If the key goes away the header says only `ON`.
5. **The other-typing-tools match is only partly tested.** On this Mac it found `com.tuyenmai.OpenKeyHelper`, OpenKey's login helper, running on 2026-11-27 (removed the same day). GoTiengViet and EVKey are not installed here.
6. **`[tap] disabled by timeout` has not been seen yet.** Stopping the app with `kill -STOP` switched the hook off on 2026-11-27, but macOS sent no event for it, so the line written was `[tap] found disabled, re-enabled` (section 7).
