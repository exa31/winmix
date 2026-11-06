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
                if model.isCallActive {
                    callDuckingBanner
                    Divider()
                }

                if case .degraded(let reason) = model.state {
                    degradedBanner(reason)
                }

                mainMixerContent
                Divider()
                bottomStatusBar
            }
        }
        .frame(minWidth: 440, idealWidth: 540, minHeight: 310)
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

            // Ducking Toggle Button (Condition-Driven)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.toggleAntiDucking()
                }
            }) {
                HStack(spacing: 5) {
                    if model.isCallActive {
                        Image(systemName: model.isAntiDuckingEnabled ? "phone.badge.checkmark" : "phone.down.waves.left.and.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(model.isAntiDuckingEnabled ? Color.green : Color.orange)
                        Text(model.isAntiDuckingEnabled ? "Telp: Musik 100%" : "Telp: Musik Redup 25%")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(model.isAntiDuckingEnabled ? Color.green : Color.orange)
                    } else {
                        Image(systemName: model.isAntiDuckingEnabled ? "shield.fill" : "speaker.wave.1.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(model.isAntiDuckingEnabled ? Color.green : Color.orange)
                        Text(model.isAntiDuckingEnabled ? "Anti-Duck: AKTIF (100%)" : "Ducking: NORMAL (25%)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(model.isAntiDuckingEnabled ? .primary : .secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(model.isAntiDuckingEnabled ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(model.isAntiDuckingEnabled ? Color.green.opacity(0.35) : Color.orange.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(model.isAntiDuckingEnabled
                ? "Bypass Ducking Aktif: Saat telepon, volume musik TETAP 100% kencang (Klik untuk ganti ke Ducking Normal 25%)"
                : "Ducking Normal: Saat telepon, volume musik OTOMATIS redup ke 25% (Klik untuk ganti ke Anti-Duck 100%)")

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

    // MARK: - Call Ducking Live Banner (Only Shown During Call)

    private var callDuckingBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(model.isAntiDuckingEnabled ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: "phone.badge.waveform.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.isAntiDuckingEnabled ? Color.green : Color.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("PANGGILAN AKTIF")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(model.isAntiDuckingEnabled ? Color.green : Color.orange)

                    if let app = model.activeCallAppName {
                        Text("•  \(app)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }

                Text(model.isAntiDuckingEnabled
                    ? "🛡️ Mode Anti-Duck: Musik dipertahankan kencang 100% (Bypass macOS)"
                    : "🔉 Mode Ducking: Musik otomatis diredupkan ke 25% agar suara telepon jelas")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.toggleAntiDucking()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: model.isAntiDuckingEnabled ? "arrow.down.right" : "shield.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(model.isAntiDuckingEnabled ? "Ubah ke Redup (25%)" : "Bypass (Tetap 100%)")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(model.isAntiDuckingEnabled ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(model.isAntiDuckingEnabled ? Color.orange.opacity(0.4) : Color.green.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(model.isAntiDuckingEnabled
                ? "Klik untuk meredupkan musik saat panggilan ini (25%)"
                : "Klik untuk memulihkan musik tetap 100% kencang")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            model.isAntiDuckingEnabled
                ? Color.green.opacity(0.08)
                : Color.orange.opacity(0.08)
        )
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

            if model.isCallActive {
                Text("•")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(model.isAntiDuckingEnabled ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Call: \(model.isAntiDuckingEnabled ? "Musik 100%" : "Musik Redup 25%")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(model.isAntiDuckingEnabled ? Color.green : Color.orange)
                }
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

