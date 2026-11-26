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
