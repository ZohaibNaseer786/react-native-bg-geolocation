import Foundation

@objc public class TSTemplate: NSObject {

    @objc public var name: String
    @objc public var content: [String: Any]

    @objc public init(name: String, content: [String: Any]) {
        self.name = name
        self.content = content
        super.init()
    }

    @objc public override init() {
        name = ""
        content = [:]
        super.init()
    }

    @objc public func render(with data: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in content {
            if let strVal = value as? String {
                result[key] = interpolate(strVal, with: data)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private func interpolate(_ template: String, with data: [String: Any]) -> String {
        var result = template
        let pattern = "<%=\\s*(.+?)\\s*%>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return template }
        let range = NSRange(template.startIndex..., in: template)
        let matches = regex.matches(in: template, range: range)
        for match in matches.reversed() {
            if let keyRange = Range(match.range(at: 1), in: template) {
                let key = String(template[keyRange])
                if let val = data[key] {
                    if let matchRange = Range(match.range, in: result) {
                        result.replaceSubrange(matchRange, with: "\(val)")
                    }
                }
            }
        }
        return result
    }

    @objc public override var description: String {
        return "<TSTemplate name=\(name)>"
    }
}
