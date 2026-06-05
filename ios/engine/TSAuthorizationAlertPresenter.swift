import Foundation
import UIKit

@objc public class TSAuthorizationAlertPresenter: NSObject {

    @objc public var authorization: TSAuthorization?
    @objc public var alertController: UIAlertController?

    @objc public init(authorization: TSAuthorization) {
        self.authorization = authorization
        super.init()
    }

    @objc public var isAlertVisible: Bool {
        return alertController != nil && alertController?.view.window != nil
    }

    @objc public func getAlertController(withCancelHandler handler: (() -> Void)?) -> UIAlertController {
        let alert = UIAlertController(
            title: "Location Authorization",
            message: "This app requires location access. Please enable it in Settings.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            handler?()
        })
        return alert
    }

    @objc public func dismissAlert() {
        alertController?.dismiss(animated: true)
        alertController = nil
    }
}
