// Menu bar mode: a status item with the switch action and its settings.
import AppKit
import ServiceManagement

/// Saved choices (UserDefaults of asia.miron.macmxswitch).
struct Settings {
    private static let d = UserDefaults.standard

    static var host: Int {
        get { d.object(forKey: "host") as? Int ?? 1 }
        set { d.set(newValue, forKey: "host") }
    }
    static var monitorEnabled: Bool {
        get { d.object(forKey: "monitorEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "monitorEnabled") }
    }
    static var monitorInput: Int {
        get { d.object(forKey: "monitorInput") as? Int ?? 17 }
        set { d.set(newValue, forKey: "monitorInput") }
    }

    static var options: Options {
        Options(host: host, monitorInput: monitorEnabled ? UInt16(monitorInput) : nil)
    }
}

/// Standard MCCS input source values (VCP 0x60); monitors may use others, hence "Custom…".
private let inputPresets: [(Int, String)] = [
    (15, "DisplayPort 1"), (16, "DisplayPort 2"), (17, "HDMI 1"), (18, "HDMI 2"), (27, "USB-C"),
]

private func inputName(_ v: Int) -> String {
    inputPresets.first { $0.0 == v }.map { "\($0.1) (\(v))" } ?? "Input \(v)"
}

/// The question shown when the monitor can't be switched but keyboard and mouse can.
func withoutMonitorQuestion(_ problems: [String], host: Int) -> String {
    "The monitor can't be switched:\n" + problems.map { "• " + $0 }.joined(separator: "\n")
        + "\n\nSwitch keyboard and mouse to channel \(host) anyway? The monitor will keep showing this Mac."
}

/// Dialog for the same question. Cancel is the default (first) button, so pressing Return or a dialog
/// that can't be shown never switches; only an explicit click on the second button does.
func confirmWithoutMonitorDialog(_ problems: [String], host: Int) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Monitor not switched"
    alert.informativeText = withoutMonitorQuestion(problems, host: host)
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Switch Keyboard & Mouse")
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertSecondButtonReturn
}

final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private let switcher = Switcher()
    private var busy = false

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "MacMXSwitch")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    /// Opening the app again (Spotlight, Finder, a Shortcuts "Open App" hotkey) switches right away.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        switchNow()
        return false
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let target =
            "channel \(Settings.host)" + (Settings.monitorEnabled ? " · \(inputName(Settings.monitorInput))" : "")
        menu.addItem(action("Switch to \(target)", #selector(switchNow), enabled: !busy))
        menu.addItem(.separator())

        menu.addItem(header("Logitech channel"))
        for h in 1...3 {
            let i = action("Channel \(h)", #selector(setHost(_:)))
            i.tag = h
            i.state = Settings.host == h ? .on : .off
            i.indentationLevel = 1
            menu.addItem(i)
        }
        menu.addItem(.separator())

        let mon = action("Switch monitor", #selector(toggleMonitor))
        mon.state = Settings.monitorEnabled ? .on : .off
        menu.addItem(mon)

        let inputItem = NSMenuItem(
            title: "Monitor input: \(inputName(Settings.monitorInput))", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (v, name) in inputPresets {
            let i = action("\(name) (\(v))", #selector(setInput(_:)))
            i.tag = v
            i.state = Settings.monitorInput == v ? .on : .off
            sub.addItem(i)
        }
        sub.addItem(.separator())
        let isCustom = !inputPresets.contains { $0.0 == Settings.monitorInput }
        let custom = action(isCustom ? "Custom (\(Settings.monitorInput))…" : "Custom…", #selector(customInput))
        custom.state = isCustom ? .on : .off
        sub.addItem(custom)
        inputItem.submenu = sub
        inputItem.isEnabled = Settings.monitorEnabled
        menu.addItem(inputItem)
        menu.addItem(.separator())

        menu.addItem(action("Check devices", #selector(checkDevices), enabled: !busy))
        let login = action("Open at login", #selector(toggleLogin))
        switch SMAppService.mainApp.status {
        case .enabled: login.state = .on
        case .requiresApproval: login.state = .mixed  // allowed in System Settings > Login Items
        default: login.state = .off
        }
        menu.addItem(login)
        menu.addItem(action("Open log", #selector(openLog)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacMXSwitch", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
    }

    private func action(_ title: String, _ sel: Selector, enabled: Bool = true) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: enabled ? sel : nil, keyEquivalent: "")
        i.target = self
        return i
    }

    private func header(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    // MARK: actions

    @objc func switchNow() {
        // Nothing to show on success: keyboard, mouse and screen now belong to the other computer.
        // Nor after a cancelled monitor prompt: the user has just seen the problem.
        if let r = perform(Settings.options), !r.ok, !r.asked { show(r.lines) }
    }

    @objc private func checkDevices() {
        var o = Settings.options
        o.dryRun = true
        if let r = perform(o) { show(r.lines) }
    }

    @objc private func setHost(_ sender: NSMenuItem) { Settings.host = sender.tag }
    @objc private func toggleMonitor() { Settings.monitorEnabled.toggle() }
    @objc private func setInput(_ sender: NSMenuItem) { Settings.monitorInput = sender.tag }

    @objc private func customInput() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.stringValue = String(Settings.monitorInput)
        let alert = NSAlert()
        alert.messageText = "Monitor input"
        alert.informativeText = "DDC input value (VCP 0x60), the number you'd pass to m1ddc set input."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let v = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), (1...0xFFFF).contains(v) {
            Settings.monitorInput = v
        } else {
            show(["“\(field.stringValue)” is not a valid input number."])
        }
    }

    @objc private func openLog() { NSWorkspace.shared.open(logURL) }

    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled || svc.status == .requiresApproval {
                try svc.unregister()
            } else {
                try svc.register()
            }
        } catch {
            show(["Could not change Open at login: \(error.localizedDescription)"])
        }
        if svc.status == .requiresApproval {
            show(["Allow MacMXSwitch in System Settings > General > Login Items to finish."])
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func perform(_ o: Options) -> RunResult? {
        guard !busy else { return nil }
        busy = true
        item.button?.appearsDisabled = true
        defer {
            busy = false
            item.button?.appearsDisabled = false
        }
        return switcher.run(o) { confirmWithoutMonitorDialog($0, host: o.host) }
    }

    private func show(_ lines: [String]) {
        let alert = NSAlert()
        alert.messageText = "MacMXSwitch"
        alert.informativeText = lines.joined(separator: "\n")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
