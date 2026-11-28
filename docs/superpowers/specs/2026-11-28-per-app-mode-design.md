# Agares — Vietnamese or English per App: Design Spec

**Date:** 2026-11-28 **Status:** Implemented 2026-11-28, hand checklist run the same day. Its last check, a look at Diagnostics after a day of use, is still to run **Author:** quyennv + Claude

## 1. Summary

Agares gains one option: remember Vietnamese or English for each app. With it on, every app keeps the mode it was last left in, and coming back to an app brings that mode back. Code in VS Code stays English and chat in Zalo stays Vietnamese without the hotkey being pressed on every switch between them.

It restores; it never guesses. Agares does not look at what is being typed, and inside one app nothing changes: writing a Vietnamese comment in VS Code, or answering a foreigner in a chat app, still takes the hotkey, and the app then remembers that.

The option is a checkbox in the panel, off by default.

This spec extends `2026-11-25-control-panel-design.md` and takes "Remembering Vietnamese or English per app" out of section 9 of `2026-11-23-agares-design.md`.

## 2. Decisions & alternatives considered

| Decision | Chosen | Rejected alternatives |
| --- | --- | --- |
| What is remembered | **The mode each app was last left in**, saved when the user toggles (user decision, 2026-11-28). No setup. | Fixed rules ("Terminal is always English"): they need a list of apps in the panel, and an app used for both languages fits no rule. Working out the language from what is typed: the user wants nothing that changes their text or mode by guessing, and ruled out automatic restore of English words on the same day for that reason. A mode per window or per conversation: it means reading window titles through Accessibility, which differs from app to app. |
| An app with no saved mode | **Keeps the mode that is on**, as it does today. | Saving a mode for every app the first time it comes to the front: the table would then list every app the user ever opened, not only the ones they toggled in. |
| What an automatic switch shows | **The menu bar letter flips. No sound.** | The toggle sound: every ⌘Tab between two apps would tick or pop. |
| Default | **Off.** Nothing changes for a user who updates. | On by default: a mode that changes by itself after an update, with no explanation. |
| Where the option lives | **A checkbox in the panel.** | A menu bar menu item as well: Launch at login was moved out of that menu into the panel on 2026-11-25. |
| Agares's own panel | **An app like any other.** The seal, clicked with the panel in front, sets the mode for the panel's try-it field. | Leaving Agares out of the rule: one more special case, and a toggle made on the seal would still not carry into an app that has a saved mode. |
| Unticking the option | **The saved modes are kept**, and apply again when it is ticked. | Clearing them, or a Forget button: nobody has asked for either. |
| Who sees the saved modes | **Nobody.** They stay in Agares's preferences on this Mac. The diagnostics report says whether the option is on and does not list them, in keeping with its rule against a history of apps. | Listing them in the report. |

## 3. Behaviour

Two rules, both only while the option is on.

