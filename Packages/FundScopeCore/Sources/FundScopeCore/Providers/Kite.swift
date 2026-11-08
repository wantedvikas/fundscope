import CryptoKit
import Foundation

/// Zerodha Kite Connect v3, read-only: login session and market quotes. No order endpoints exist here.
/// Checked against kite.trade/docs/connect/v3 on 2026-10-29 (user, market-quotes, exceptions).
public enum Kite {
    public static let apiBase = URL(string: "https://api.kite.trade")!
    /// Must be registered as the app's redirect URL in the Kite developer console.
    /// Accepted by the Kite developer console (verified with a real app, 2026-10-29).
    public static let redirectPort: UInt16 = 7313
    public static let redirectURL = "http://127.0.0.1:7313/kite"
    /// Quote API limits (docs): 500 instruments per /quote request, 1 request per second.
    public static let quoteBatchSize = 500

    public enum KiteError: Error, LocalizedError, Equatable {
        /// 403 TokenException: session expired (6 AM daily) or invalidated. Reconnect.
        case authRequired
        case rateLimited
        case server(type: String?, message: String)
        case badResponse(Int)
        case loginRejected(String)

        public var errorDescription: String? {
            switch self {
            case .authRequired: "Your Zerodha session has expired. Reconnect to continue."
            case .rateLimited: "Kite is rate-limiting requests. FundScope will try again shortly."
            case .server(let type, let message): "Kite: \(message)\(type.map { " (\($0))" } ?? "")"
            case .badResponse(let code): "Kite responded with HTTP \(code)."
            case .loginRejected(let reason): "Zerodha login didn't complete: \(reason)"
            }
        }
    }

    // MARK: Login

    /// Opens on Zerodha's own page; FundScope never sees the password. `state` comes back via `redirect_params`.
    public static func loginURL(apiKey: String, state: String) -> URL {
        var c = URLComponents(string: "https://kite.zerodha.com/connect/login")!
        c.queryItems = [
            URLQueryItem(name: "v", value: "3"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "redirect_params", value: "state=\(state)"),
        ]
        return c.url!
    }

    /// Reads the redirect after login. Rejects a missing token, a failed login or a state that doesn't match.
    public static func requestToken(fromRedirect url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == expectedState else { throw KiteError.loginRejected("the reply didn't come from this login attempt") }
        if let status = value("status"), status != "success" { throw KiteError.loginRejected("Zerodha reported “\(status)”") }
        guard let token = value("request_token"), !token.isEmpty else { throw KiteError.loginRejected("no request token in the reply") }
        return token
    }

