import Foundation

@objc public class TSScheduler: NSObject {

    private static var _sharedInstance: TSScheduler?
    private static let lock = NSLock()

    private var scheduleRules: [TSScheduleRule] = []
    private var timer: Timer?
    private var enabled: Bool = false

    @objc public class func sharedInstance() -> TSScheduler {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSScheduler()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
    }

    @objc public func start(withSchedule schedule: [String]) -> Bool {
        stop()
        scheduleRules = schedule.compactMap { TSScheduleRule(rule: $0) }
        guard !scheduleRules.isEmpty else { return false }
        enabled = true
        startTimer()
        return true
    }

    @objc public func stop() {
        timer?.invalidate()
        timer = nil
        enabled = false
    }

    @objc public func isEnabled() -> Bool {
        return enabled
    }

    @objc public func isTracking() -> Bool {
        guard enabled else { return false }
        let now = Date()
        return scheduleRules.contains { $0.isActiveAt(now) }
    }

    @objc public func nextScheduledDate() -> Date? {
        let now = Date()
        return scheduleRules.compactMap { $0.nextTriggerDate(after: now) }.min()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(timeInterval: 60.0,
                                     target: self,
                                     selector: #selector(evaluate),
                                     userInfo: nil,
                                     repeats: true)
    }

    @objc private func evaluate() {
        let tracking = isTracking()
        NotificationCenter.default.post(
            name: NSNotification.Name("TSSchedulerEvaluated"),
            object: self,
            userInfo: ["tracking": tracking]
        )
    }
}

private class TSScheduleRule {
    let raw: String
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    let weekdays: [Int]

    init?(rule: String) {
        raw = rule
        let parts = rule.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let timePart = parts[0].components(separatedBy: "-")
        guard timePart.count == 2 else { return nil }
        let startParts = timePart[0].components(separatedBy: ":")
        let endParts = timePart[1].components(separatedBy: ":")
        guard startParts.count == 2, endParts.count == 2 else { return nil }
        startHour = Int(startParts[0]) ?? 0
        startMinute = Int(startParts[1]) ?? 0
        endHour = Int(endParts[0]) ?? 0
        endMinute = Int(endParts[1]) ?? 0
        weekdays = parts.dropFirst().compactMap { Int($0) }
    }

    func isActiveAt(_ date: Date) -> Bool {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        if !weekdays.isEmpty && !weekdays.contains(weekday) { return false }
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let current = hour * 60 + minute
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute
        if start <= end {
            return current >= start && current < end
        } else {
            return current >= start || current < end
        }
    }

    func nextTriggerDate(after date: Date) -> Date? {
        return nil
    }
}
