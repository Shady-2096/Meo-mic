// Meo macOS camera-extension feasibility probe — the host application.
//
// Its only jobs are to ask macOS to install the bundled camera extension, to
// report exactly what macOS says back, and to list the cameras the system
// currently exposes. The verdict for CAMERA_BUILD_PLAN.md §18 step 2 is
// whatever this window says, not what the plan hoped it would say.

import AVFoundation
import Combine
import SwiftUI
import SystemExtensions

let extensionBundleID = "com.meo.camera.probe.extension"

// MARK: - Extension install

/// Wraps OSSystemExtensionRequest and records every callback verbatim.
///
/// The failure text is the deliverable here. "It didn't install" is not a
/// usable Milestone 0 result; `OSSystemExtensionError` code 8 with its
/// message is, because it names which of the §8.1 obstacles was hit.
final class ExtensionInstaller: NSObject, ObservableObject,
                                OSSystemExtensionRequestDelegate {
    @Published var log: [String] = []
    @Published var busy = false

    func append(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        DispatchQueue.main.async {
            self.log.append("[\(stamp)] \(line)")
            NSLog("MeoProbe: %@", line)
        }
    }

    func install() {
        busy = true
        append("Requesting activation of \(extensionBundleID)")
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func uninstall() {
        busy = true
        append("Requesting deactivation of \(extensionBundleID)")
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension new: OSSystemExtensionProperties)
        -> OSSystemExtensionRequest.ReplacementAction {
        append("Replacing existing build \(existing.bundleShortVersion) "
               + "(\(existing.bundleVersion)) with \(new.bundleShortVersion) "
               + "(\(new.bundleVersion))")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        append("NEEDS USER APPROVAL — open System Settings > General > "
               + "Login Items & Extensions and allow it.")
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            append("RESULT: completed")
        case .willCompleteAfterReboot:
            append("RESULT: will complete after reboot")
        @unknown default:
            append("RESULT: unknown (\(result.rawValue))")
        }
        DispatchQueue.main.async { self.busy = false }
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFailWithError error: Error) {
        let nsError = error as NSError
        append("FAILED: \(nsError.domain) code \(nsError.code) — "
               + nsError.localizedDescription)
        append(explain(nsError))
        DispatchQueue.main.async { self.busy = false }
    }

    /// Maps the codes §8.1 predicts onto what they mean for the plan, so the
    /// result can be transcribed into an ADR without a second research pass.
    private func explain(_ error: NSError) -> String {
        guard error.domain == OSSystemExtensionErrorDomain else {
            return "Not an OSSystemExtension error; record verbatim."
        }
        switch OSSystemExtensionError.Code(rawValue: error.code) {
        case .missingEntitlement:
            return "-> MISSING ENTITLEMENT. This is the §8.1 wall: "
                + "com.apple.developer.system-extension.install needs a "
                + "provisioning profile from a PAID Apple Developer account. "
                + "Developer mode is the only free way past it, and on this "
                + "macOS that needs SIP disabled."
        case .validationFailed:
            return "-> VALIDATION FAILED. Usually the bundle layout or the "
                + "signature. Check that the .systemextension sits in "
                + "Contents/Library/SystemExtensions and that both bundle IDs "
                + "match the prefix rule."
        case .forbiddenBySystemPolicy:
            return "-> FORBIDDEN BY SYSTEM POLICY. macOS refused outright. "
                + "Typically an unsigned or ad-hoc extension with developer "
                + "mode off."
        case .authorizationRequired:
            return "-> AUTHORIZATION REQUIRED. Approve it in System Settings, "
                + "then try again."
        case .requestSuperseded:
            return "-> Superseded by a later request; harmless."
        case .extensionNotFound:
            return "-> EXTENSION NOT FOUND. The app bundle does not actually "
                + "contain the extension, or the app is not in /Applications."
        case .unsupportedParentBundleLocation:
            return "-> UNSUPPORTED PARENT BUNDLE LOCATION. The app must live "
                + "in /Applications. Move it there and retry."
        default:
            return "-> Record this code verbatim in the results file."
        }
    }
}

// MARK: - Camera listing

/// Every device type macOS might file a virtual camera under.
///
/// The spelling of the "not built in" type changed: `.externalUnknown` up to
/// macOS 13, `.external` from 14. A camera extension normally lands there, but
/// asking for all of them means a miscategorised device still shows up instead
/// of looking like a total failure — which matters when the whole point is to
/// find out where macOS puts this thing.
func videoDeviceTypes() -> [AVCaptureDevice.DeviceType] {
    var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) {
        types.append(.external)
        types.append(.continuityCamera)
    } else {
        types.append(.externalUnknown)
    }
    return types
}

func discoverVideoDevices() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(deviceTypes: videoDeviceTypes(),
                                     mediaType: .video,
                                     position: .unspecified).devices
}

