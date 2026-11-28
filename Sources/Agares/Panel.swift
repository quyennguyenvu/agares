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
        // The panel opens on its settings next time, and an unseen page stops being refreshed.
        model.hideDiagnostics()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.refreshLaunchAtLogin()
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
        // The settings stay in place under the diagnostics page and keep setting the window's size,
        // so the window does not jump when the page opens or closes.
        settings
            .opacity(model.diagnostics == nil ? 1 : 0)
            .disabled(model.diagnostics != nil)
            .accessibilityHidden(model.diagnostics != nil)
            .overlay {
                if let page = model.diagnostics {
                    DiagnosticsPage(page: page, back: model.hideDiagnostics, copy: model.copyDiagnostics)
                }
            }
            .padding(EdgeInsets(top: 40, leading: 28, bottom: 24, trailing: 28))
            .frame(width: 420)
            .background(Palette.bg0)
            .foregroundColor(Palette.text1)
            .tint(Palette.accent)
    }

    private var settings: some View {
        VStack(spacing: 22) {
            Seal(model: model)
            tryField
            hotkeySection
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Allow z, w, j, f as consonants", isOn: $model.allowsZFWJ)
                    .help("Words such as zô and jì can then take marks. So can English words that start with these letters.")
                Toggle("Leave text typed by other apps alone", isOn: $model.ignoresOtherApps)
                    .help("A password manager's auto-type or a text expander sends keys of its own. Agares then passes them through unconverted. Turn this off if you type with an on-screen keyboard.")
                Toggle("Remember Vietnamese or English for each app", isOn: $model.remembersPerApp)
                    .help("When you come back to an app, Agares switches to the mode you last used there. These switches play no sound.")
                Toggle("Play a sound when toggling", isOn: $model.soundOn)
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
        // In the corner beside the seal: the footer's rows are full while Accessibility is missing.
        .overlay(alignment: .topTrailing) {
            Button("Diagnostics ›", action: model.showDiagnostics)
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
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

/// What Agares noticed going wrong, and what is true right now. Laid over the settings.
private struct DiagnosticsPage: View {
    let page: Diagnostics.Page
    let back: () -> Void
    let copy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button("‹ Back", action: back)
                Text("DIAGNOSTICS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.text2)
                Spacer()
                Button("Copy", action: copy)
                    .help("Copies these lines, with the settings and the state above, as text.")
            }
            VStack(alignment: .leading, spacing: 7) {
                // Amber marks what would explain typing that does not convert.
                fact("Key hook", page.tap, fine: page.tap == "enabled")
                fact("Secure Input", page.secureInput, fine: page.secureInput == "off")
                fact("Input source", page.inputSource, fine: ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].contains(page.inputSource))
                fact("Other typing tools", page.otherTools, fine: page.otherTools == "none")
                fact("Last app", page.lastApp, fine: nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.bg1)
            .cornerRadius(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(page.lines.indices, id: \.self) { index in
                        line(page.lines[index])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 12))
    }

    /// Wide enough for the day as well only when a line from an earlier day is on show.
    private var stampWidth: CGFloat {
        page.lines.allSatisfy { $0.hasPrefix(page.today) } ? 60 : 82
    }

    private func fact(_ name: String, _ value: String, fine: Bool?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(fine.map { $0 ? Palette.ok : Palette.warn } ?? Color.clear)
                .frame(width: 7, height: 7)
            Text(name).foregroundColor(Palette.text2)
            Text(value).textSelection(.enabled)
        }
    }

    private func line(_ stored: String) -> some View {
        let parts = DiagnosticLog.parts(of: stored)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(parts?.stamp(today: page.today) ?? "")
                .foregroundColor(Palette.text2)
                .frame(width: stampWidth, alignment: .leading)
            (Text(parts.map { "[\($0.tag)] " } ?? "").foregroundColor(Palette.text2) + Text(parts?.text ?? stored))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11, design: .monospaced))
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
