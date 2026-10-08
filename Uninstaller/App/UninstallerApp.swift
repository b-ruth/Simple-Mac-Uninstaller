import SwiftUI

struct UninstallerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Uninstaller", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .task { await model.loadApps() }
        }
        .defaultSize(width: 1100, height: 700)
    }
}
