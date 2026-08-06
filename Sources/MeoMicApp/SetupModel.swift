import Foundation
import MeoMicCore

@MainActor
final class SetupModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case working(message: String, fraction: Double?)
        case failed(message: String, canRetry: Bool)
        case finished(deviceName: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var showsManualSteps = false

    private var task: Task<Void, Never>?

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    func install(then onFinish: @escaping () -> Void) {
        guard !isWorking else { return }
        phase = .working(message: "Starting…", fraction: nil)

        let report: BlackHoleInstaller.Progress = { [weak self] message, fraction in
            Task { @MainActor in
                guard let self, self.isWorking else { return }
                self.phase = .working(message: message, fraction: fraction)
            }
        }

        task = Task { [weak self] in
            do {
                let status = try await BlackHoleInstaller.install(progress: report)
                guard !Task.isCancelled else { return }
                self?.phase = .finished(deviceName: status.deviceName ?? "BlackHole 2ch")
                onFinish()
            } catch is CancellationError {
                self?.phase = .idle
            } catch let error as BlackHoleInstaller.InstallError {
                self?.phase = .failed(message: error.message, canRetry: error.canRetry)
                self?.showsManualSteps = true
            } catch {
                self?.phase = .failed(message: error.localizedDescription, canRetry: true)
                self?.showsManualSteps = true
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }
}
