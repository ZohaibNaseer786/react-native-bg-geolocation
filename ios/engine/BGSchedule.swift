import Foundation

@objc public final class BGSchedule: NSObject {

    @objc public var days: NSMutableArray
    @objc public private(set) var isLiteralDate: Bool = false
    private var hasTriggered: Bool = false
    private var datePattern: String
    private var calendar: NSCalendar
    @objc public var triggered: Bool = false
    @objc public var onTime: NSDateComponents?
    @objc public var onDate: Date?
    @objc public var offTime: NSDateComponents?
    @objc public var offDate: Date?
    @objc public var trackingMode: Int = 1
    @objc public var handlerBlock: (() -> Void)?

    @objc public init(record: String) {
        self.days = NSMutableArray()
        self.triggered = false
        self.hasTriggered = false
        self.trackingMode = 1
        self.datePattern = "^\\d{4}-\\d{2}-\\d{2}.*"

        let cal = NSCalendar(calendarIdentifier: .gregorian)!
        cal.locale = Locale(identifier: "en_US")
        cal.timeZone = NSTimeZone.local
        self.calendar = cal

        let onComponents = NSDateComponents()
        let offComponents = NSDateComponents()
        self.onTime = onComponents
        self.offTime = offComponents

        super.init()

        let parts = NSMutableArray(array: record.components(separatedBy: " "))
        guard parts.count > 0, let part0 = parts.object(at: 0) as? String else { return }

        if part0.contains("-") {
            let isDate = part0.range(of: datePattern, options: .regularExpression) != nil
            if isDate {
                isLiteralDate = true
                let dateComponents = part0.components(separatedBy: "-")
                onComponents.year = Int(dateComponents[0]) ?? 0
                onComponents.month = Int(dateComponents[1]) ?? 0
                onComponents.day = Int(dateComponents[2]) ?? 0

                if parts.count > 1, let part1 = parts.object(at: 1) as? String {
                    if part1.range(of: datePattern, options: .regularExpression) != nil {
                        offComponents.year = onComponents.year
                        offComponents.month = onComponents.month
                        offComponents.day = onComponents.day
                    } else {
                        let off = part1.components(separatedBy: "-")
                        offComponents.year = Int(off[0]) ?? 0
                        offComponents.month = Int(off[1]) ?? 0
                        offComponents.day = Int(off[2]) ?? 0
                        if dateComponents.count > 3 && off.count > 3 {
                            parts[1] = String(format: "%@-%@", dateComponents[3], off[3])
                        }
                    }
                }
            } else {
                // Numeric day range "from-to".
                let range = part0.components(separatedBy: "-")
                let from = Int(range[0]) ?? 0
                let to = Int(range[1]) ?? 0
                if from <= to {
                    for day in from...to {
                        days.add(NSNumber(value: day))
                    }
                }
            }
        } else {
            // Comma-separated day list.
            for dayStr in part0.components(separatedBy: ",") {
                days.add(NSNumber(value: Int(dayStr) ?? 0))
            }
        }

        // Parse time window from parts[1] ("HH:MM-HH:MM").
        if parts.count > 1, let part1 = parts.object(at: 1) as? String {
            let timeRange = part1.components(separatedBy: "-")
            if timeRange.count >= 2 {
                let onParts = timeRange[0].components(separatedBy: ":")
                onComponents.hour = Int(onParts[0]) ?? 0
                onComponents.minute = onParts.count > 1 ? (Int(onParts[1]) ?? 0) : 0
                let offParts = timeRange[1].components(separatedBy: ":")
                offComponents.hour = Int(offParts[0]) ?? 0
                offComponents.minute = offParts.count > 1 ? (Int(offParts[1]) ?? 0) : 0
            }
        }

        if isLiteralDate {
            onDate = calendar.date(from: onComponents as DateComponents)
            offDate = calendar.date(from: offComponents as DateComponents)
            if let onDate = onDate, let offDate = offDate,
               (offDate as NSDate).earlierDate(onDate) == offDate {
                let oneDay = NSDateComponents()
                oneDay.day = 1
                self.offDate = calendar.date(byAdding: oneDay as DateComponents, to: offDate, options: [])
            }
        }

        if parts.count >= 3, let part2 = parts.object(at: 2) as? String {
            if part2.contains("geofence") {
                trackingMode = 0
            }
        }
    }

