import Combine
import Foundation

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var snapshot = F40Snapshot()
    @Published private(set) var isRefreshing = false

    private let client: F40APIClient
    private var pollingTask: Task<Void, Never>?

    init(client: F40APIClient = F40APIClient()) {
        self.client = client
    }

    deinit {
        pollingTask?.cancel()
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            snapshot = try await client.fetchSnapshot()
        } catch {
            var failed = snapshot
            if let f40Error = error as? F40Error,
               f40Error == .loginFailed || f40Error == .noCredential {
                failed.isReachable = true
                failed.isAuthenticated = false
                failed.simStatus = "需要登录"
            } else {
                failed.isReachable = false
            }
            failed.errorMessage = error.localizedDescription
            failed.lastUpdated = Date()
            snapshot = failed
        }
    }
}
