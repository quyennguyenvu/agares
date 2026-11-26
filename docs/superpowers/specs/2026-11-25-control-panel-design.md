# Agares — Control Panel, Configurable Hotkey and Updates: Design Spec

**Date:** 2026-11-25 **Status:** Implemented 2026-11-25, with same-day changes folded in (Dock icon, Reset Permission, seal focus, daily update check, the z-w-j-f option) **Author:** quyennv + Claude

## 1. Summary

Agares gains a control panel window, a hotkey the user can change, an optional sound on toggle, a Check for Updates command, and a Dock icon that shows while the panel is open. It also fixes a bug in v1: the Ctrl+Shift hotkey fired whenever a larger chord such as Ctrl+Shift+Cmd+4 was released through it.

This spec extends `2026-11-23-agares-design.md` and replaces three of its decisions:

| v1 decision | Now |
| --- | --- |
| Settings: none beyond the menu, hotkey fixed | A control panel; the hotkey is configurable |
| Menu-bar only (`LSUIElement`) | Menu bar, plus a Dock icon while the panel is open |
| No network access | One request to GitHub for the latest release, made at most once a day and when the user asks |

## 2. Decisions & alternatives considered

| Decision | Chosen | Rejected alternatives |
| --- | --- | --- |
| Hotkey bug | **Fix the detection:** a hold that has contained any other modifier, key or click cannot fire until every modifier is released. | Only changing the default: any modifiers-only hotkey had the same fault with some larger chord. |
| Default hotkey | **Ctrl+Shift+Space.** It fires on one exact key press, so no chord can trigger it by passing through. | Ctrl+Shift alone (the v1 default the user found colliding with screenshots). Ctrl+Space (macOS input-source switch, VS Code suggestions). Option+Z (VS Code word wrap). Ctrl+Option+Space (macOS next input source). Cmd+Shift+Space (VS Code parameter hints). |
| Hotkey shapes | **Modifiers alone (two or more), or modifiers plus one key.** | Side-specific single keys such as "tap right Command": a third shape for the model and the recorder. |
| Panel toolkit | **SwiftUI in an `NSWindow`**, with all state in one observable model object. | AppKit views by hand: about three times the code for a custom-styled panel. SwiftUI's `@State`: the macro plugin it needs does not ship with Command Line Tools. |
| Theme | **Dark only**, Goetia's dark tokens. | Light and dark, as Goetia has. |
| Update check | **Ask GitHub for the latest release, compare versions, offer to open the release page.** A quiet check at most once a day marks a waiting update with a dot on the menu bar item and a line in the menu and the panel; the Check for Updates command always answers with an alert. Same shape as Goetia's check. | Downloading and installing (needs Sparkle and distribution signing). No background check: the first design, changed the same day because the user judged one request a day cheap. A switch to turn the daily check off: not asked for. |
| Quitting | **Only the menu bar item's Quit.** Cmd+Q and the Dock's Quit close the panel. Logout, restart and shutdown still quit. | Blocking every quit: the app would hold up shutting the Mac down. |
| Panel at launch | **Shown only while Accessibility is missing.** | Shown on every launch: it would pop up at each login and each reinstall. |
| Dock icon | **Only while the panel is open.** The app stays `LSUIElement`, becomes a regular app when the panel is shown, and goes back when it closes. | A permanent Dock icon: built first, then changed the same day because the user wanted closing the panel to remove it. |
| Typing option | **One checkbox: Allow z, w, j, f as consonants,** off by default (v1 spec, 4.8). | Always on: English words that start with those letters would pick up marks. |
| Keys typed by other apps | **Passed through untouched, by an option that is on by default.** Auto-type from a password manager is then never converted, in either mode, and cannot trigger the hotkey (v1 spec, 3.2). | Recognising KeePassXC by name: every auto-type tool and text expander has the same problem. Holding the toggle back while auto-type runs: unnecessary once its keys are left alone. No option: an on-screen keyboard also types as an app, and its user needs conversion. |
| Stale permission | **A Reset Permission button** in the panel while Accessibility is missing. | Leaving it to the README: the user would land in Settings, see Agares already switched on, and have no hint that the entry must be removed first. |

## 3. The hotkey

### 3.1 Shapes and validity

A hotkey is a set of modifiers (Control, Option, Shift, Command) with or without one key.

- Modifiers alone: valid with two or more. It fires when they are released, if nothing else happened during the hold.
- With a key: valid when Control, Option or Command is among the modifiers. It fires on the key press, when the held modifiers are exactly the hotkey's. Holding it down does not repeat the toggle.
- Command+Tab, with or without other modifiers, is never a hotkey.

### 3.2 The fix

