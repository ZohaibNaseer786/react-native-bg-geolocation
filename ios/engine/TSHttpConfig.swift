import Foundation

@objc public class TSHttpConfig: TSConfigModuleBase {

    @objc public var url: String = ""
    @objc public var method: String = "POST"
    @objc public var headers: [String: String] = [:]
    @objc public var params: [String: Any] = [:]
    @objc public var rootProperty: String = "location"
    @objc public var timeout: Double = 60.0
    @objc public var autoSync: Bool = true
    @objc public var autoSyncThreshold: Int = 0
    @objc public var batchSync: Bool = false
    @objc public var maxBatchSize: Int = -1
    @objc public var disableAutoSyncOnCellular: Bool = false

    @objc public override func applyDefaults() {
        url = ""
        method = "POST"
        headers = [:]
        params = [:]
        rootProperty = "location"
        timeout = 60.0
        autoSync = true
        autoSyncThreshold = 0
        batchSync = false
        maxBatchSize = -1
        disableAutoSyncOnCellular = false
    }

    @objc public var hasValidUrl: Bool {
        return !url.isEmpty && URL(string: url) != nil
    }

    @objc public var timeoutSeconds: TimeInterval {
        return timeout
    }

    @objc public var effectiveBatchSize: Int {
        return maxBatchSize > 0 ? maxBatchSize : 50
    }

    @objc public var isImmediateSyncEnabled: Bool {
        return autoSync && autoSyncThreshold == 0
    }

    @objc public func fullUrlWithParams() -> String {
        guard !url.isEmpty else { return url }
        if params.isEmpty { return url }
        var components = URLComponents(string: url)
        let queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        let existing = components?.queryItems ?? []
        components?.queryItems = existing + queryItems
        return components?.url?.absoluteString ?? url
    }

    @objc public func validateAndCleanUrl(_ rawUrl: String) -> String? {
        let trimmed = rawUrl.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return nil }
        return trimmed
    }

    @objc public func headersWithAuth(_ auth: TSAuthorization?) -> [String: String] {
        var result = headers
        if let auth = auth, let token = auth.accessToken, !token.isEmpty {
            result["Authorization"] = "Bearer \(token)"
        }
        return result
    }

    @objc public override func sensitivePropertyNames() -> [String] {
        return ["headers"]
    }

    @objc public override func deprecatedPropertyMappings() -> [String: String] {
        return [
            "httpRootProperty": "rootProperty",
            "httpTimeout": "timeout"
        ]
    }

    @objc public override func propertySpecs() -> [TSPropertySpecImpl] {
        return [
            TSPropertySpec(name: "url", type: "string"),
            TSPropertySpec(name: "method", type: "string"),
            TSPropertySpec(name: "headers", type: "object"),
            TSPropertySpec(name: "params", type: "object"),
            TSPropertySpec(name: "rootProperty", type: "string"),
            TSPropertySpec(name: "timeout", type: "double"),
            TSPropertySpec(name: "autoSync", type: "bool"),
            TSPropertySpec(name: "autoSyncThreshold", type: "int"),
            TSPropertySpec(name: "batchSync", type: "bool"),
            TSPropertySpec(name: "maxBatchSize", type: "int"),
            TSPropertySpec(name: "disableAutoSyncOnCellular", type: "bool")
        ]
    }

    @objc public override func validateConfiguration() -> Bool {
        return true
    }

    @objc public override var description: String {
        return "<TSHttpConfig url=\(url) method=\(method) autoSync=\(autoSync)>"
    }
}
