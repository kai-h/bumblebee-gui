import SwiftUI

@main
struct BumblebeeGUIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 920, height: 620)
        .commands {
            // Remove New Window from File menu — single-window app
            CommandGroup(replacing: .newItem) { }
        }
    }
}
