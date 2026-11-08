import Foundation

/// Parses cell text into typed values. Unknown or blank → nil, never zero.
public enum ValueParser {
    /// "₹1,23,456.78", "(50.00)", "7.7499999999999999E-2" → Decimal. "-", "N.A.", "" → nil.
    public static func number(_ raw: String?) -> Decimal? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if ["-", "—", "n.a.", "na", "n/a", "nil"].contains(s.lowercased()) { return nil }
        var negative = false
        if s.hasPrefix("("), s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        for junk in ["₹", "Rs.", "INR", ",", " ", "\u{00A0}"] { s = s.replacingOccurrences(of: junk, with: "") }
        if s.hasPrefix("−") { s = "-" + s.dropFirst() }
        guard s.allSatisfy({ $0.isNumber || ".-+eE".contains($0) }),
              let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    /// Two letters, nine alphanumerics, one check digit.
    public static func isISIN(_ s: String) -> Bool {
        s.range(of: "^[A-Z]{2}[A-Z0-9]{9}[0-9]$", options: .regularExpression) != nil
    }
}
