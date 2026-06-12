import Foundation

@objc public class BGPropertySpecImpl: NSObject {
    @objc public let name: String
    @objc public let type: String
    @objc public init(name: String, type: String) {
        self.name = name
        self.type = type
        super.init()
    }
}

public func BGPropertySpec(name: String, type: String) -> BGPropertySpecImpl {
    return BGPropertySpecImpl(name: name, type: type)
}

@objc public class BGConfigModuleBase: NSObject {

    @objc public var trackExplicitKeys: Bool = false
    private var explicitKeys: Set<String> = []
    private var changeObservers: [String: [AnyObject]] = [:]

    @objc public override class func automaticallyNotifiesObservers(forKey key: String) -> Bool {
        return false
    }

    @objc public override init() {
        super.init()
        applyDefaults()
    }

    @objc public func applyDefaults() {}

    @objc public func propertySpecs() -> [BGPropertySpecImpl] { return [] }

    @objc public func allPropertyNames() -> [String] {
        return propertySpecs().map { $0.name }
    }

    @objc public func hasProperty(_ name: String) -> Bool {
        return allPropertyNames().contains(name)
    }

    @objc public func canHandleProperty(_ name: String) -> Bool {
        return hasProperty(name)
    }

    @objc public func sensitivePropertyNames() -> [String] {
        return []
    }

    @objc public func deprecatedPropertyMappings() -> [String: String] {
        return [:]
    }

    @objc public func currentPropertyName(forDeprecated deprecated: String) -> String? {
        return deprecatedPropertyMappings()[deprecated]
    }

    @objc public func markExplicitKey(_ key: String) {
        explicitKeys.insert(key)
    }

    @objc public func clearExplicitKeys() {
        explicitKeys.removeAll()
    }

    @objc public func wasExplicitlySet(_ key: String) -> Bool {
        return explicitKeys.contains(key)
    }

    @objc public func userConfigured() -> [String: Any] {
        var result: [String: Any] = [:]
        for key in explicitKeys {
            if let val = value(forKey: key) {
                result[key] = val
            }
        }
        return result
    }

    @objc public func updateWithDictionary(_ dict: [String: Any]) {
        for (key, value) in dict {
            let targetKey = currentPropertyName(forDeprecated: key) ?? key
            if canHandleProperty(targetKey) {
                setValue(value, forProperty: targetKey)
                if trackExplicitKeys { markExplicitKey(targetKey) }
            }
        }
    }

    @objc public func setValue(_ value: Any?, forProperty key: String) {
        let coerced = defaultCoerce(value, forKey: key)
        let old = self.value(forKey: key)
        willChangeValue(forKey: key)
        primitiveWriteValue(coerced, forKey: key)
        didChangeValue(forKey: key)
        propertyDidChange(key, oldValue: old, newValue: coerced)
    }

    @objc public override func setValue(_ value: Any?, forKey key: String) {
        if canHandleProperty(key) {
            setValue(value, forProperty: key)
        } else {
            super.setValue(value, forKey: key)
        }
    }

    @objc public override func setValue(_ value: Any?, forUndefinedKey key: String) {
    }

    @objc public func primitiveWriteValue(_ value: Any?, forKey key: String) {
        super.setValue(value, forKey: key)
    }

    @objc public func defaultCoerce(_ value: Any?, forKey key: String) -> Any? {
        return value
    }

    @objc public func valueForProperty(_ key: String) -> Any? {
        return value(forKey: key)
    }

    @objc public func validateValue(_ value: Any?, forKey key: String) -> Bool {
        return true
    }

    @objc public func isValue(_ a: Any?, equalTo b: Any?) -> Bool {
        if let a = a as? NSObject, let b = b as? NSObject {
            return a.isEqual(b)
        }
        return a == nil && b == nil
    }

    @objc public func applyAndDiff(_ dict: [String: Any]) -> [String] {
        var changed: [String] = []
        for (key, newValue) in dict {
            let targetKey = currentPropertyName(forDeprecated: key) ?? key
            guard canHandleProperty(targetKey) else { continue }
            let old = value(forKey: targetKey)
            setValue(newValue, forProperty: targetKey)
            if !isValue(old, equalTo: newValue) {
                changed.append(targetKey)
            }
        }
        return changed
    }

    @objc public func resetPropertyToDefault(_ key: String) {
        applyDefaults()
    }

    @objc public func propertyDidChange(_ key: String, oldValue: Any?, newValue: Any?) {}

    @objc public func contributeDeprecatedProperties(_ dict: NSMutableDictionary, redact: Bool) {}

    @objc public func redactedValue(forProperty name: String, originalValue: Any?) -> Any? {
        if sensitivePropertyNames().contains(name) { return "**redacted**" }
        return originalValue
    }

    @objc public func toDictionary() -> [String: Any] {
        return toDictionary(false)
    }

    @objc public func toDictionary(_ redact: Bool) -> [String: Any] {
        var dict: [String: Any] = [:]
        for spec in propertySpecs() {
            let val = value(forKey: spec.name)
            dict[spec.name] = redact ? redactedValue(forProperty: spec.name, originalValue: val) : val
        }
        return dict
    }

    @objc public func validateConfiguration() -> Bool { return true }

    @objc public override var description: String {
        return "<\(type(of: self)) \(toDictionary())>"
    }
}