1. **Saving.** A toggle made by the user (the hotkey, the menu bar menu's Vietnamese item, the seal) saves the new mode for the app in front.
2. **Restoring.** When an app comes to the front and has a saved mode that differs from the current one, Agares switches to it. The switch is silent and saves nothing.

| The user | Mode | Why |
| --- | --- | --- |
| Types code in VS Code | E | |
| Presses ⌘Tab to Zalo | V | Zalo was left in Vietnamese |
| Presses ⌘Tab back to VS Code | E | VS Code was left in English |
| Presses the hotkey in VS Code for a Vietnamese comment | V | A toggle; VS Code now remembers V |
| Presses ⌘Tab to an app never toggled in | V | No saved mode, so the mode stays |

The details:

- **An app is known by its bundle id.** An app without one has nothing saved for it, and coming to it changes nothing.
- **The app in front is tracked whether or not the option is on,** so ticking the box takes effect at the next toggle or app switch. Ticking it saves nothing by itself.
- **The menu bar menu does not bring Agares to the front,** so its Vietnamese item saves for the app the user is in (risk 1).
- **The panel does bring Agares to the front.** Agares has its own saved mode under its own bundle id, like any app.
- **Spotlight on macOS 27** does not change the app in front (v1 spec, section 5), so it types in the mode of the app under it. Before macOS 27 Spotlight can be the app in front, and would then get a saved mode of its own (risk 4).
- **At launch nothing is restored.** Agares starts in the mode it was quit in, and the rule applies from the first app switch.
- **A restore ends the word being tracked,** as any change of mode does. An app switch ends it already.

## 4. The panel

One new checkbox, above the sound checkbox, because both are about switching. The two typing options stay together above it.

```text
┌──────────────────────────────────────────────────┐
│                                   Diagnostics ›  │
│                   ╭──────────╮                   │
│                   │    â     │                   │
│                   ╰──────────╯                   │
│                Vietnamese · Telex                │
│                                                  │
│  [ Try it here: tieengs vieejt                ]  │
│                                                  │
│  HOTKEY                                          │
│  (⌃ ⇧ Space)  (⌃ ⌥ Z)  (⌃ ⌥)                     │
│  Press Control + Shift + Space to switch.        │
│  [Record…]                                       │
│                                                  │
│  ☐ Allow z, w, j, f as consonants                │
│  ☑ Leave text typed by other apps alone          │
│  ☐ Remember Vietnamese or English for each app   │
│  ☑ Play a sound when toggling                    │
│  ☑ Launch at login                               │
│                                                  │
│  ● Accessibility granted                         │
│  Agares 0.2.0               [Check for Updates…] │
└──────────────────────────────────────────────────┘
```

- **Label:** "Remember Vietnamese or English for each app".
- **Tooltip:** "When you come back to an app, Agares switches to the mode you last used there. These switches play no sound."
- **Window:** one row taller. The panel takes its height from its content, so nothing else moves.

Nothing else on screen changes. The menu bar letter and the seal follow the mode as they do for any toggle, and the diagnostics page is as it was.

## 5. Storage

`UserDefaults`, written on the background save queue like every other setting:

| Key | Value |
| --- | --- |
| `remembersPerApp` | Bool, false until the box is ticked |
| `appModes` | A dictionary from bundle id to Bool, true for Vietnamese |

A stored `appModes` that is not a dictionary of Bools is read as empty.

## 6. Cost

The rule of the v1 spec (5.1) holds: nothing that runs inside the key hook may wait on the system.

- **Restoring** runs outside the key hook, in the app-switch notification Agares already receives: one dictionary lookup per app switch.
- **Saving** runs inside the toggle, which the hotkey calls from the key hook. It adds one dictionary insert and one more block handed to the save queue, the same shape as the write of `vietnameseOn` already there.
- **The app in front** is read from macOS once, at launch, and after that kept in a variable by the notification. The key hook never asks macOS for it.

None of this is measured. The toggle was measured at about 10 µs (control-panel spec, section 4). A toggle that took more than 50 ms would show as a `[tap] slow callback … (hotkey)` line in Diagnostics, which is one of the hand checks; a smaller slowdown would not.

## 7. Code layout

| File | Change |
| --- | --- |
| `Sources/Agares/AppModel.swift` | `remembersPerApp` (published, saved), `appModes` and `frontApp` (private); an observer of `NSWorkspace.didActivateApplicationNotification` that applies rule 2; one line in `toggle()` for rule 1; "remember per app on" or "off" in the report's settings line |
| `Sources/Agares/Panel.swift` | The checkbox and its tooltip |

The restore sets `vietnameseOn` directly and does not call `toggle()`. That one choice is what makes it silent and keeps it from saving. `KeyTap`, `StatusMenu` and the engine do not change.

## 8. Testing

No unit tests: the logic is two `if` statements around a dictionary, in the app target, which has no test target. It is checked by hand, with A and B standing for any two apps.

| Check | Expect |
| --- | --- |
| Box unticked: toggle in A, switch to B | The mode follows from A to B, as before |
| Tick the box. Press the hotkey to English in A and to Vietnamese in B, then ⌘Tab back and forth | The menu bar letter flips to each app's mode on arrival; no sound |
| Press the hotkey | The sound plays as before |
| Switch to an app never toggled in | The mode stays |
| With A in front, choose Vietnamese in the menu bar menu, leave A and come back | A has the new mode |
| Open the panel, click the seal, go back to A | A's saved mode returns |
| Open Spotlight over A and type | A's mode |
| Quit Agares, open it again, switch to A and to B | The saved modes are still there |
| Untick the box, switch between A and B | No switching. Ticked again, the saved modes apply |
| Copy the diagnostics report | The settings line ends with `remember per app on`, and the report holds no list of remembered apps. `last app` on the `Now:` line is there as before |
| After a day of use, open Diagnostics | No `slow callback … (hotkey)` line |

## 9. Documents to update

When this is built:

- `README.md`: the panel's contents under "Using it", and a line under "Good to know".
- `2026-11-23-agares-design.md`: section 9 and the Amendments table.
- `2026-11-25-control-panel-design.md`: the storage keys (3.5), the panel sketch and checkbox list (5), and "Per-app settings" under out of scope (10).
- `2026-11-27-diagnostics-design.md`: the settings line of the report (4).
- The plans that print `AppModel.swift` and `Panel.swift`, which `scripts/sync-plans.py` checks.

## 10. Out of scope

- A list of the remembered apps, forgetting one app, and forgetting all of them
- Fixed rules per app
- A mode per window, tab or conversation
- Working out the language from what is typed
- A sound or any other notice for an automatic switch
- Restoring a mode at launch
- Other settings per app

## 11. Risks

1. **The menu bar menu does not change the app in front: verified by hand on 2026-11-28.** Its Vietnamese item, chosen with TextEdit in front, was saved for TextEdit and came back after a switch to Notes and back. Had the menu made Agares the front app, the toggle would have been saved for Agares instead.
2. **The app-switch notification arrives after the switch.** A key typed in between is handled in the old mode. The delay is not measured.
3. **An app with no saved mode takes over whatever mode is on,** including one the panel has just restored for itself. Opening the panel can therefore change the mode the user carries into such an app.
4. **Spotlight before macOS 27 is not tested.** This Mac runs macOS 27, where Spotlight is not an app.
