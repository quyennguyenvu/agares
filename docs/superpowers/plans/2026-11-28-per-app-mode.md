# Agares Per-App Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an option that remembers Vietnamese or English for each app and brings that mode back when the app comes to the front.

**Architecture:** All of it lives in `AppModel`: a saved dictionary from bundle id to mode, the bundle id of the app in front kept by the app-switch notification, one block in `toggle()` that saves, and one handler that restores by setting `vietnameseOn` directly. `Panel` gains one checkbox. The key hook, the menu bar item and the engine do not change. Spec: `docs/superpowers/specs/2026-11-28-per-app-mode-design.md`.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, AppKit, SwiftUI, `UserDefaults`. No third-party dependencies.

**Verified while planning (2026-11-28):** both patches below were applied to a scratch copy of the repo: `swift build` ended with `Build complete!` and `bash scripts/test.sh` with 59 tests passed. `git apply --check` accepted both patches against the repo. The edits to `scripts/sync-plans.py`, the README and the three older specs were made in the same scratch copy, where the sync check listed twelve `EXPECTED` lines and markdownlint found 0 issues. The app itself has not been run with this code.

## Global Constraints

- Minimum macOS 13. Bundle id `com.quyennguyenvu.agares`. Signing certificate name `Agares Dev`.
- No third-party dependencies, and no new network request.
- Nothing that runs inside the key hook may wait on the system (v1 spec, 5.1). `toggle()` runs inside the hook when the hotkey is pressed: it may change a variable and hand work to a queue, and it must not ask macOS which app is in front or write a file itself.
- A restore sets `vietnameseOn` directly and never calls `toggle()`. That is what keeps it silent and keeps it from saving.
- The option is off by default. Its label is `Remember Vietnamese or English for each app`. Its tooltip is `When you come back to an app, Agares switches to the mode you last used there. These switches play no sound.`
- The `UserDefaults` keys are `remembersPerApp` (Bool) and `appModes` (a dictionary from bundle id to Bool, true for Vietnamese).
- No unit tests are added: the logic is two `if` statements around a dictionary, in the app target, which has no test target (spec, section 8). The existing 59 tests must still pass.
- Never run `git commit`. Each task ends with a commit checkpoint: stop and ask the user to run `/grimoire:seal`, offering the suggested message. On an auto run, leave the checkpoints unticked, carry on, and ask for one `/grimoire:seal` at the end.
- Run `swift build`, `bash scripts/test.sh` and `bash scripts/bundle.sh` one at a time, from the main session only, never inside parallel subagents. This Mac has 16 GB of RAM.
- The test command is `bash scripts/test.sh`.
- Never delete, skip or weaken a test to make a change pass.
- Comments explain why, in one line. No comments that restate the code.
- Any Markdown you touch must pass `npx --yes markdownlint-cli2 "docs/**/*.md" README.md`. Prose is never hard-wrapped.
- Each patch is against the file as it stood on 2026-11-28, with the `KeyAction` change in the working tree. Save a patch to a file and run `git apply <file>` from the repo root, or make the same edits by hand.

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/Agares/AppModel.swift` | Patched. The option, the saved modes, the app in front, the save in `toggle()`, the restore on an app switch, and the option's state in the report's settings line |
| `Sources/Agares/Panel.swift` | Patched. The checkbox and its tooltip |
| `scripts/sync-plans.py` | The diagnostics plan's copy of `AppModel.swift` becomes an expected difference |
| `README.md` | The option under "Using it" |
| `docs/superpowers/specs/2026-11-23-agares-design.md` | An Amendments row, and the out-of-scope line |
| `docs/superpowers/specs/2026-11-25-control-panel-design.md` | Storage keys, the sound rule, the panel sketch, the checkbox list, and the out-of-scope line |
| `docs/superpowers/specs/2026-11-27-diagnostics-design.md` | The report's settings line |
| `docs/superpowers/specs/2026-11-28-per-app-mode-design.md` | Its status line and risk 1, once the hand checks have run |

---

### Task 1: The option and its two rules

**Files:**

- Modify: `Sources/Agares/AppModel.swift`, `Sources/Agares/Panel.swift`, `scripts/sync-plans.py`, `README.md`, `docs/superpowers/specs/2026-11-23-agares-design.md`, `docs/superpowers/specs/2026-11-25-control-panel-design.md`, `docs/superpowers/specs/2026-11-27-diagnostics-design.md`

**Interfaces:**

- Consumes: `AppModel` as it stands: `vietnameseOn: Bool` (its `didSet` tells the key hook, redraws the menu bar item and saves), `toggle()` (the one function the hotkey, the menu bar item and the seal all call), `save(_ value: Any, as key: String)` (writes on the background save queue) and `copyDiagnostics()`.
- Produces: on `AppModel`, `remembersPerApp: Bool` (published, saved as `remembersPerApp`), and three private members: `appModes: [String: Bool]` (saved as `appModes`), `frontApp: String?` and `appCameToFront(_ app: String?)`.

- [x] **Step 1: Add the option and the two rules to the model**

Patch `Sources/Agares/AppModel.swift`:

```diff
--- a/Sources/Agares/AppModel.swift
+++ b/Sources/Agares/AppModel.swift
@@ -33,6 +33,11 @@
         }
     }
 
