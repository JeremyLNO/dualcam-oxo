import Network
import Combine

/// Tracks whether the device currently has a usable network path, so account
/// and purchase screens can show a clear "you're offline" state instead of a
/// spinner that never resolves or a raw error.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.crazybeelabs.dualcam.netmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = (path.status == .satisfied) }
        }
        monitor.start(queue: queue)
    }
}
