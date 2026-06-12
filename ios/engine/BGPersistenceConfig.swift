import Foundation

@objc public class BGPersistenceConfig: BGConfigModuleBase {

    @objc public var maxDaysToPersist: Int = 1
    @objc public var maxRecordsToPersist: Int = -1
    @objc public var persistMode: Int = 2
    @objc public var locationsOrderDirection: String = "ASC"

    @objc public override func applyDefaults() {
        maxDaysToPersist = 1
        maxRecordsToPersist = -1
        persistMode = 2
        locationsOrderDirection = "ASC"
    }

    @objc public override func propertySpecs() -> [BGPropertySpecImpl] {
        return [
            BGPropertySpec(name: "maxDaysToPersist", type: "int"),
            BGPropertySpec(name: "maxRecordsToPersist", type: "int"),
            BGPropertySpec(name: "persistMode", type: "int"),
            BGPropertySpec(name: "locationsOrderDirection", type: "string")
        ]
    }

    @objc public override var description: String {
        return "<BGPersistenceConfig maxDaysToPersist=\(maxDaysToPersist) maxRecordsToPersist=\(maxRecordsToPersist)>"
    }
}