    /// SHA-256 of api_key + request_token + api_secret, hex encoded.
    public static func checksum(apiKey: String, requestToken: String, apiSecret: String) -> String {
        SHA256.hash(data: Data((apiKey + requestToken + apiSecret).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func sessionRequest(apiKey: String, requestToken: String, apiSecret: String) -> URLRequest {
        var r = URLRequest(url: apiBase.appending(path: "session/token"))
        r.httpMethod = "POST"
        r.setValue("3", forHTTPHeaderField: "X-Kite-Version")
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "request_token", value: requestToken),
            URLQueryItem(name: "checksum", value: checksum(apiKey: apiKey, requestToken: requestToken, apiSecret: apiSecret)),
        ]
        r.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return r
    }

    public struct Session: Decodable, Sendable {
        public let access_token: String
        public let user_id: String?
    }

    public static func createSession(apiKey: String, requestToken: String, apiSecret: String, session: URLSession = .shared) async throws -> Session {
        let (data, response) = try await session.data(for: sessionRequest(apiKey: apiKey, requestToken: requestToken, apiSecret: apiSecret))
        return try decode(Session.self, data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public static func logout(apiKey: String, accessToken: String, session: URLSession = .shared) async throws {
        var c = URLComponents(url: apiBase.appending(path: "session/token"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "api_key", value: apiKey), URLQueryItem(name: "access_token", value: accessToken)]
        var r = URLRequest(url: c.url!)
        r.httpMethod = "DELETE"
        r.setValue("3", forHTTPHeaderField: "X-Kite-Version")
        let (data, response) = try await session.data(for: r)
        _ = try decode(Bool.self, data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    // MARK: Quotes

    public static func quoteRequest(symbols: [String], apiKey: String, accessToken: String) -> URLRequest {
        var c = URLComponents(url: apiBase.appending(path: "quote"), resolvingAgainstBaseURL: false)!
        c.queryItems = symbols.map { URLQueryItem(name: "i", value: $0) }
        var r = URLRequest(url: c.url!)
        r.setValue("3", forHTTPHeaderField: "X-Kite-Version")
        r.setValue("token \(apiKey):\(accessToken)", forHTTPHeaderField: "Authorization")
        return r
    }

    /// Kite's instrument key for the Nifty 50 index (exchange NSE, tradingsymbol "NIFTY 50").
    public static let nifty50 = "NSE:NIFTY 50"

    struct QuoteEntry: Decodable {
        struct OHLC: Decodable { let close: Decimal? }
        let last_price: Decimal?
        let ohlc: OHLC?
        /// Exchange time of the quote packet, "yyyy-MM-dd HH:mm:ss" in IST.
        let timestamp: String?
    }

    /// Parses /quote. Keys missing from the response (unknown or suspended stocks) are simply absent from the result.
    /// `previousClose` is ohlc.close: the close of the last trading day, which is what the estimator needs.
    public static func parseQuotes(_ data: Data, status: Int, symbolToISIN: [String: String], fallbackTime: Date) throws -> [String: Quote] {
        let entries = try decode([String: QuoteEntry].self, data: data, status: status)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = MarketCalendar.ist
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var quotes: [String: Quote] = [:]
        for (symbol, e) in entries {
            guard let isin = symbolToISIN[symbol], let price = e.last_price, price > 0, let close = e.ohlc?.close, close > 0 else { continue }
            quotes[isin] = Quote(isin: isin, price: price, previousClose: close,
                                 exchangeTime: e.timestamp.flatMap(formatter.date) ?? fallbackTime)
        }
        return quotes
    }

    /// Fetches quotes for NSE symbols in batches, waiting a second between batches (Kite allows 1 quote request/second).
    public static func quotes(symbolToISIN: [String: String], apiKey: String, accessToken: String,
                              session: URLSession = .shared) async throws -> [String: Quote] {
        var result: [String: Quote] = [:]
        let symbols = symbolToISIN.keys.sorted()
        for (i, start) in stride(from: 0, to: symbols.count, by: quoteBatchSize).enumerated() {
            if i > 0 { try await Task.sleep(for: .milliseconds(1100)) }
            let batch = Array(symbols[start..<min(start + quoteBatchSize, symbols.count)])
            let (data, response) = try await session.data(for: quoteRequest(symbols: batch, apiKey: apiKey, accessToken: accessToken))
            result.merge(try parseQuotes(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                         symbolToISIN: symbolToISIN, fallbackTime: .now)) { a, _ in a }
        }
        return result
    }

    // MARK: Responses

    struct Envelope<T: Decodable>: Decodable {
        let status: String?
        let data: T?
        let message: String?
        let error_type: String?
    }

    /// Kite wraps everything in {status, data} or {status: "error", message, error_type}.
    static func decode<T: Decodable>(_ type: T.Type, data: Data, status: Int) throws -> T {
        let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data)
        if status == 403 || envelope?.error_type == "TokenException" { throw KiteError.authRequired }
        if status == 429 { throw KiteError.rateLimited }
        if let envelope, envelope.status == "error" || status != 200 {
            throw KiteError.server(type: envelope.error_type, message: envelope.message ?? "Unknown error")
        }
        guard status == 200, let value = envelope?.data else { throw KiteError.badResponse(status) }
        return value
    }
}
