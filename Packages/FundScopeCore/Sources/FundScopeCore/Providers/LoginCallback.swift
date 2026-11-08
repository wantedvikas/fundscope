import Foundation
import Network

/// Waits for Zerodha's login redirect on 127.0.0.1 only, answers one request, then stops.
/// Nothing on the network beyond this Mac can reach it.
public enum LoginCallback {
    public enum CallbackError: Error, LocalizedError {
        case couldNotListen(String)
        case timedOut

        public var errorDescription: String? {
            switch self {
            case .couldNotListen(let reason): "FundScope couldn't listen for the login reply (\(reason)). Paste the address from the browser instead."
            case .timedOut: "The Zerodha login wasn't finished within 5 minutes."
            }
        }
    }

    /// Returns the full redirect URL (with `request_token`) once the browser arrives.
    public static func wait(port: UInt16 = Kite.redirectPort, timeout: Duration = .seconds(300)) async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch { throw CallbackError.couldNotListen(error.localizedDescription) }

        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                    let once = Once(continuation)
                    listener.stateUpdateHandler = { state in
                        if case .failed(let error) = state { once.resume(throwing: CallbackError.couldNotListen(error.localizedDescription)) }
                    }
                    listener.newConnectionHandler = { connection in
                        connection.start(queue: .global())
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                            // "GET /kite?request_token=…&state=… HTTP/1.1"
                            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                            let page = "<html><body style=\"font: 15px -apple-system; padding: 40px\">Signed in. You can close this tab and return to FundScope.</body></html>"
                            let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
                            connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
                            if path.hasPrefix("/kite"), let url = URL(string: "http://127.0.0.1:\(port)\(path)") { once.resume(returning: url) }
                        }
                    }
                    listener.start(queue: .global())
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CallbackError.timedOut
            }
            defer { listener.cancel(); group.cancelAll() }
            return try await group.next()!
        }
    }

    /// Resumes a continuation exactly once, from whichever callback fires first.
    private final class Once: @unchecked Sendable {
        private var continuation: CheckedContinuation<URL, Error>?
        private let lock = NSLock()
        init(_ c: CheckedContinuation<URL, Error>) { continuation = c }
        func resume(returning url: URL) { take()?.resume(returning: url) }
        func resume(throwing error: Error) { take()?.resume(throwing: error) }
        private func take() -> CheckedContinuation<URL, Error>? {
            lock.lock(); defer { lock.unlock() }
            let c = continuation
            continuation = nil
            return c
        }
    }
}
