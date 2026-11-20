// MacMXSwitch: hand the Logitech MX Keys + MX Master 4 (Easy-Switch channel, HID++ 0x1814 over BLE)
// and the external monitor (input, DDC/CI) to another computer.
//
// No arguments: menu bar app (settings in the menu; opening the app again switches).
// With arguments, one run and exit:
//   --host N (1-based, default 1), --input N (monitor input, default 17),
//   --no-monitor, --monitor-only, --dry-run
import AppKit

let args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }

if args.isEmpty {
    let app = NSApplication.shared
    let controller = MenuBarController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    app.run()
} else {
    var o = Options()
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "--dry-run": o.dryRun = true
        case "--host": if let v = it.next(), let n = Int(v) { o.host = n }
        case "--input": if let v = it.next(), let n = UInt16(v) { o.monitorInput = n }
        case "--no-monitor": o.monitorInput = nil
        case "--monitor-only": o.monitorOnly = true
        default: print("unknown option \(a)")
        }
    }
    let fromTerminal = isatty(STDOUT_FILENO) != 0
    if !fromTerminal { NSApplication.shared.setActivationPolicy(.accessory) }
    let r = Switcher().run(o) { problems in
        if !fromTerminal { return confirmWithoutMonitorDialog(problems, host: o.host) }
        let q = withoutMonitorQuestion(problems, host: o.host)
        guard isatty(STDIN_FILENO) != 0 else {
            print(q + "\n(no terminal to answer; not switching. Use --no-monitor to skip the monitor.)")
            return false
        }
        print(q + " [y/N] ", terminator: "")
        fflush(stdout)
        return readLine()?.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("y") == true
    }
    // When launched via `open --args`, show a dialog if something went wrong (or dry run),
    // but not right after the user answered the monitor question.
    if !fromTerminal && (!r.ok || o.dryRun) && !r.asked {
        NSApplication.shared.setActivationPolicy(.accessory)
        let alert = NSAlert()
        alert.messageText = "MacMXSwitch"
        alert.informativeText = r.lines.joined(separator: "\n")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    exit(r.ok ? 0 : 1)
}
