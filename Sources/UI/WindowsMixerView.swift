import SwiftUI
import CoreAudio

/// The primary container for the Windows Volume Mixer UI.
struct WindowsMixerView: View {
    @ObservedObject var model: MixerModel
    var isStandaloneWindow: Bool = false
    var onDetach: (() -> Void)? = nil

    var isClassic: Bool { model.isClassicTheme }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if model.needsPrimer {
                PrimerView(model: model)
            } else {
                if case .degraded(let reason) = model.state {
                    degradedBanner(reason)
                }

                mainMixerContent
                Divider()
                bottomStatusBar
            }
        }
        .frame(minWidth: 420, idealWidth: 520, minHeight: 330, maxHeight: 380)
        .background(
            isClassic
                ? Color(nsColor: .windowBackgroundColor)
                : Color(nsColor: .underPageBackgroundColor).opacity(0.85)
        )
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            // App Icon & Title
            HStack(spacing: 6) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isClassic ? .primary : MixerTheme.win11Blue)

                Text("WinMix")
                    .font(.system(size: 14, weight: .bold))

                Text("OSS")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(MixerTheme.win11Blue)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(MixerTheme.win11Blue.opacity(0.12))
                    )
            }

            Spacer()

            // Theme Switcher Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.isClassicTheme.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isClassic ? "desktopcomputer" : "sparkles")
                        .font(.system(size: 10))
                    Text(isClassic ? "Classic (SndVol)" : "Windows 11")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .help("Toggle between Windows 11 and Classic SndVol theme")

            // Popout to Standalone Window Button
            if !isStandaloneWindow, let detachAction = onDetach {
                Button(action: detachAction) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Open in standalone window")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            isClassic
                ? Color(nsColor: .controlBackgroundColor).opacity(0.6)
                : Color(nsColor: .controlBackgroundColor).opacity(0.3)
        )
    }

    // MARK: - Main Mixer Content

    private var mainMixerContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // Master Device Column (Left)
            WindowsDeviceColumn(model: model)
                .padding(.leading, 12)
                .padding(.vertical, 10)

            // Vertical Divider
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1)
            }
            .padding(.vertical, 8)

            // Applications Section (Right)
            VStack(alignment: .leading, spacing: 6) {
                Text("Applications")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isClassic ? .primary : MixerTheme.win11Blue)
                    .padding(.top, 10)
                    .padding(.leading, 4)

                if model.channels.isEmpty {
                    emptyStateView
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 10) {
                            ForEach(model.channels) { ch in
                                WindowsAppColumn(model: model, id: ch.id)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.trailing, 14)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)

            Text("Tidak ada aplikasi yang memutar audio")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Putar musik, video, atau game, maka aplikasi akan langsung muncul di sini.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Bottom Status Bar

    private var bottomStatusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle()
                    .fill(model.state == .running ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                Text(model.state == .running ? "Siap / Ready" : "Memulai / Starting...")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(model.channels.count) aplikasi aktif")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)

            Text("•")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                if model.isAutoOutput {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8))
                        .foregroundStyle(isClassic ? Color.accentColor : MixerTheme.win11Blue)
                }
                Text(model.isAutoOutput ? "Auto: \(model.outputName)" : model.outputName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Degraded Banner

    private func degradedBanner(_ reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kontrol audio per-aplikasi dijeda")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(reason). Audio tetap berbunyi normal.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }
}

