import Foundation

@objc public class TSTimerService: NSObject {

    private var timers: [String: Timer] = [:]
    private let lock = NSLock()

    @objc public func scheduleTimer(
        _ id: String,
        interval: TimeInterval,
        repeats: Bool,
        block: @escaping () -> Void
    ) {
        lock.lock()
        timers[id]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            block()
        }
        timers[id] = timer
        lock.unlock()
    }

    @objc public func cancelTimer(_ id: String) {
        lock.lock()
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
        lock.unlock()
    }

    @objc public func cancelAllTimers() {
        lock.lock()
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        lock.unlock()
    }

    @objc public func hasTimer(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return timers[id]?.isValid ?? false
    }

    @objc public func isRunning(_ id: String) -> Bool {
        return hasTimer(id)
    }
}