final class CameraList: ObservableObject {
    @Published var cameras: [String] = []

    func refresh() {
        cameras = discoverVideoDevices().map { device in
            "\(device.localizedName)  [\(device.deviceType.rawValue)]  "
            + "uid=\(device.uniqueID)"
        }
        if cameras.isEmpty {
            cameras = ["(no video devices found)"]
        }
    }
}

// MARK: - Preview

/// A live preview of a chosen camera, so frames can be confirmed without
/// opening Zoom first. The real §13.2 checks still have to happen in the
/// actual applications — this only proves the extension is producing frames
/// at all.
struct CameraPreview: NSViewRepresentable {
    let device: AVCaptureDevice?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        context.coordinator.session?.stopRunning()
        context.coordinator.session = nil

        guard let device,
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = nsView.bounds
        layer.videoGravity = .resizeAspect
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        nsView.layer?.addSublayer(layer)

        context.coordinator.session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var session: AVCaptureSession?
    }
}

// MARK: - UI

struct ProbeView: View {
    @StateObject private var installer = ExtensionInstaller()
    @StateObject private var cameras = CameraList()
    @State private var selectedCameraID: String?

    private var selectedDevice: AVCaptureDevice? {
        guard let selectedCameraID else { return nil }
        return AVCaptureDevice(uniqueID: selectedCameraID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Meo camera-extension probe")
                .font(.system(size: 22, weight: .semibold))
            Text("Answers CAMERA_BUILD_PLAN.md §18 step 2: can a Core Media "
                 + "I/O camera extension install and be consumed with a free "
                 + "Apple ID?")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Install extension") { installer.install() }
                    .disabled(installer.busy)
                Button("Uninstall extension") { installer.uninstall() }
                    .disabled(installer.busy)
                Button("Refresh cameras") { cameras.refresh() }
                Spacer()
                if installer.busy { ProgressView().controlSize(.small) }
            }

            GroupBox("Cameras macOS currently exposes") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(cameras.cameras, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Camera", selection: $selectedCameraID) {
                        Text("None").tag(String?.none)
                        ForEach(discoverVideoDevices(), id: \.uniqueID) { device in
                            Text(device.localizedName).tag(String?.some(device.uniqueID))
                        }
                    }
                    CameraPreview(device: selectedDevice)
                        .frame(height: 220)
                    Text("A working extension shows colour bars with a white "
                         + "line sweeping across every two seconds. Bars that "
                         + "are not moving mean frames stopped.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            GroupBox("Log — copy this into RESULTS") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(installer.log, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .frame(height: 160)
            }
        }
        .padding(20)
        .frame(width: 720)
        .onAppear { cameras.refresh() }
    }
}

// MARK: - Headless mode

/// Runs the activation request with no window and prints the outcome.
///
/// This exists so the §18 step 2 result can be captured as text — a
/// screenshot of a dialog is not something an ADR can quote, and the exact
/// `OSSystemExtensionError` code is the entire finding.
func runHeadless(uninstall: Bool) -> Never {
    let installer = ExtensionInstaller()
    var printed = 0
    var finished = false

    let cancellable = installer.$log.sink { lines in
        while printed < lines.count {
            print(lines[printed])
            printed += 1
        }
        if let last = lines.last,
           last.contains("RESULT:") || last.contains("->") {
            finished = true
        }
    }

    print("Cameras before:")
    for device in discoverVideoDevices() {
        print("  \(device.localizedName)  [\(device.deviceType.rawValue)]")
    }
    print("")

    if uninstall { installer.uninstall() } else { installer.install() }

    // Bounded wait. A request that neither succeeds nor fails is itself worth
    // reporting, so this times out loudly instead of hanging forever.
    let deadline = Date().addingTimeInterval(45)
    while !finished && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    _ = cancellable

    if !finished {
        print("[timeout] No result after 45s. If macOS is showing an approval "
              + "prompt, approve it in System Settings and run again.")
    }

    print("")
    print("Cameras after:")
    for device in discoverVideoDevices() {
        print("  \(device.localizedName)  [\(device.deviceType.rawValue)]")
    }
    exit(finished ? 0 : 2)
}

// MARK: - Entry point

if CommandLine.arguments.contains("--cli-install") {
    runHeadless(uninstall: false)
}
if CommandLine.arguments.contains("--cli-uninstall") {
    runHeadless(uninstall: true)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 720, height: 820),
    styleMask: [.titled, .closable, .miniaturizable],
    backing: .buffered,
    defer: false)
window.title = "Meo camera-extension probe"
window.center()
window.contentView = NSHostingView(rootView: ProbeView())
window.makeKeyAndOrderFront(nil)

app.activate(ignoringOtherApps: true)
app.run()
