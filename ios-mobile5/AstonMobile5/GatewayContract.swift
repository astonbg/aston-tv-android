import Foundation

enum GatewayContract {
    // Matches on(x) in the deployed Gateway's app.js.
    static func isEnabled(_ value: Any?) -> Bool {
        if let string = value as? String { return string == "1" || string == "true" }
        if let number = value as? NSNumber { return number == 1 }
        return false
    }
}
