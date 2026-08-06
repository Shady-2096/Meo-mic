import Foundation

/// Meo Mic does not bundle or redistribute BlackHole. BlackHole is
/// GPL-3.0 software by Existential Audio, and the installer package on
/// existential.audio is theirs. This type mirrors what `vbcable.py` does on
/// Windows:
///
///   1. downloads the official installer package straight from
///      existential.audio,
///   2. verifies Apple's signature on it and checks that Gatekeeper accepts
///      it, refusing to continue if either check fails,
///   3. launches Existential Audio's own installer unmodified, so the user
///      accepts their terms in their own installer and macOS asks for the
///      administrator password rather than Meo Mic asking for it.
///
/// Nothing here installs anything silently, and Meo Mic never handles the
/// user's password.
public enum BlackHoleInstaller {

    /// Shown to the user, and the fallback when the guided install cannot run.
    public static let downloadPageURL = URL(string: "https://existential.audio/blackhole/")!
    public static let licenseURL = URL(string: "https://github.com/ExistentialAudio/BlackHole")!

    /// Official package URLs, newest first. Existential Audio publishes each
    /// release under a versioned filename and keeps older ones online, so
    /// trying newest-first lands on the current release without us having to
    /// chase the version number.
    static let versions = ["0.7.1", "0.7.0", "0.6.1", "0.6.0"]

    /// Certificate subject fragment we require on the package. Fails closed:
    /// we are about to hand this package to macOS Installer, so an unexpected
    /// publisher aborts the install instead of warning about it.
    static let acceptedSigner = "existential audio"

    static let downloadTimeout: TimeInterval = 30
    /// Sanity cap. The real package is around 100 KB.
    static let maxDownloadBytes = 16 * 1024 * 1024
    static let minDownloadBytes = 16 * 1024

    // MARK: - Detection

    public struct Status: Sendable {
        /// Name of the BlackHole output device, when macOS can see one.
        public let deviceName: String?

        public var isInstalled: Bool { deviceName != nil }
    }

    public static func detect() -> Status {
        let device = AudioDevices.outputDevices().first {
            $0.name.lowercased().contains("blackhole")
        }
        return Status(deviceName: device?.name)
    }

    // MARK: - Errors

    public struct InstallError: LocalizedError {
        public let message: String
        /// False when retrying cannot help, so the UI can offer the manual
        /// steps instead of a pointless "Try again".
        public let canRetry: Bool

        public init(_ message: String, canRetry: Bool = true) {
            self.message = message
            self.canRetry = canRetry
        }

        public var errorDescription: String? { message }
    }

    // MARK: - Install

    /// Message plus a 0...1 fraction, or nil when the step is indeterminate.
    public typealias Progress = @Sendable (String, Double?) -> Void

    /// Downloads, verifies and runs Existential Audio's BlackHole installer.
    ///
    /// Returns once the installer has quit and the new device has appeared.
    /// Cancelling the surrounding task stops the download, but never
    /// interrupts the installer itself — killing an audio driver install
    /// halfway leaves the machine worse off than letting it finish.
    public static func install(progress: @escaping Progress) async throws -> Status {
        let workDirectory = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        )
        .appendingPathComponent("meomic-blackhole-\(UUID().uuidString)", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: workDirectory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        progress("Contacting existential.audio…", nil)
        let packageURL = try await download(into: workDirectory, progress: progress)

        try Task.checkCancellation()

        progress("Verifying Existential Audio's signature…", nil)
        try await verify(packageURL)

        try Task.checkCancellation()

        progress("Waiting for the macOS installer…", nil)
        try await launchInstaller(packageURL)

        progress("Checking for the new audio device…", nil)
        let status = try await waitForDevice()

        return status
    }

    // MARK: - Download

    static func packageURL(version: String) -> URL {
        URL(string: "https://existential.audio/downloads/BlackHole2ch-\(version).pkg")!
    }

