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
        return open
    }

    private func lookForSpotlight() -> Bool {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Spotlight" { return true }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return (windows as? [[String: Any]] ?? []).contains { $0[kCGWindowOwnerName as String] as? String == "Spotlight" }
    }
}
