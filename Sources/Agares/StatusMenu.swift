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