+    /// Brings back the mode each app was last left in whenever that app comes to the front.
+    @Published var remembersPerApp: Bool {
+        didSet { save(remembersPerApp, as: "remembersPerApp") }
+    }
+
     @Published var hotkey: Hotkey {
         didSet {
             keyTap.hotkey = hotkey
@@ -73,6 +78,10 @@
     private var pendingSound: DispatchWorkItem?
     /// Accessibility is granted but macOS will not start the hook. Kept so it is noted once, not every tick.
     private var tapRefused = false
+    /// The mode each app was last left in, by bundle id. Only the user's own toggles fill it.
+    private var appModes = UserDefaults.standard.dictionary(forKey: "appModes") as? [String: Bool] ?? [:]
+    /// Kept by the app-switch notification, so a toggle inside the key hook never asks macOS for it.
+    private var frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
 
     init() {
         let defaults = UserDefaults.standard
@@ -81,6 +90,7 @@
         soundOn = defaults.bool(forKey: "soundOn")
         allowsZFWJ = defaults.bool(forKey: "allowsZFWJ")
         ignoresOtherApps = defaults.bool(forKey: "ignoresOtherApps")
+        remembersPerApp = defaults.bool(forKey: "remembersPerApp")
         hotkey = Self.storedHotkey(in: defaults)
 
         keyTap.vietnameseOn = vietnameseOn
@@ -93,6 +103,12 @@
             // Later, not now: the line may have been written inside the key hook, which must not wait.
             DispatchQueue.main.async { self?.refreshDiagnostics() }
         }
+        NSWorkspace.shared.notificationCenter.addObserver(
+            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
+        ) { [weak self] notification in
+            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
+            self?.appCameToFront(app?.bundleIdentifier)
+        }
     }
 
     /// Asks for Accessibility once, then starts the key hook as soon as it is granted.
@@ -135,7 +151,7 @@
         let settings = [
             "Vietnamese \(word(vietnameseOn))", "hotkey \(hotkey.name)", "z, w, j, f \(word(allowsZFWJ))",
             "leave other apps' keys \(word(ignoresOtherApps))", "sound \(word(soundOn))",
-            "launch at login \(word(launchAtLogin))",
+            "launch at login \(word(launchAtLogin))", "remember per app \(word(remembersPerApp))",
         ].joined(separator: " · ")
         let report = Diagnostics.report(settings: settings, accessibility: AXIsProcessTrusted(), tap: tapState)
         NSPasteboard.general.clearContents()
@@ -174,8 +190,19 @@
         saveQueue.async { UserDefaults.standard.set(value, forKey: key) }
     }
 
