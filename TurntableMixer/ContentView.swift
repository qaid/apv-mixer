import SwiftUI

struct ContentView: View {
    let mixer: Mixer
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            if mixer.micDenied {
                MicrophoneBanner(open: mixer.openMicrophoneSettings)
                    .padding(.horizontal, 24).padding(.top, 20)
            }
            if mixer.strips.isEmpty {
                Text("No input devices.")
                    .engraved(size: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(mixer.strips) { strip in
                            StripView(mixer: mixer, strip: strip)
                            if strip.id != mixer.strips.last?.id { PanelDivider() }
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxHeight: .infinity)
                }
            }
            if let error = mixer.engineError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Panel.ink(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.bottom, 14)
            }
        }
        .frame(minWidth: 360, minHeight: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Faceplate())
    }
}

/// Shown when macOS has denied the Microphone permission.
struct MicrophoneBanner: View {
    let open: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack {
            Text("Microphone permission is off. Turntable Mixer cannot hear the turntable without it.")
                .font(.callout)
                .foregroundStyle(Panel.ink(scheme))
            Button("Open Microphone settings", action: open)
        }
        .padding(10)
        .background(Color.orange.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.35), lineWidth: 1))
    }
}
