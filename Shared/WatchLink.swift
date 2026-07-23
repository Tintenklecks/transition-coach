import Foundation
import Observation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// One-way state, one-way intent.
///
/// The phone publishes a `CoachSnapshot` as the application context — the system
/// keeps only the latest one and delivers it even if the watch app is closed, so
/// opening the watch always lands on current data. The watch sends back a single
/// intent ("I pressed the button"); the phone owns the model and decides what
/// that means.
@Observable
final class WatchLink {
    static let shared = WatchLink()

    private(set) var snapshot: CoachSnapshot?

    /// Whether the counterpart app can be reached right now. Only the watch acts
    /// on this — its button needs a live phone to have any effect.
    private(set) var isReachable = false

    /// Phone side: what to run when the watch taps its primary button.
    @ObservationIgnored var primaryActionHandler: (() -> Void)?

    @ObservationIgnored private var lastPublished: CoachSnapshot?
    @ObservationIgnored private var delegate: SessionDelegate?

    private static let snapshotKey = "snapshot"
    private static let actionKey = "action"
    private static let primaryAction = "primary"

    func activate() {
#if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        guard delegate == nil else { return }
        let delegate = SessionDelegate(link: self)
        self.delegate = delegate
        let session = WCSession.default
        session.delegate = delegate
        session.activate()
        apply(context: session.receivedApplicationContext)
#endif
    }

    // MARK: - Phone side

    /// Publishes the current plan. Repeats are dropped, so this is safe to call
    /// from a per-second timeline tick.
    func publish(_ snapshot: CoachSnapshot?) {
#if canImport(WatchConnectivity)
        guard let snapshot, snapshot != lastPublished else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try WCSession.default.updateApplicationContext([Self.snapshotKey: data])
            lastPublished = snapshot
        } catch {
            // Transient — the next tick republishes.
        }
#endif
    }

    // MARK: - Watch side

    /// Asks the phone to run the same action its primary button would.
    /// `completion` reports whether the phone actually took it.
    func requestPrimaryAction(completion: @escaping (Bool) -> Void) {
#if canImport(WatchConnectivity)
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            completion(false)
            return
        }
        WCSession.default.sendMessage(
            [Self.actionKey: Self.primaryAction],
            replyHandler: { _ in
                Task { @MainActor in completion(true) }
            },
            errorHandler: { _ in
                Task { @MainActor in completion(false) }
            }
        )
#else
        completion(false)
#endif
    }

    // MARK: - Inbound

    fileprivate func apply(context: [String: Any]) {
        guard let data = context[Self.snapshotKey] as? Data,
              let decoded = try? JSONDecoder().decode(CoachSnapshot.self, from: data)
        else { return }
        snapshot = decoded
    }

    fileprivate func handle(message: [String: Any]) {
        guard message[Self.actionKey] as? String == Self.primaryAction else { return }
        primaryActionHandler?()
    }

    fileprivate func setReachable(_ reachable: Bool) {
        isReachable = reachable
    }

    /// Republishes after a reconnect, when the counterpart may have missed the
    /// last context.
    fileprivate func republish() {
        let pending = lastPublished
        lastPublished = nil
        publish(pending)
    }
}

#if canImport(WatchConnectivity)

/// Kept separate from `WatchLink` so the delegate callbacks — which arrive off
/// the main actor — stay isolated from the observable state they feed.
private final class SessionDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let link: WatchLink

    init(link: WatchLink) {
        self.link = link
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            link.setReachable(reachable)
            link.apply(context: context)
            link.republish()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in link.apply(context: context) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            link.handle(message: message)
            replyHandler(["ok": true])
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in link.setReachable(reachable) }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched watches — reactivate so the new one gets the plan.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}

#endif