+    /// Not a toggle: it plays no sound and saves nothing for the app.
+    private func appCameToFront(_ app: String?) {
+        frontApp = app
+        guard remembersPerApp, let app, let mode = appModes[app], mode != vietnameseOn else { return }
+        vietnameseOn = mode
+    }
+
     func toggle() {
         vietnameseOn.toggle()
+        if remembersPerApp, let frontApp {
+            appModes[frontApp] = vietnameseOn
+            save(appModes, as: "appModes")
+        }
         // A sound still waiting behind a slow start is dropped, so the wait cannot end in a burst of them.
         pendingSound?.cancel()
         guard soundOn else { return }
```

What each part is for:

- `remembersPerApp` is the checkbox. Setting it saves the flag and nothing else, so ticking the box changes no mode.
- `appModes` is read once from `UserDefaults`. A stored value that is not a dictionary of Bools fails the cast and is read as empty.
- `frontApp` is read from macOS once, when the model is created, and after that kept by the notification, whether or not the option is on. `toggle()` can then save without asking macOS anything inside the key hook.
- `appCameToFront` is rule 2 of the spec. It sets `vietnameseOn` directly: no sound, and nothing saved for the app.
- The block in `toggle()` is rule 1 of the spec. An app with no bundle id leaves `frontApp` nil, and nothing is saved for it.

- [x] **Step 2: Add the checkbox to the panel**

Patch `Sources/Agares/Panel.swift`:

```diff
--- a/Sources/Agares/Panel.swift
+++ b/Sources/Agares/Panel.swift
@@ -100,6 +100,8 @@
                     .help("Words such as zô and jì can then take marks. So can English words that start with these letters.")
                 Toggle("Leave text typed by other apps alone", isOn: $model.ignoresOtherApps)
                     .help("A password manager's auto-type or a text expander sends keys of its own. Agares then passes them through unconverted. Turn this off if you type with an on-screen keyboard.")
+                Toggle("Remember Vietnamese or English for each app", isOn: $model.remembersPerApp)
+                    .help("When you come back to an app, Agares switches to the mode you last used there. These switches play no sound.")
                 Toggle("Play a sound when toggling", isOn: $model.soundOn)
                 Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
             }
```

The panel takes its height from its content, so the window grows by one row and needs no other change.

- [x] **Step 3: Build and run the tests**

Run: `swift build 2>&1 | grep -E "error|Build complete"`

Expected: one line, `Build complete!` with a time after it.

Run: `bash scripts/test.sh 2>&1 | grep -E "error:|Test run with"`

Expected: one line, `Test run with 59 tests in 0 suites passed`. The count does not change, because this task adds no tests.

- [x] **Step 4: Bring the plans back in step**

The diagnostics plan prints `Sources/Agares/AppModel.swift`, which this task changed, and `scripts/release.sh` refuses to release while `scripts/sync-plans.py` finds a copy that differs. That copy stays as its plan built it, the way the control panel plan's copies did when the diagnostics plan changed them.

Run: `python3 scripts/sync-plans.py | grep -v EXPECTED`

Expected: one line, `DIFFERS   2026-11-27-diagnostics.md::Sources/Agares/AppModel.swift#1 (29 changed lines)`.

In `scripts/sync-plans.py`, the control panel plan's entry in `EXPECTED` ends with these two lines:

```python
            "Sources/Agares/UpdateCheck.swift",
        )),
```

Add this entry directly after them:

```python
        ("2026-11-27-diagnostics.md", (
            "Sources/Agares/AppModel.swift",
        )),
```

Run: `python3 scripts/sync-plans.py; echo "exit $?"`

Expected: twelve lines that each start with `EXPECTED`, none that starts with `DIFFERS`, then `exit 0`.

- [x] **Step 5: Update the README**

Under "Using it", add this bullet directly above the one that starts `- **Open the panel**`:

```markdown
- **Let each app keep its own mode** by ticking **Remember Vietnamese or English for each app** in the panel. Coming back to an app then brings back the mode you last used there, without a sound. Agares never guesses: inside one app you still switch with the hotkey, and an app you have never switched in keeps whatever mode is on. It is off by default.
```

