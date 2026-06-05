import Foundation

@objc public final class TSScheduleEvent: NSObject {

    @objc public private(set) var schedule: TSSchedule?
    @objc public private(set) var state: Any?

    @objc public init(schedule: TSSchedule?, state: Any?) {
        self.schedule = schedule
        self.state = state
        super.init()
    }
}