For a modifiers-only hotkey, a hold is spoiled as soon as it contains a modifier outside the hotkey, a key press that is not the hotkey, or a mouse click. A spoiled hold never fires, and stays spoiled until every modifier is released. The v1 code re-armed whenever the held set became exactly the hotkey, including while releasing a larger chord.

### 3.3 Presets

| Preset | Kind |
| --- | --- |
| ⌃⇧Space | Key. The default. |
| ⌃⌥Z | Key. |
| ⌃⌥ | Modifiers alone. |

### 3.4 Recording a custom hotkey

Record puts the key hook in recording mode. The next valid combination becomes the hotkey: a key pressed with valid modifiers, or two or more modifiers pressed and released. Escape alone cancels, and so does any mouse click or the panel losing focus. Key presses that cannot be a hotkey pass through to the app as usual. Record is disabled while Accessibility is missing, since recording runs through the key hook.

### 3.5 Storage

`UserDefaults`: `hotkeyModifiers` (bit set) and `hotkeyKeyCode` (−1 for none). An invalid stored value falls back to the default. The other keys are `vietnameseOn`, `soundOn`, `allowsZFWJ`, `ignoresOtherApps` and `nextUpdateCheck` (section 7). Settings are written on a background queue, never on the thread the key hook runs on.

## 4. Sound

`soundOn` (default on) plays the system sound Tink when Vietnamese turns on and Pop when it turns off, however the toggle was made.

The sound is started on a background queue, never on the main thread. Starting a sound waits for the audio output to be ready, and with the output asleep that wait was measured at 3,959 ms on Bluetooth headphones (2026-11-25). The toggle runs inside the key hook, so that wait froze the menu bar letter and made macOS switch the hook off for not responding, which is why the hotkey sometimes had to be pressed several times. A sound still queued behind a slow start is dropped when the next toggle comes, so the wait cannot end in a burst of sounds.

Nothing in the toggle waits. It flips the state, tells the key hook, and changes the menu bar letter at once; saving the setting and starting the sound are handed to background queues. Measured on the real toggle: about 10 µs, about 100 µs with the sound on.

## 5. The panel

