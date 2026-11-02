import SwiftUI

/// A vertical volume slider designed to match Windows Volume Mixer faders.
struct VerticalFader: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0.0...1.0
    var isClassic: Bool = false
    var isMuted: Bool = false
    var height: CGFloat = 140

    @State private var isDragging: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            // Tick marks
            tickMarksView

            // Fader track & thumb
            GeometryReader { geo in
                let trackHeight = geo.size.height
                let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                let clampedNorm = max(0, min(1, normalized))
                let thumbY = (1.0 - clampedNorm) * trackHeight

                ZStack(alignment: .bottom) {
                    // Track background
                    trackView(totalHeight: trackHeight, filledHeight: clampedNorm * trackHeight)

                    // Thumb
                    thumbView
                        .position(x: geo.size.width / 2, y: thumbY)
                }
                .frame(width: geo.size.width, height: trackHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            isDragging = true
                            let progress = 1.0 - (gesture.location.y / trackHeight)
                            let newNorm = Float(max(0, min(1, progress)))
                            let newVal = range.lowerBound + newNorm * (range.upperBound - range.lowerBound)
                            value = round(newVal * 100) / 100
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
                .onTapGesture(count: 2) {
                    // Double-tap resets to 100% (1.0)
                    value = 1.0
                }
            }
            .frame(width: 28, height: height)
        }
        .frame(height: height)
    }

    // MARK: - Track

    @ViewBuilder
    private func trackView(totalHeight: CGFloat, filledHeight: CGFloat) -> some View {
        if isClassic {
            // Windows Classic recessed slot
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 4, height: totalHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1.5)
                            .stroke(Color.black.opacity(0.6), lineWidth: 0.5)
                    )
            }
        } else {
            // Windows 11 rounded modern track
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 6, height: totalHeight)

                Capsule()
                    .fill(MixerTheme.activeFill(isClassic: false, isMuted: isMuted))
                    .frame(width: 6, height: max(filledHeight, 0))
            }
        }
    }

    // MARK: - Thumb

    @ViewBuilder
    private var thumbView: some View {
        if isClassic {
            // Classic SndVol rectangular metallic knob with center grip
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.92), Color(white: 0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 24, height: 12)
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color(white: 0.45), lineWidth: 0.75)
                    )

                // Center grip line
                Rectangle()
                    .fill(Color(white: 0.35))
                    .frame(width: 12, height: 1.5)
            }
        } else {
            // Windows 11 rounded pill thumb
            ZStack {
                Capsule()
                    .fill(Color(nsColor: .controlColor))
                    .frame(width: 22, height: 12)
                    .shadow(color: .black.opacity(0.20), radius: isDragging ? 3 : 1.5, x: 0, y: 1)
                    .overlay(
                        Capsule()
                            .stroke(isDragging ? MixerTheme.win11Blue : Color.primary.opacity(0.25), lineWidth: 1.5)
                    )

                Circle()
                    .fill(MixerTheme.activeFill(isClassic: false, isMuted: isMuted))
                    .frame(width: 4, height: 4)
            }
        }
    }

    // MARK: - Tick Marks

    private var tickMarksView: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // 100% mark (Max)
            tickLine(width: 8, label: "100%", isBold: true)
            Spacer()
            // 75% mark
            tickLine(width: 4, label: "")
            Spacer()
            // 50% mark
            tickLine(width: 6, label: "50%")
            Spacer()
            // 25% mark
            tickLine(width: 4, label: "")
            Spacer()
            // 0% mark
            tickLine(width: 8, label: "0%")
        }
        .frame(width: 24, height: height)
        .padding(.vertical, 2)
    }

    private func tickLine(width: CGFloat, label: String, isBold: Bool = false) -> some View {
        HStack(spacing: 2) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 8, weight: isBold ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Rectangle()
                .fill(Color.primary.opacity(isBold ? 0.4 : 0.2))
                .frame(width: width, height: 1)
        }
    }
}

