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
                callDuckingSection
                Divider()

                if case .degraded(let reason) = model.state {
                    degradedBanner(reason)
                }

                mainMixerContent
                Divider()
                bottomStatusBar
            }
        }
        .frame(minWidth: 460, idealWidth: 560, minHeight: 360, maxHeight: 440)
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

            // Call Audio Behavior Button (Bypass Ducking vs Normal macOS Ducking)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.toggleAntiDucking()
                }
            }) {
                HStack(spacing: 5) {
                    if model.isCallActive {
                        Image(systemName: model.isAntiDuckingEnabled ? "phone.badge.checkmark" : "phone.down.waves.left.and.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(model.isAntiDuckingEnabled ? Color.green : Color.orange)
                        Text(model.isAntiDuckingEnabled ? "Telp: Musik 100%" : "Telp: Musik Redup 25%")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(model.isAntiDuckingEnabled ? .primary : Color.orange)
                    } else {
                        Image(systemName: model.isAntiDuckingEnabled ? "shield.fill" : "speaker.wave.1")
                            .font(.system(size: 10))
                            .foregroundStyle(model.isAntiDuckingEnabled ? Color.green : Color.secondary)
                        Text(model.isAntiDuckingEnabled ? "Anti-Duck: Tetap 100%" : "Ducking: Normal Mac")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(model.isAntiDuckingEnabled ? .primary : .secondary)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(model.isCallActive
                            ? (model.isAntiDuckingEnabled ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                            : (model.isAntiDuckingEnabled ? Color.green.opacity(0.12) : Color.primary.opacity(0.06)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(model.isCallActive
                            ? (model.isAntiDuckingEnabled ? Color.green.opacity(0.5) : Color.orange.opacity(0.5))
                            : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(model.isCallActive
                ? (model.isAntiDuckingEnabled
                    ? "Panggilan Aktif: Musik/video ditahan 100% kencang (Klik untuk ganti ke Redup 25%)"
                    : "Panggilan Aktif: Musik/video diredupkan ke 25% (Klik untuk ganti ke Tetap 100%)")
                : (model.isAntiDuckingEnabled
                    ? "Mode Standby: Saat ada telepon nanti, musik TIDAK AKAN mengecil (Bypass Ducking Aktif)"
                    : "Mode Standby: Saat ada telepon nanti, musik AKAN mengecil otomatis (Standar macOS)"))

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

    // MARK: - Call Ducking Section (Always Visible)

    private var callDuckingSection: some View {
        HStack(spacing: 10) {
            // Left Status Icon
            ZStack {
                Circle()
                    .fill(model.isCallActive
                        ? (model.isAntiDuckingEnabled ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        : (model.isAntiDuckingEnabled ? Color.green.opacity(0.12) : Color.primary.opacity(0.08)))
                    .frame(width: 28, height: 28)

                Image(systemName: model.isCallActive
                    ? (model.isTestingDucking ? "phone.badge.waveform" : "phone.fill")
                    : (model.isAntiDuckingEnabled ? "shield.fill" : "speaker.wave.2"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.isCallActive
                        ? (model.isAntiDuckingEnabled ? Color.green : Color.orange)
                        : (model.isAntiDuckingEnabled ? Color.green : Color.secondary))
            }

            // Middle Text Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if model.isCallActive {
                        Text(model.isTestingDucking ? "SIMULASI PANGGILAN" : "PANGGILAN AKTIF")
                            .font(.system(size: 9.5, weight: .black))
                            .foregroundStyle(model.isAntiDuckingEnabled ? Color.green : Color.orange)

                        if let app = model.activeCallAppName {
                            Text("•  \(app)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Text("DUCKING / AUDIO SAAT CALL")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.secondary)

                        Text(model.isAntiDuckingEnabled ? "•  Bypass Aktif (100%)" : "•  Normal Mac (25%)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(model.isAntiDuckingEnabled ? Color.green : Color.orange)
                    }
                }

                Text(model.isCallActive
                    ? (model.isAntiDuckingEnabled
                        ? "🛡️ Musik & video dipertahankan tetap kencang 100% (Anti-Ducking)"
                        : "🔉 Musik & video otomatis mengecil ke 25% agar suara telepon jelas")
                    : (model.isAntiDuckingEnabled
                        ? "Saat ada telepon, volume musik/video tidak akan mengecil"
                        : "Saat ada telepon, volume musik/video akan mengecil otomatis"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right Action Controls
            HStack(spacing: 6) {
                // Test Ducking Simulation Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.toggleTestDucking()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: model.isTestingDucking ? "stop.fill" : "play.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(model.isTestingDucking ? "Stop Test" : "Test")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(model.isTestingDucking ? Color.red.opacity(0.15) : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(model.isTestingDucking ? Color.red : Color.primary)
                }
                .buttonStyle(.plain)
                .help("Uji coba efek ducking suara saat panggilan langsung pada musik yang sedang diputar")

                // Mode Switch Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.toggleAntiDucking()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: model.isAntiDuckingEnabled ? "arrow.down.right" : "shield.fill")
                            .font(.system(size: 9.5, weight: .bold))
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
                    ? "Ganti ke mode normal: musik akan mengecil saat ada telepon"
                    : "Ganti ke mode bypass: musik akan tetap kencang 100% saat ada telepon")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            model.isCallActive
                ? (model.isAntiDuckingEnabled ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
                : (model.isAntiDuckingEnabled ? Color.green.opacity(0.04) : Color.primary.opacity(0.02))
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