One fixed-size window, about 420 points wide, dark graphite with ember accents (Goetia's dark tokens: `#0f1115`, `#161a20`, `#1e232b`, border `#2a303a`, text `#e7eaef` and `#9aa3af`, accent `#ff9e2c` to `#e8590c`).

```text
┌──────────────────────────────────────────┐
│               ╭──────────╮               │
│               │    â     │               │
│               ╰──────────╯               │
│            Vietnamese · Telex            │
│                                          │
│  [ Try it here: tieengs vieejt         ] │
│                                          │
│  HOTKEY                                  │
│  (⌃ ⇧ Space)  (⌃ ⌥ Z)  (⌃ ⌥)             │
│  Press Control + Shift + Space to switch.│
│  [Record…]                               │
│                                          │
│  ☐ Allow z, w, j, f as consonants        │
│  ☑ Leave text typed by other apps alone  │
│  ☑ Play a sound when toggling            │
│  ☑ Launch at login                       │
│                                          │
│  ● Accessibility granted                 │
│  Agares 0.1.0       [Check for Updates…] │
└──────────────────────────────────────────┘
```

- **Seal:** a button. While Vietnamese is on the ring is ember, glows, and the glow slowly breathes; the letter is `â`. While off the ring is grey and the letter is `a`. It springs slightly on every toggle, including one made by hotkey from another app. The whole circle takes clicks, not only the drawn ring and letter. It is left out of the keyboard focus order: as the first control it took the focus ring, a square around the round seal, whenever the panel opened with keyboard navigation switched on.
- **Try-it field:** an ordinary text field. Typing there goes through the real key hook.
- **Hotkey:** the presets as keycap chips with the current one outlined in ember. A custom hotkey appears as an extra chip in front. Under the chips the current hotkey is spelled out in words ("Press Control + Option + Z to switch."), and each chip has the words as its tooltip. Symbols alone were not enough: ⌃ is the Control key, but at chip size it reads as an arrow, and a user pressing Shift + Option + Z for the second preset got `¸` and no switch.
- **Checkboxes:** allow z, w, j, f as consonants (off by default; v1 spec, 4.8), leave text typed by other apps alone (on by default; v1 spec, 3.2), sound, and launch at login (moved here from the menu).
- **Footer:** Accessibility state; the version and Check for Updates. When a newer release is known, the footer shows the newer version in ember beside the current one ("0.2.0 available"), and the button becomes Get 0.2.0…, which opens the release page. While Accessibility is missing the footer instead offers a button to open the Settings pane and a Reset Permission button. Reset Permission runs `tccutil reset Accessibility` for the app's bundle id, which clears a grant left by a build from another signer (macOS still lists it as switched on but no longer honours it), then asks macOS to prompt again and opens the Settings pane.

The seal is labelled for VoiceOver with its on or off value, and each preset chip with its keys in words.

## 6. Menu bar, Dock and quitting

The menu bar item shows `V`, `E` or `⚠`, followed by a dot when a newer release is known. Its width is fixed (one size without the dot, one with), because `V` is a point wider than `E` and a width that follows the letter nudges the item and its neighbours on every switch. Its menu: Open Accessibility Settings… (only while missing), Version 0.2.0 Available…, naming the newer release (only when one is known), Vietnamese (checkmark), Open Agares…, Check for Updates…, Quit Agares.

- The app lives in the menu bar (`LSUIElement`). It has a Dock icon only while the panel is open: showing the panel switches the app to a regular app, and closing the panel switches it back.
- The panel opens from the menu bar item, and also when Agares is opened again from Launchpad, Spotlight or Finder while it is running.
- Closing the panel hides it and removes the Dock icon. The app keeps running.
- The main menu has Hide, Close Panel and an Edit menu, and no Quit item. Without a Quit item ⌘Q would do nothing, so it is an unlisted second shortcut for Close Panel.
- `applicationShouldTerminate` allows a quit only when it came from the menu bar item or the quit event's reason is logout, restart or shutdown. Any other quit closes the panel and is cancelled.
- `scripts/bundle.sh install` still restarts the app: it sends a signal, which this rule does not see.

## 7. Check for updates

A `GET` to `https://api.github.com/repos/quyennguyenvu/agares/releases/latest`. The repository name is hardcoded. `tag_name` must be `v` plus three plain numbers, or three plain numbers; anything else counts as a check that named no version. The release page is always `https://github.com/quyennguyenvu/agares/releases/tag/v<version>`, built from the validated version, never from the response. Nothing is downloaded or installed.

The request is made in two situations.

**The daily check.** Agares checks when it starts and then at most once every 24 hours, on the same two-second tick that watches the Accessibility permission. `nextUpdateCheck` holds the time of the next one: it is booked a day ahead before the request goes out, so a check that fails is not retried and the next one comes a day later. The check is silent. A newer release switches on the dot in the menu bar, the Version … Available… menu item and the panel's Get … button; a release that is not newer switches them off; a check that named no version leaves them as they were.

**The Check for Updates command.** It always answers with an alert, and updates the same indicators.

- Newer than the running version: the alert offers to open the release page.
- Not newer: the alert says Agares is up to date.
- No version named, or GitHub not reached: the alert says the check could not be done.

## 8. Code layout

| File | Change |
| --- | --- |
| `Sources/AgaresEngine/Hotkey.swift` | New: `Modifiers`, `Hotkey`, `HotkeyMatcher`, `HotkeyRecorder` |
| `Sources/AgaresEngine/Version.swift` | New: three-number versions and their ordering |
| `Sources/Agares/AppModel.swift` | New: settings, state and actions shared by the menu and the panel |
| `Sources/Agares/Panel.swift` | New: the window and its SwiftUI views; switches the Dock icon on and off with the window |
| `Sources/Agares/UpdateCheck.swift` | New: the GitHub request and the alert that answers a manual check; `AppModel` schedules the daily check |
| `Sources/Agares/KeyTap.swift` | Uses `HotkeyMatcher`; adds recording mode |
| `Sources/Agares/StatusMenu.swift` | New menu, Dock and quit rules; state moves to `AppModel` |
| `Sources/Agares/main.swift`, `Resources/Info.plist` | Still a menu bar app at launch (`LSUIElement`); `Info.plist` is kept in the layout `plutil` writes |

## 9. Testing

Unit tests for the hotkey matcher (including the exact Ctrl+Shift+Cmd+4 sequence), the recorder, keycap labels, validity, and version parsing and ordering. The panel, sounds, Dock and quit rules, and the update alert are checked by hand.

## 10. Out of scope

- Side-specific single-key hotkeys
- A light theme
- Downloading or installing updates
- A switch to turn the daily update check off
- Per-app settings
- Warning when a recorded hotkey collides with another app's shortcut

## 11. Risks

1. **A modifiers-only hotkey can still fire after input the key hook cannot see**, such as a media key pressed during the hold. The default avoids this by being a key hotkey.
2. **The update check finds nothing until the repository is public and has a release tagged `v<version>`.**
3. **Other typing tools double-convert.** OpenKey is installed and set to launch at login on this Mac, and the built-in Vietnamese Simple Telex input source is enabled. Only one of them should be active at a time.
4. **A manual launch shows no window** once Accessibility is granted; the menu bar item opens the panel, and so does opening Agares a second time.
5. **Reset Permission has not been exercised against a real stale grant.** Trying it means withdrawing a working permission.
6. **The app's own menus may lag for a moment when the panel opens.** macOS sometimes keeps showing the previous app's menus right after an app gains its Dock icon at run time.