In the `- **Open the panel**` bullet, replace `two typing options, the sound switch, Launch at login` with `two typing options, the per-app and sound switches, Launch at login`.

The "About 1,900 lines of Swift" in "Why Agares" stays: the sources come to 1,942 lines with this task.

- [x] **Step 6: Update the three older specs**

In `docs/superpowers/specs/2026-11-23-agares-design.md`:

Add this row at the end of the Amendments table, after the row that starts `| Spotlight |`:

```markdown
| Per-app mode | An option remembers Vietnamese or English for each app and brings it back when the app comes to the front | `2026-11-28-per-app-mode-design.md` |
```

In section 9, replace the line `- Remembering Vietnamese or English per app` with:

```markdown
- Remembering Vietnamese or English per app (added on 2026-11-28 as an option that is off by default; see the per-app spec)
```

In `docs/superpowers/specs/2026-11-25-control-panel-design.md`:

In section 3.5, replace `` `ignoresOtherApps` and `nextUpdateCheck` (section 7). `` with:

```markdown
`ignoresOtherApps`, `nextUpdateCheck` (section 7), and `remembersPerApp` and `appModes` (per-app spec, section 5).
```

In section 4, add this sentence to the end of the first paragraph, after `however the toggle was made.`:

```markdown
A mode brought back on an app switch is not a toggle and plays no sound (per-app spec, section 3).
```

In the sketch of section 5, add these two lines directly under the line `│  ☑ Leave text typed by other apps alone  │`:

```text
│  ☐ Remember Vietnamese or English for    │
│    each app                              │
```

In the **Checkboxes** bullet of section 5, replace `(on by default; v1 spec, 3.2), sound, and launch at login` with:

```markdown
(on by default; v1 spec, 3.2), remember Vietnamese or English for each app (off by default; per-app spec), sound, and launch at login
```

In section 10, replace the line `- Per-app settings` with:

```markdown
- Per-app settings, other than the mode remembered for each app (added on 2026-11-28; see the per-app spec)
```

In `docs/superpowers/specs/2026-11-27-diagnostics-design.md`, section 4, add a space and `· remember per app off` to the end of the report's `Settings:` line, so that it ends:

```text
· sound on · launch at login on · remember per app off
```

- [x] **Step 7: Lint the Markdown**

Run: `npx --yes markdownlint-cli2 "docs/**/*.md" README.md 2>&1 | tail -1`

Expected: `Summary: 0 issues in 0 files`.

- [x] **Step 8: Install and confirm the app is live**

Run: `bash scripts/bundle.sh install`

Expected: output ends with `build/Agares.app: satisfies its Designated Requirement`, and the menu bar item shows `V` or `E` again within a few seconds.

Run: `sleep 5; /usr/bin/log show --predicate 'subsystem == "com.quyennguyenvu.agares" AND process == "Agares"' --last 1m --style compact | tail -2`

Expected: `[app] started` followed by `[perm] accessibility granted`.

- [ ] **Step 9: Commit checkpoint**

Ask the user to run `/grimoire:seal`. Suggested message: `feat(app): remember Vietnamese or English for each app`.

---

### Task 2: Hand checklist

**Files:**

- Modify: `docs/superpowers/specs/2026-11-28-per-app-mode-design.md` (the status line and risk 1), and only what a failing check requires.

**Interfaces:**

- Consumes: `/Applications/Agares.app` from Task 1, running with Accessibility granted.
- Produces: each row of the spec's section 8, seen in the real app.

This task needs the user at the keyboard. Before starting, open TextEdit with an empty document and Notes with an empty note, and tick **Play a sound when toggling** in the panel. The steps build on each other, so run them in order. "The letter" is the `V` or `E` in the menu bar. For each failure, write down what was done and what the letter showed, then find the cause with superpowers:systematic-debugging before changing code.

To run the checklist a second time from a clean state, choose Quit Agares, run `defaults delete com.quyennguyenvu.agares appModes`, and open Agares again.

