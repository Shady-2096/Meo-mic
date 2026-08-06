import AppKit
import SwiftUI

@main
struct MeoMicApplication: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Meo Mic", id: "main") {
            MainView(model: model)
                .onAppear { model.start() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: model.isConnected ? "waveform" : "mic")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // The menu says the same thing the window does, in the same words.
        // A dBFS reading here would be the instrument panel growing back.
        Text(model.statusHeadline)
        Text(model.selectedDevice?.name ?? "No audio route")
        Divider()
        Button("Open Meo Mic") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Audio setup…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            model.showsSetup = true
        }
        Divider()
        Button("Quit Meo Mic") {
            model.stop()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
