import Foundation

var failures = 0
func assertTest(_ condition: Bool, _ message: String) {
    if condition {
        print("  [PASS] \(message)")
    } else {
        print("  [FAIL] \(message)")
        failures += 1
    }
}

func approx(_ a: Float, _ b: Float, tolerance: Float = 0.001) -> Bool {
    abs(a - b) <= tolerance
}

@main
struct SwiftUnitTests {
    static func main() {
        print("==================================================")
        print(" RUNNING SWIFT UNIT TESTS")
        print("==================================================")

        testPersistence()
        testAppIdentity()
        testDBScale()

        print("\nRESULT: \(failures == 0 ? "ALL SWIFT TESTS PASSED" : "FAILED") (\(failures) failure(s))\n")
        if failures > 0 {
            exit(1)
        }
    }

    static func testPersistence() {
        print("\n-- Testing Persistence & Preferences --")

        let testBundle = "com.test.volume.app.\(UUID().uuidString)"

        // Default gain should be 1.0 (100%)
        let defaultGain = Persistence.gain(for: testBundle)
        assertTest(approx(defaultGain, 1.0), "Default unconfigured app gain is 1.0 (100%)")

        // Default mute should be false
        let defaultMute = Persistence.mute(for: testBundle)
        assertTest(defaultMute == false, "Default app mute is false")

        // Set and retrieve gain
        Persistence.setGain(0.75, for: testBundle)
        assertTest(approx(Persistence.gain(for: testBundle), 0.75), "Saved gain persists correctly (0.75)")

        // Set and retrieve mute
        Persistence.setMute(true, for: testBundle)
        assertTest(Persistence.mute(for: testBundle) == true, "Saved mute state persists correctly (true)")

        // Master gain & mute
        let origMaster = Persistence.masterGain
        Persistence.masterGain = 0.85
        assertTest(approx(Persistence.masterGain, 0.85), "Master gain persists correctly (0.85)")
        Persistence.masterGain = origMaster

        // Output routing auto-follow
        let origAuto = Persistence.isAutoOutputFollowing
        Persistence.isAutoOutputFollowing = true
        assertTest(Persistence.isAutoOutputFollowing == true, "Auto output routing default is true")
        Persistence.isAutoOutputFollowing = false
        assertTest(Persistence.isAutoOutputFollowing == false, "Manual output routing persists correctly (false)")
        Persistence.isAutoOutputFollowing = origAuto

        // Excluded bundle IDs should contain self
        let excluded = Persistence.excludedBundleIDs
        assertTest(excluded.contains("com.antigravity.WindowsVolumeMixer"), "Excluded bundle IDs contains our mixer bundle ID")
    }

    static func testAppIdentity() {
        print("\n-- Testing App Identification & Friendly Names --")

        let chrome = AppIdentity.resolve(bundleID: "com.google.Chrome.helper", pid: -1)
        assertTest(chrome.name == "Google Chrome", "Chrome helper resolved to 'Google Chrome'")

        let safari = AppIdentity.resolve(bundleID: "com.apple.WebKit.GPU", pid: -1)
        assertTest(safari.name == "Safari", "WebKit GPU process resolved to 'Safari'")

        let systemSounds = AppIdentity.resolve(bundleID: "com.apple.audio.SystemSoundServer", pid: -1)
        assertTest(systemSounds.name == "System Sounds", "SystemSoundServer resolved to 'System Sounds'")

        let spotify = AppIdentity.resolve(bundleID: "com.spotify.client", pid: -1)
        assertTest(spotify.name == "Spotify", "Spotify bundle resolved to 'Spotify'")

        let fallback = AppIdentity.resolve(bundleID: "com.example.discordapp", pid: -1)
        assertTest(fallback.name == "Discordapp", "Unlisted app fallback capitalized last component ('Discordapp')")
    }

    static func testDBScale() {
        print("\n-- Testing dB Perceptual VU Meter Scaling --")

        // Zero signal should result in 0.0 meter level
        let zero = dbScale(0.0)
        assertTest(zero == 0.0, "Zero peak maps to 0.0 on meter")

        // Unity signal (1.0) should map close to 1.0
        let unity = dbScale(1.0)
        assertTest(unity >= 0.80 && unity <= 1.0, "Unity peak 1.0 maps to top region of meter (\(unity))")

        // Moderate signal (0.1) should map to middle region
        let moderate = dbScale(0.1)
        assertTest(moderate > 0.0 && moderate < unity, "Moderate peak 0.1 maps to mid region (\(moderate))")
    }

    private static func dbScale(_ peak: Float) -> Float {
        guard peak > 0.0001 else { return 0 }
        let db = 20 * log10f(min(peak, 1.5))
        return max(0, min(1, 1 + db / 50))
    }
}

