import Foundation

/// Month-to-month comparison of two disclosures of the same fund (docs/10-nav-engine.md §9).
public enum DisclosureDiff {
    public enum Kind: String, Sendable, CaseIterable {
        case new, exited, increased, decreased, unchanged
    }

    public struct Change: Identifiable, Hashable, Sendable {
        public var id: String { key }
        public let key: String
        public let name: String
        public let sector: String?
        public let kind: Kind
        public let oldWeight: Decimal?
        public let newWeight: Decimal?
        public let oldQuantity: Decimal?
        public let newQuantity: Decimal?
        /// True when both disclosures report quantity, so the change is a confirmed trade.
        public var isQuantityConfirmed: Bool { oldQuantity != nil && newQuantity != nil }
        public var weightChange: Decimal { (newWeight ?? 0) - (oldWeight ?? 0) }

        /// A quantity ratio of a typical split/bonus factor needs checking before calling it a trade.
        public var possibleCorporateAction: Bool {
            guard let o = oldQuantity, let n = newQuantity, o > 0, n > 0 else { return false }
            return [2, 3, 4, 5, 10].contains { n == o * Decimal($0) || o == n * Decimal($0) }
        }
    }

    public static func compare(old: Disclosure, new: Disclosure) -> [Change] {
        // Only real investment decisions: cash, debt, arbitrage and fund units roll over every month and would drown them out.
        func index(_ d: Disclosure) -> [String: DisclosedHolding] {
            Dictionary(d.holdings.filter(\.assetType.isOwnedCompany).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        let a = index(old), b = index(new)
        return Set(a.keys).union(b.keys).map { key in
            let o = a[key], n = b[key]
            let kind: Kind
            switch (o, n) {
            case (nil, _?): kind = .new
            case (_?, nil): kind = .exited
            case let (o?, n?):
                // Prefer quantity when both sides have it; weight alone can move with price.
                if let oq = o.quantity, let nq = n.quantity {
                    kind = nq > oq ? .increased : nq < oq ? .decreased : .unchanged
                } else {
                    kind = n.weight > o.weight ? .increased : n.weight < o.weight ? .decreased : .unchanged
                }
            default: kind = .unchanged
            }
            let holding = n ?? o!
            return Change(key: key, name: holding.security?.name ?? holding.rawName,
                          sector: holding.security?.sector, kind: kind,
                          oldWeight: o?.weight, newWeight: n?.weight,
                          oldQuantity: o?.quantity, newQuantity: n?.quantity)
        }
        .sorted { abs($0.weightChange) > abs($1.weightChange) }
    }

    /// Sector weight (percent) for a disclosure; non-equity grouped by asset type label.
    public static func sectorWeights(_ d: Disclosure) -> [String: Decimal] {
        d.holdings.reduce(into: [:]) { result, h in
            let key = h.assetType == .equity ? (h.security?.sector ?? "Unmapped") : h.assetType.label
            result[key, default: 0] += h.weight
        }
    }
}
