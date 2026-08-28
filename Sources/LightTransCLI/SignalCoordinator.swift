import Foundation
import Darwin

actor CancellationRelay {
    private var task: Task<TranslationRunResult, Never>?
    private var pendingCancel = false

    func setTask(_ task: Task<TranslationRunResult, Never>) {
        self.task = task
        if pendingCancel {
            task.cancel()
            pendingCancel = false
        }
    }

    func cancel() {
        if let task {
            task.cancel()
            return
        }
        pendingCancel = true
    }
}

final class SignalCoordinator {
    private let relay: CancellationRelay
    private let lock = NSLock()
    private var source: DispatchSourceSignal?
    private var receivedInterrupt = false

    init(relay: CancellationRelay) {
        self.relay = relay
    }

    func start() {
        signal(SIGINT, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard !self.receivedInterrupt else {
                self.lock.unlock()
                return
            }
            self.receivedInterrupt = true
            self.lock.unlock()
            Task {
                await self.relay.cancel()
            }
        }
        self.source = source
        source.resume()
    }

    var didReceiveInterrupt: Bool {
        lock.lock()
        defer { lock.unlock() }
        return receivedInterrupt
    }
}
