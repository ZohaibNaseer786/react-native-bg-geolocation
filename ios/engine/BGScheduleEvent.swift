import Foundation

@objc public final class BGScheduleEvent: NSObject {

    @objc public private(set) var schedule: BGSchedule?
    @objc public private(set) var state: Any?

    @objc public init(schedule: BGSchedule?, state: Any?) {
        self.schedule = schedule
        self.state = state
        super.init()
    }
}
