// Renders fixture scenes to PNG (hosted SwiftUI drawn offscreen). Run through scripts/snapshot.sh. Never starts audio.
// Check what the hosted render cannot draw: NSViewRepresentable views (the knob's scroll catcher): they stay blank, and they are invisible anyway.
import SwiftUI
import AppKit

@main struct Snapshot {
    static func icon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }

    static func scenes() -> [(String, Mixer)] {
        func mixer(_ s: [Strip], _ a: [Strip], denied: Bool = false, off: Bool = false) -> Mixer {
            let m = Mixer(); m.fixture(strips: s, apps: a, micDenied: denied, captureMaybeOff: off); return m
        }
        let turntable = Mixer.fixtureStrip(uid: "tt", name: "Turntable", position: 0.7, needleDB: -14, isDefaultInput: false)
        let mic = Mixer.fixtureStrip(uid: "mic", name: "MacBook Pro Microphone", position: 0.3, isDefaultInput: true, deviceGain: 0.6)
        let music = Mixer.fixtureStrip(uid: "com.apple.Music", name: "Music", isApp: true, position: 0.7, muted: true, needleDB: -20,
                          icon: icon("/System/Applications/Music.app"))
        let safari = Mixer.fixtureStrip(uid: "com.apple.Safari", name: "Safari", isApp: true, position: 0.7, needleDB: -8, clip: 1,
                           icon: icon("/Applications/Safari.app"))
        let states = [
            Mixer.fixtureStrip(uid: "a", name: "No signal", position: 0.7, noSignal: true),
            Mixer.fixtureStrip(uid: "b", name: "Disconnected", connected: false, position: 0.7),
            Mixer.fixtureStrip(uid: "c", name: "Clip lit", position: 0.7, needleDB: -2, clip: 1),
            Mixer.fixtureStrip(uid: "f", name: "Clip fading", position: 0.7, needleDB: -6, clip: 0.4),
            Mixer.fixtureStrip(uid: "d", name: "Muted", position: 0.7, muted: true, needleDB: -14),
        ]
        let broken = Mixer.fixtureStrip(uid: "e", name: "Spotify", isApp: true, position: 0.7, error: "Could not tap Spotify.")
        return [
            ("window", mixer([turntable, mic], [music, safari])),
            ("states", mixer(states, [broken])),
            ("banners", mixer([turntable], [], denied: true, off: true)),
            ("single", mixer([turntable], [])),
            ("empty", mixer([], [])),
        ]
    }

    @MainActor static func main() {
        let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/snapshots")
        for (name, mixer) in scenes() {
            for (tag, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                let view = ContentView(mixer: mixer).environment(\.colorScheme, scheme)
                // ImageRenderer drops ScrollView content (the strips), so draw an NSHostingView into a 2x bitmap instead.
                let host = NSHostingView(rootView: view)
                // The window sizes to its content: draw at the hosting view's fitting size.
                let size = host.fittingSize
                host.frame = CGRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                rep.size = size
                host.cacheDisplay(in: host.bounds, to: rep)
                guard let png = rep.representation(using: .png, properties: [:]) else {
                    print("FAIL: could not render \(name)-\(tag)"); exit(1)
                }
                let url = dir.appendingPathComponent("\(name)-\(tag).png")
                try! png.write(to: url)
                print(url.path)
            }
        }
    }
}
