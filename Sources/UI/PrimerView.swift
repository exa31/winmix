import SwiftUI

/// First-run onboarding and permission guide for macOS System Audio Recording.
struct PrimerView: View {
    @ObservedObject var model: MixerModel

    var isClassic: Bool { model.isClassicTheme }

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(isClassic ? Color.accentColor.opacity(0.12) : MixerTheme.win11Blue.opacity(0.12))
                    .frame(width: 72, height: 72)

                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(isClassic ? Color.accentColor : MixerTheme.win11Blue)
            }
            .padding(.top, 8)

            // Title
            VStack(spacing: 4) {
                Text("WinMix")
                    .font(.system(size: 20, weight: .bold))

                Text("Open-Source Volume Mixer for macOS")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Explanation
            VStack(spacing: 8) {
                Text("Atur volume masing-masing aplikasi (Chrome, Spotify, Game, Safari) secara independen persis seperti di Windows.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Saat pertama kali dibuka, macOS akan meminta izin **Screen & System Audio Recording**. Klik **Allow / Izinkan** agar WinMix dapat mengalirkan dan menyeimbangkan audio. Audio diproses secara lokal (*real-time zero latency*) dan tidak pernah disimpan.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            if case .permissionNeeded = model.state {
                VStack(spacing: 4) {
                    Label("Izin Perekaman Audio Belum Diberikan", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text("Buka **System Settings > Privacy & Security > Screen & System Audio Recording**, aktifkan izin untuk **WinMix**, lalu klik tombol di bawah.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.10))
                )
                .padding(.horizontal, 16)
            }

            // Action Button
            Button(action: {
                model.startEngine()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                    Text(buttonTitle)
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 200, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(isClassic ? Color.accentColor : MixerTheme.win11Blue)
            .controlSize(.large)
            .padding(.bottom, 12)
        }
        .padding(24)
        .frame(maxWidth: 420)
    }

    private var buttonTitle: String {
        if case .permissionNeeded = model.state {
            return "Coba Lagi / Try Again"
        }
        return "Aktifkan Mixer / Enable"
    }
}

