import SwiftUI

@main struct TurntableMixerApp: App {
    private let mixer = Mixer.shared

    init() { mixer.start() }

    var body: some Scene {
        WindowGroup {
            ContentView(mixer: mixer)
        }
        .defaultSize(width: 620, height: 680)
    }
}
