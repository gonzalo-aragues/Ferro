import AppKit
import ServiceManagement

@main
enum FerroMain {
    static let delegate = AppDelegate()
    static func main() {
        let app = NSApplication.shared
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.run(dir: CommandLine.arguments[i + 1])
            return
        }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController()
        notch.start()
        setupStatusItem()
        // Dev flag: `--open <tab>` opens the island on a tab at launch (handy for checking the real glass).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--open") {
            let tab = i + 1 < args.count ? IslandTab(rawValue: args[i + 1]) : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let tab { self?.notch.model.tab = tab }
                self?.notch.setExpanded(true, sticky: true)
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Ferro")
        let menu = NSMenu()
        menu.addItem(item("Open Island", #selector(openIsland)))
        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit Ferro", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func openIsland() { notch.setExpanded(true, sticky: true) }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch { NSSound.beep() }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
