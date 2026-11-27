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