    private static func download(
        into directory: URL,
        progress: @escaping Progress
    ) async throws -> URL {
        var lastError: String = "unknown error"

        for version in versions {
            do {
                let destination = directory.appendingPathComponent(
                    "BlackHole2ch-\(version).pkg"
                )
                try await downloadPackage(
                    from: packageURL(version: version),
                    to: destination,
                    progress: progress
                )
                return destination
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as InstallError where !error.canRetry {
                throw error
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }

        throw InstallError(
            """
            Could not download BlackHole. Check your internet connection, or \
            install it manually from existential.audio.
            (\(lastError))
            """
        )
    }

    private static func downloadPackage(
        from url: URL,
        to destination: URL,
        progress: @escaping Progress
    ) async throws {
        var request = URLRequest(url: url, timeoutInterval: downloadTimeout)
        request.setValue(
            "Meo-Mic/1.0 (+https://github.com/Shady-2096/Meo-mic)",
            forHTTPHeaderField: "User-Agent"
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError("Server returned HTTP \(http.statusCode).")
        }

        let expected = response.expectedContentLength
        if expected > Int64(maxDownloadBytes) {
            throw InstallError("The download is unexpectedly large; aborting.")
        }

        var data = Data()
        data.reserveCapacity(expected > 0 ? Int(expected) : 128 * 1024)

        for try await byte in bytes {
            data.append(byte)
            if data.count > maxDownloadBytes {
                throw InstallError("The download is unexpectedly large; aborting.")
            }
            if data.count % (16 * 1024) == 0 {
                let fraction = expected > 0 ? Double(data.count) / Double(expected) : nil
                progress("Downloading BlackHole… \(data.count / 1024) KB", fraction)
                try Task.checkCancellation()
            }
        }

        guard data.count >= minDownloadBytes else {
            throw InstallError("The downloaded package is too small to be valid.")
        }

        try data.write(to: destination)
    }

    // MARK: - Verification

    /// Fails closed. Both checks must pass: Apple's own signature check on the
    /// package, and Gatekeeper's assessment (which also covers notarization).
    private static func verify(_ package: URL) async throws {
        let signature = try await run("/usr/sbin/pkgutil", ["--check-signature", package.path])
        guard signature.status == 0 else {
            throw InstallError(
                """
                The downloaded package has no valid signature, so Meo Mic will \
                not run it. Install BlackHole manually instead.
                """
            )
        }
        guard signatureIsAcceptable(signature.output) else {
            throw InstallError(
                """
                The downloaded package is not signed by Existential Audio. \
                Aborting for safety — install BlackHole manually instead.
                """
            )
        }

        let assessment = try await run(
            "/usr/sbin/spctl", ["--assess", "--type", "install", "-vv", package.path]
        )
        guard assessment.status == 0, gatekeeperAccepted(assessment.output) else {
            throw InstallError(
                """
                macOS did not accept the downloaded package (it may not be \
                notarized). Aborting for safety — install BlackHole manually \
                instead.
                """
            )
        }
    }

    /// True when `pkgutil --check-signature` reports an Apple-trusted
    /// certificate chain that belongs to Existential Audio.
    static func signatureIsAcceptable(_ output: String) -> Bool {
        let lowered = output.lowercased()

        let trusted = lowered.contains("signed by a developer certificate issued by apple")
            || lowered.contains("signed by a certificate trusted by")
        guard trusted else { return false }

        guard !lowered.contains("no signature"),
              !lowered.contains("untrusted"),
              !lowered.contains("signed by untrusted certificate")
        else {
            return false
        }

        return lowered.contains(acceptedSigner)
    }

    /// True when `spctl --assess --type install` accepted the package.
    static func gatekeeperAccepted(_ output: String) -> Bool {
        let lowered = output.lowercased()
        guard !lowered.contains("rejected") else { return false }
        return lowered.contains("accepted")
    }

    // MARK: - Running the vendor's installer

    private static func launchInstaller(_ package: URL) async throws {
        // `open -W` hands the package to Installer.app and waits for it to
        // quit. Installer is the one that asks for the administrator
        // password — Meo Mic never sees it.
        let result = try await run("/usr/bin/open", ["-W", package.path])
        guard result.status == 0 else {
            throw InstallError(
                "Could not open the BlackHole installer (exit code \(result.status))."
            )
        }
    }

    private static func waitForDevice() async throws -> Status {
        // coreaudiod needs a moment to pick up a freshly installed driver.
        for _ in 0..<20 {
            let status = detect()
            if status.isInstalled { return status }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw InstallError(
            """
            The installer finished but BlackHole did not appear. It may have \
            been cancelled — try again, or install it manually from \
            existential.audio.
            """
        )
    }

    // MARK: - Process helper

    private struct ProcessResult {
        let status: Int32
        let output: String
    }

    /// Runs a command on a background thread and returns its combined output.
    /// Never blocks a cooperative thread: `open -W` can sit there for as long
    /// as the user takes to work through the installer.
    private static func run(_ path: String, _ arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        throwing: InstallError(
                            "Could not run \(path): \(error.localizedDescription)"
                        )
                    )
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(
                    returning: ProcessResult(
                        status: process.terminationStatus,
                        output: String(decoding: data, as: UTF8.self)
                    )
                )
            }
        }
    }
}
