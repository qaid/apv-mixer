import SwiftUI

struct ContentView: View {
    let mixer: Mixer
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // The 2-strip floor keeps banners, the error line and the empty message readable; a lone strip fits tightly.
        let wordy = mixer.micDenied || mixer.captureMaybeOff || mixer.inputError != nil || (mixer.strips.isEmpty && mixer.apps.isEmpty)
        FitColumn(minWidth: wordy ? 2 * StripView.width : 0) {
            if mixer.micDenied {
                PermissionBanner(text: "Microphone permission is off. Turntable Mixer cannot hear the turntable without it.",
                                 button: "Open Microphone settings", open: mixer.openMicrophoneSettings)
                    .padding(.horizontal, 36).padding(.top, 36)
                    .wrapsToColumn()
            }
            if mixer.captureMaybeOff {
                PermissionBanner(text: "System Audio Recording may be off. App strips stay silent without it.",
                                 button: "Open System Audio Recording settings", open: mixer.openAudioCaptureSettings)
                    .padding(.horizontal, 36).padding(.top, mixer.micDenied ? 20 : 36)
                    .wrapsToColumn()
            }
            if mixer.strips.isEmpty && mixer.apps.isEmpty {
                Text("No input devices.")
                    .engraved(size: 14)
                    .padding(.vertical, 56)
                    .frame(maxWidth: .infinity)
            } else {
                // The row reports its natural size, so the window fits the strips. On a screen too small for it, the
                // scroll view takes over, capped at the screen's visible frame (less room for the title bar and banners).
                ViewThatFits(in: [.horizontal, .vertical]) {
                    strips
                    ScrollView([.horizontal, .vertical]) { strips }
                }
                .frame(maxWidth: screen.width, maxHeight: screen.height - 40 - extraHeight)
            }
            if let error = mixer.inputError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Panel.ink(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.bottom, 14)
                    .wrapsToColumn()
            }
        }
        .background(Faceplate())
    }

    private var strips: some View {
        HStack(alignment: .top, spacing: 0) {
            if !mixer.strips.isEmpty { StripGroup(mixer: mixer, title: "Inputs", strips: mixer.strips) }
            if !mixer.strips.isEmpty && !mixer.apps.isEmpty { GroupDivider() }
            if !mixer.apps.isEmpty { StripGroup(mixer: mixer, title: "Apps", strips: mixer.apps) }
        }
        // Edge padding is tuned to the visible ink (the meters, with nothing sticking out), about 36 pt on both sides.
        // The bottom keeps a state label ("No signal") and the divider ends clear of the window edge.
        .padding(.leading, 13).padding(.trailing, 13).padding(.bottom, 16)
        .fixedSize()
    }

    private var screen: CGSize { NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900) }

    /// Rough height of the banners and error text, kept out of the strip area's cap.
    private var extraHeight: CGFloat {
        (mixer.micDenied ? 80 : 0) + (mixer.captureMaybeOff ? 80 : 0) + (mixer.inputError == nil ? 0 : 50)
    }
}

private struct WrapsToColumn: nonisolated LayoutValueKey { static let defaultValue = false }

private extension View {
    /// Marks a view that takes the column's width and wraps its text, instead of setting the width.
    func wrapsToColumn() -> some View { layoutValue(key: WrapsToColumn.self, value: true) }
}

/// A top-to-bottom stack as wide as its widest unmarked child (at least `minWidth`). Marked children get that width.
private struct FitColumn: Layout {
    let minWidth: CGFloat

    /// Ignores the proposal on purpose: the column has one width, so the window (`.contentSize`) has one size.
    private func width(_ subviews: Subviews) -> CGFloat {
        let natural = subviews.filter { !$0[WrapsToColumn.self] }.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return max(minWidth, natural)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = width(subviews)
        return CGSize(width: w, height: subviews.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for v in subviews {
            let size = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            v.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height
        }
    }
}

/// One labelled group of strips.
private struct StripGroup: View {
    let mixer: Mixer
    let title: String
    let strips: [Strip]

    var body: some View {
        VStack(spacing: 0) {
            Text(title).engraved(size: 11).padding(.top, 33)
            HStack(spacing: 0) {
                ForEach(strips) { strip in
                    StripView(mixer: mixer, strip: strip)
                    if strip.id != strips.last?.id { PanelDivider() }
                }
            }
        }
    }
}

/// Shown when a permission is missing, with a button to the right Settings pane.
struct PermissionBanner: View {
    let text: String
    let button: String
    let open: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.callout)
                .foregroundStyle(Panel.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: open)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.35), lineWidth: 1))
    }
}
