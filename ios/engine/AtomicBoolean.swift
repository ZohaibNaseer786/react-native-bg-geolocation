import Foundation

@objc public final class AtomicBoolean: NSObject {

    private var _value: Bool = false
    private var _lock = os_unfair_lock_s()

    @objc public override init() {
        super.init()
        setValue(false)
    }

    @objc public init(value: Bool) {
        super.init()
        _value = value
    }

    @objc public func getValue() -> Bool {
        os_unfair_lock_lock(&_lock)
        let v = _value
        os_unfair_lock_unlock(&_lock)
        return v
    }

    @objc public func setValue(_ value: Bool) {
        os_unfair_lock_lock(&_lock)
        _value = value
        os_unfair_lock_unlock(&_lock)
    }

    @objc public func compareTo(_ expected: Bool, andSetValue newValue: Bool) -> Bool {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        if _value == expected {
            _value = newValue
            return true
        }
        return false
    }

    @objc public func getAndSetValue(_ newValue: Bool) -> Bool {
        os_unfair_lock_lock(&_lock)
        let old = _value
        _value = newValue
        os_unfair_lock_unlock(&_lock)
        return old
    }
}
