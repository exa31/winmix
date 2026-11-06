import SwiftUI

/// A vertical audio peak level meter supporting both Windows 11 smooth gradient
/// and Windows Classic segmented LED styles.
struct VerticalVUMeter: View {
    var level: Float
    var peak: Float
    var isClassic: Bool = false
    var isMuted: Bool = false

    private let totalSegments = 16
    var height: CGFloat = 115
    var width: CGFloat = 8

    private let gradient = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.25, blue: 0.25), // Red (peak)
            Color(red: 0.98, green: 0.75, blue: 0.20), // Amber (warm)
            Color(red: 0.25, green: 0.85, blue: 0.40)  // Green (normal)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        Group {
            if isClassic {
                classicSegmentedMeter
            } else {
                modernFluentMeter
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Modern Windows 11 Fluent Meter

    private var modernFluentMeter: some View {
        let effLevel = isMuted ? 0.0 : CGFloat(max(0, min(1, level)))
        let effPeak  = isMuted ? 0.0 : CGFloat(max(0, min(1, peak)))

        return ZStack(alignment: .bottom) {
            // Background track
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.08))

            // Active level gradient fill
            gradient
                .mask(
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4)
                            .frame(height: max(effLevel * height, effLevel > 0 ? 3 : 0))
                    }
                )

            // Peak hold bar
            if effPeak > 0.03 {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.85))
                    .frame(height: 2)
                    .offset(y: -min(effPeak * height, height - 2))
            }
        }
        .animation(.linear(duration: 0.05), value: level)
    }

    // MARK: - Windows Classic Segmented LED Meter

    private var classicSegmentedMeter: some View {
        let effLevel = isMuted ? 0.0 : Float(max(0, min(1, level)))
        let effPeak  = isMuted ? 0.0 : Float(max(0, min(1, peak)))

        return VStack(spacing: 2) {
            ForEach((0..<totalSegments).reversed(), id: \.self) { idx in
                let segmentThreshold = Float(idx) / Float(totalSegments)
                let isLit = effLevel >= segmentThreshold
                let isPeakSegment = abs(effPeak - segmentThreshold) < (1.0 / Float(totalSegments))

                RoundedRectangle(cornerRadius: 1)
                    .fill(segmentColor(for: idx, lit: isLit || isPeakSegment))
                    .frame(height: (height - CGFloat(totalSegments * 2)) / CGFloat(totalSegments))
            }
        }
        .padding(1)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.black.opacity(0.6), lineWidth: 0.5)
                )
        )
    }

    private func segmentColor(for index: Int, lit: Bool) -> Color {
        guard lit else { return Color.black.opacity(0.3) }
        if index >= 14 {
            return Color(red: 0.95, green: 0.20, blue: 0.20) // Red
        } else if index >= 11 {
            return Color(red: 0.95, green: 0.80, blue: 0.20) // Yellow
        } else {
            return Color(red: 0.20, green: 0.85, blue: 0.35) // Green
        }
    }
}

