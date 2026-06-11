import Foundation

@objc public class BGPropertySpecObject: NSObject {

    @objc public var name: String
    @objc public var type: String
    @objc public var defaultValue: Any?
    @objc public var isOptional: Bool = true
    @objc public var isPrivate: Bool = false

    @objc public init(name: String, type: String, defaultValue: Any? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        super.init()
    }

    @objc public func setValue(_ value: Any?, onObject obj: AnyObject, validate: Bool) {
        obj.setValue(value, forKey: name)
    }

    @objc public func getValue(fromObject obj: AnyObject) -> Any? {
        return obj.value(forKey: name)
    }

    @objc public override var description: String {
        return "<BGPropertySpec name=\(name) type=\(type)>"
    }
}
