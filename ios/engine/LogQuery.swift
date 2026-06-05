import Foundation

@objc public class LogQuery: SQLQuery {

    @objc public override init() {
        super.init()
        self.order = 1
        self.limit = -1
    }
}
