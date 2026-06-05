import Foundation

@objc public class TSPersistenceConfig: TSConfigModuleBase {

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

    @objc public override func propertySpecs() -> [TSPropertySpecImpl] {
        return [
            TSPropertySpec(name: "maxDaysToPersist", type: "int"),
            TSPropertySpec(name: "maxRecordsToPersist", type: "int"),
            TSPropertySpec(name: "persistMode", type: "int"),
            TSPropertySpec(name: "locationsOrderDirection", type: "string")
        ]
    }

    @objc public override var description: String {
        return "<TSPersistenceConfig maxDaysToPersist=\(maxDaysToPersist) maxRecordsToPersist=\(maxRecordsToPersist)>"
    }
}
