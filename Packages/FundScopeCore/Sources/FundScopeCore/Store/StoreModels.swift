import Foundation
import SwiftData

// Local store, schema V1 (docs/07-data-model.md). Holds only which funds you watch and their
// official NAVs. No units, amounts or account details.

@Model
public final class WatchlistItem {
    /// AMFI scheme code.
    @Attribute(.unique) public var code: String
    public var name: String
    public var addedAt: Date

    public init(code: String, name: String, addedAt: Date = .now) {
        self.code = code
        self.name = name
        self.addedAt = addedAt
    }
}

/// One official NAV for one scheme and valuation date. Never edited after it is written.
@Model
public final class StoredNAV {
    @Attribute(.unique) public var key: String
    public var code: String
    public var date: Date
    public var nav: Decimal
    public var retrievedAt: Date

    public init(code: String, date: Date, nav: Decimal, retrievedAt: Date) {
        self.key = StoredNAV.key(code: code, date: date)
        self.code = code
        self.date = date
        self.nav = nav
        self.retrievedAt = retrievedAt
    }

    static func key(code: String, date: Date) -> String {
        "\(code)|\(ISO8601DateFormatter.string(from: date, timeZone: MarketCalendar.ist, formatOptions: [.withFullDate]))"
    }
}

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [WatchlistItem.self, StoredNAV.self] }
}

public enum FundScopeMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
