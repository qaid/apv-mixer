import SwiftUI

struct ContentView: View {
    let mixer: Mixer

    var body: some View {
        VStack(spacing: 16) {
            if mixer.micDenied {
                MicrophoneBanner(open: mixer.openMicrophoneSettings)
            }
            if mixer.turntableUID != nil {
                StripView(mixer: mixer)
            } else {
                Text("Turntable not found. Power it on.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
        .preferredColorScheme(.dark)
    }
}

struct MicrophoneBanner: View {
    let open: () -> Void
    var body: some View {
        HStack {
            Text("Microphone permission is off. Turntable Mixer cannot hear the turntable without it.")
                .font(.callout)
            Button("Open Microphone settings", action: open)
        }
        .padding(10)
        .background(Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
    }
}