- [x] **Step 1: The checkbox** — open the panel. Expected: **Remember Vietnamese or English for each app** is there, unticked, directly above **Play a sound when toggling**. Resting the pointer on it shows the tooltip. The window is one row taller and the footer is whole.
- [x] **Step 2: Off is as before** — leave the box unticked. In TextEdit press the hotkey once, then press ⌘Tab to Notes. Expected: the letter does not change on the switch.
- [x] **Step 3: Two apps, two modes** — tick the box and close the panel. In TextEdit press the hotkey once or twice so that the letter ends on `E`. In Notes press it once or twice so that the letter ends on `V`. Press ⌘Tab between the two four times, then type `tieengs` in each. Expected: `E` every time TextEdit comes to the front and `V` every time Notes does, with no sound on any switch; `tieengs` in TextEdit and `tiếng` in Notes.
- [x] **Step 4: A toggle still sounds** — in Notes press the hotkey twice. Expected: the pop, then the tick, and the letter ends on `V`.
- [x] **Step 5: An app with no saved mode** — from Notes press ⌘Tab to Calculator, then to TextEdit, then to Calculator again. Expected: `V` on the first arrival at Calculator and `E` on the second. The letter never changes on arriving there.
- [x] **Step 6: The menu bar item saves for the app in front** — with TextEdit in front, click the menu bar item and choose Vietnamese; the letter becomes `V`. Switch to Notes, press the hotkey once so the letter becomes `E`, and switch back to TextEdit. Expected: `V`. If it shows `E`, the menu made Agares the front app and the toggle was saved for Agares: stop here, because that is risk 1 of the spec and the design needs a decision from the user before any code changes.
- [x] **Step 7: The panel is an app too** — with TextEdit in front, choose Open Agares… from the menu bar item, click the seal once so the letter becomes `E`, then click TextEdit's window. Expected: the letter returns to `V`.
- [x] **Step 8: Spotlight** — with TextEdit in front, open Spotlight, type `tieengs`, and press Esc. Do the same with Notes in front. Expected: `tiếng` over TextEdit and `tieengs` over Notes.
- [x] **Step 9: After a relaunch** — choose Quit Agares, open Agares again, then press ⌘Tab to TextEdit and to Notes. Expected: `V` in TextEdit and `E` in Notes. Then run `defaults read com.quyennguyenvu.agares appModes`. Expected: a dictionary holding `com.apple.TextEdit` with 1, `com.apple.Notes` with 0 and `com.quyennguyenvu.agares` with 0, and no entry for Calculator.
- [x] **Step 10: Unticking** — open the panel, untick the box, close the panel, and press ⌘Tab between TextEdit and Notes. Expected: the letter does not change on any switch. Tick the box again, close the panel, and switch to TextEdit and to Notes. Expected: `V` and `E` again.
- [x] **Step 11: The report** — choose Diagnostics… from the menu bar item, press Copy, and paste into TextEdit. Expected: the `Settings:` line ends with `· remember per app on`. The report holds no list of remembered apps; `last app` on the `Now:` line is there as before.
- [ ] **Step 12: A day later** — after a day of ordinary use with the box ticked, choose Diagnostics…. Expected: no line of the form `[tap] slow callback: … ms (hotkey)`.

- [x] **Step 13: Mark the spec as implemented**

In `docs/superpowers/specs/2026-11-28-per-app-mode-design.md`, change the status in the second line from `Designed 2026-11-28, not yet implemented` to `Implemented` with the date Task 1 ran, followed by the date the hand checklist was run and which steps, if any, are still to run. Rewrite risk 1 with what Step 6 showed.

Run: `npx --yes markdownlint-cli2 "docs/**/*.md" README.md 2>&1 | tail -1`

Expected: `Summary: 0 issues in 0 files`.

- [ ] **Step 14: Commit checkpoint**

Ask the user to run `/grimoire:seal`. Suggested message: `docs: mark the per-app spec as implemented`.
