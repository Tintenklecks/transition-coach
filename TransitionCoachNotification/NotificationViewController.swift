import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// Hosts the Signal-styled banner inside the expanded notification.
///
/// iOS draws the collapsed lock-screen banner itself — this takes over once the
/// notification is expanded, with the system's own body text hidden via
/// `UNNotificationExtensionDefaultContentHidden`.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var host: UIHostingController<SignalNotificationView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let step = StepNotification(userInfo: content.userInfo, fallbackBody: content.body)
        let root = SignalNotificationView(step: step)

        if let host {
            host.rootView = root
        } else {
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            addChild(host)
            view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            host.didMove(toParent: self)
            self.host = host
        }

        // Size the extension to exactly what the banner needs.
        let target = view.bounds.width > 0 ? view.bounds.width : preferredContentSize.width
        let fitted = host?.sizeThatFits(in: CGSize(width: target, height: .greatestFiniteMagnitude))
        if let fitted, fitted.height > 0 {
            preferredContentSize = CGSize(width: target, height: fitted.height)
        }
    }
}
