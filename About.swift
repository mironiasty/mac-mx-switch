// The About window: app icon, name and version, and who made it.
import AppKit
import SwiftUI

private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MacMXSwitch"

private var versionText: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "?"
    let build = info["CFBundleVersion"] as? String
    return "Version \(version)" + (build.map { " (\($0))" } ?? "")
}

struct AboutView: View {
    private static let authorAvatar = Bundle.main.url(forResource: "Author", withExtension: "svg")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text(appName).font(.title2.bold())
                Text(versionText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider().frame(width: 200).padding(.vertical, 8)

            HStack(spacing: 10) {
                if let avatar = Self.authorAvatar {
                    Image(nsImage: avatar)
                        .resizable()
                        .frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Made by Miron Pawlik")
                    Link("miron.asia", destination: URL(string: "https://miron.asia")!)
                }
            }
            if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 360)
    }
}

/// Shows the About window, reusing it if it is already open.
final class AboutWindow {
    static let shared = AboutWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            w.title = "About \(appName)"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
