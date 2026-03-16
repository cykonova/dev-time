import SwiftUI
import AppKit

@main
struct DevTimeApp: App {
    @StateObject private var timer = TimerManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(timer: timer)
        } label: {
            Text(monospacedTitle)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: timer.showAwayPrompt) { _, show in
            if show {
                appDelegate.showAwayWindow(timer: timer)
            } else {
                appDelegate.closeAwayWindow()
            }
        }
    }

    private var monospacedTitle: AttributedString {
        let title = timer.menuBarTitle
        var attr = AttributedString(title)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
        attr.font = Font(font)
        return attr
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var awayWindow: NSWindow?

    func showAwayWindow(timer: TimerManager) {
        // Fully defer window creation to the next run loop iteration,
        // outside any SwiftUI/AppKit layout pass
        DispatchQueue.main.async { [weak self] in
            guard let self, self.awayWindow == nil else { return }

            let view = AwayPromptView(timer: timer)
            let hosting = NSHostingController(rootView: view)
            // Set a fixed frame before creating the window to prevent layout negotiation
            hosting.view.frame = NSRect(x: 0, y: 0, width: 300, height: 200)

            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            window.contentViewController = hosting
            window.title = "DevTime - Away"
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.center()

            self.awayWindow = window

            // Show the window after another run loop tick to be safe
            DispatchQueue.main.async {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func closeAwayWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.awayWindow?.close()
            self?.awayWindow = nil
        }
    }
}
