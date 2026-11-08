import Foundation

/// Combined exposure across funds and fund overlap (docs/10-nav-engine.md §7–8).
public enum LookThrough {
    public struct Exposure: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let value: Decimal
        /// Percent of total portfolio value.
        public let share: Decimal
        public let fundCodes: [String]
    }

    public static let unmappedKey = "__unmapped"
    public static let nonEquityKey = "__nonEquity"

    /// - Parameter positions: my value in each fund paired with that fund's latest disclosure.
    /// Groups equity holdings by `key`; unmapped equity and all non-equity assets get their own buckets,
    /// so shares always add up to 100%.
    public static func exposure(
        positions: [(value: Decimal, disclosure: Disclosure)],
        key: (SecurityInfo) -> (id: String, name: String)
    ) -> [Exposure] {
        var values: [String: (name: String, value: Decimal, funds: Set<String>)] = [:]
        var total: Decimal = 0

        for (value, disclosure) in positions {
            let weightSum = disclosure.holdings.reduce(Decimal(0)) { $0 + $1.weight }
            total += value
            for holding in disclosure.holdings {
                let bucket: (id: String, name: String)
                if holding.assetType == .equity || holding.assetType == .foreignEquity {
                    bucket = holding.security.map(key) ?? (unmappedKey, "Unmapped holdings")
                } else {
                    bucket = (nonEquityKey, "Cash, debt & other")
                }
                var entry = values[bucket.id] ?? (bucket.name, 0, [])
                entry.value += value * holding.weight / 100
                entry.funds.insert(disclosure.fundCode)
                values[bucket.id] = entry
            }
            // Disclosures rarely sum to exactly 100%; keep a shortfall visible instead of rescaling.
            // Rounding overshoot (sum > 100) is left alone rather than shown as negative exposure.
            if weightSum < 100 {
                var entry = values[unmappedKey] ?? ("Unmapped holdings", 0, [])
                entry.value += value * (100 - weightSum) / 100
                entry.funds.insert(disclosure.fundCode)
                values[unmappedKey] = entry
            }
        }

        return values.map { id, entry in
            Exposure(id: id, name: entry.name, value: entry.value,
                     share: total == 0 ? 0 : entry.value / total * 100,
                     fundCodes: entry.funds.sorted())
        }
        .sorted { $0.value > $1.value }
    }

    /// Overlap in percent: sum over common companies of min(weightA, weightB).
    public static func overlap(_ a: Disclosure, _ b: Disclosure) -> Decimal {
        let weightsB = equityWeights(b)
        return equityWeights(a).reduce(Decimal(0)) { sum, entry in
            guard let wb = weightsB[entry.key] else { return sum }
            return sum + min(entry.value, wb)
        }
    }

    static func equityWeights(_ d: Disclosure) -> [String: Decimal] {
        d.holdings.reduce(into: [:]) { result, h in
            guard h.assetType == .equity || h.assetType == .foreignEquity, let isin = h.security?.isin else { return }
            result[isin, default: 0] += h.weight
        }
    }

    /// Herfindahl index on shares given in percent (returns 0...10000).
    public static func herfindahl(_ shares: [Decimal]) -> Decimal {
        shares.reduce(0) { $0 + $1 * $1 }
    }
}
