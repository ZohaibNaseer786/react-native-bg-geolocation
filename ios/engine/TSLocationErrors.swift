import Foundation

public let TSLocationErrorDomain = "TSLocationManager"

private let TSLocationErrorMessages: [Int: String] = [
    0: "Location unknown",
    100: "Location did not meet desired accuracy.",
    404: "No location available.",
    408: "Timed out.",
    499: "Request was cancelled",
    503: "Service unavailable"
]

public func TSLocationErrorMessage(_ code: Int) -> String {
    return TSLocationErrorMessages[code] ?? "Location error."
}

public func TSMakeLocationError(_ code: Int) -> NSError {
    return NSError(domain: TSLocationErrorDomain,
                   code: code,
                   userInfo: [NSLocalizedDescriptionKey: TSLocationErrorMessage(code)])
}

public func TSMakeError(_ domain: String, _ code: Int) -> NSError {
    return NSError(domain: domain,
                   code: code,
                   userInfo: [NSLocalizedDescriptionKey: TSLocationErrorMessage(code)])
}
