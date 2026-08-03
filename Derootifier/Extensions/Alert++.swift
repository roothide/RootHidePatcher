//
//  Alert++.swift
//  Derootifier
//
//  Created by Анохин Юрий on 15.04.2023.
//

import UIKit

var currentUIAlertController: UIAlertController?

extension UIApplication {
    func dismissAlert(animated: Bool, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            currentUIAlertController?.dismiss(animated: animated, completion: completion)
        }
    }
    func alert(title: String, body: String, animated: Bool = true, withButton: Bool = true) {
        DispatchQueue.main.async {
            currentUIAlertController = UIAlertController(title: title, message: body, preferredStyle: .alert)
            if withButton { currentUIAlertController?.addAction(.init(title: NSLocalizedString("OK", comment: ""), style: .cancel)) }
            self.present(alert: currentUIAlertController!)
        }
    }
    func confirmAlert(title: String, body: String, onOK: @escaping () -> (), noCancel: Bool) {
        DispatchQueue.main.async {
            currentUIAlertController = UIAlertController(title: title, message: body, preferredStyle: .alert)
            if !noCancel {
                currentUIAlertController?.addAction(.init(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
            }
            currentUIAlertController?.addAction(.init(title: NSLocalizedString("OK", comment: ""), style: noCancel ? .cancel : .default, handler: { _ in
                onOK()
            }))
            self.present(alert: currentUIAlertController!)
        }
    }
    func change(title: String, body: String) {
        DispatchQueue.main.async {
            currentUIAlertController?.title = title
            currentUIAlertController?.message = body
        }
    }
    
    func present(alert: UIViewController, animated: Bool = true) {
        if var topController = self.keyWindow?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            
            topController.present(alert, animated: animated)
            // topController should now be your topmost view controller
        }
    }
}