    @objc public func evaluate() -> Date {
        let now = Date()
        if triggered {
            if (now as NSDate).laterDate(offDate ?? now) == now {
                trigger(false)
            }
        } else {
            if let onDate = onDate, (now as NSDate).laterDate(onDate) == now {
                let withinWindow = (now as NSDate).earlierDate(offDate ?? now) == now
                trigger(withinWindow)
            }
        }
        return now
    }

    @objc public func trigger(_ state: Bool) {
        if hasTriggered && triggered == state {
            return
        }
        let logger = BGLog.sharedInstance()
        if state {
            if logger.shouldLog(5) {
                let message = String(format: "%@", description)
                logger.log(5, tag: 3, function: "-[BGSchedule trigger:]", message: message)
            }
        } else {
            if logger.shouldLog(3) {
                let message = String(format: "%@", description)
                logger.log(3, tag: 5, function: "-[BGSchedule trigger:]", message: message)
            }
        }
        hasTriggered = true
        triggered = state

        let state = BGConfig.sharedInstance().toDictionary()
        let event = BGScheduleEvent(schedule: self, state: state)
        BGEventBus.sharedInstance().trigger(BGEventNameSchedule, payload: event)
        BGEventManager.sharedInstance().trigger(BGEventNameSchedule, payload: event)
    }

    @objc public func make(_ components: NSDateComponents) {
        guard !isLiteralDate else { return }
        onTime?.year = components.year
        onTime?.month = components.month
        onTime?.day = components.day
        onDate = calendar.date(from: (onTime ?? NSDateComponents()) as DateComponents)

        offTime?.year = components.year
        offTime?.month = components.month
        offTime?.day = components.day
        offDate = calendar.date(from: (offTime ?? NSDateComponents()) as DateComponents)

        if let onDate = onDate, let offDate = offDate,
           (offDate as NSDate).earlierDate(onDate) == offDate {
            let oneDay = NSDateComponents()
            oneDay.day = 1
            self.offDate = calendar.date(byAdding: oneDay as DateComponents, to: offDate, options: [])
        }
    }

    @objc public func isNext(_ date: Date) -> Bool {
        let comps = calendar.components([.year, .month, .day, .hour, .minute, .weekday], from: date)
        if !isLiteralDate {
            make(comps as NSDateComponents)
            if !hasDay(comps.weekday ?? 0) {
                return false
            }
        }
        guard let offDate = offDate else { return false }
        return (date as NSDate).earlierDate(offDate) == date
    }

    @objc public func reset() {
        hasTriggered = false
    }

    @objc public func expired() -> Bool {
        let now = Date()
        guard let offDate = offDate else { return false }
        return (now as NSDate).laterDate(offDate) == now
    }

    @objc public func startsBefore(_ date: Date) -> Bool {
        guard let onDate = onDate else { return false }
        return (onDate as NSDate).earlierDate(date) == onDate
    }

    @objc public func startsAfter(_ date: Date) -> Bool {
        guard let onDate = onDate else { return false }
        return (onDate as NSDate).earlierDate(date) == date
    }

    @objc public func endsBefore(_ date: Date) -> Bool {
        guard let offDate = offDate else { return false }
        return (offDate as NSDate).earlierDate(date) == offDate
    }

    @objc public func endsAfter(_ date: Date) -> Bool {
        guard let offDate = offDate else { return false }
        return (offDate as NSDate).earlierDate(date) == date
    }

    @objc public func hasDay(_ weekday: Int) -> Bool {
        return days.contains(NSNumber(value: weekday))
    }

    public override var description: String {
        let onHour = onTime?.hour ?? 0
        let onMinute = onTime?.minute ?? 0
        let offHour = offTime?.hour ?? 0
        let offMinute = offTime?.minute ?? 0
        let daysString = days.componentsJoined(by: ",")
        return String(format: "BGSchedule[triggered:%d, %02ld:%02ld - %02ld:%02ld, Days:%@, trackingMode:%d]",
                      triggered, onHour, onMinute, offHour, offMinute, daysString, trackingMode)
    }
}
