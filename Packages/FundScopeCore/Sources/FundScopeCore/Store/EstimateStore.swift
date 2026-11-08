import Foundation

/// Frozen estimates on disk, one write-once JSON file per trading day: `Estimates/<yyyy-MM-dd>.json`.
public enum EstimateStore {
    static func folder(_ base: URL) -> URL { base.appending(path: "Estimates", directoryHint: .isDirectory) }

    /// Writes a day's estimates. If that day already has a file, nothing is changed.
    @discardableResult
    public static func save(_ estimates: [FrozenEstimate], day: Date, in base: URL) throws -> Bool {
        guard !estimates.isEmpty else { return false }
        try FileManager.default.createDirectory(at: folder(base), withIntermediateDirectories: true)
        let url = folder(base).appending(path: DisclosureStore.fileName(day))
        guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
        try DisclosureStore.encoder.encode(estimates).write(to: url, options: .withoutOverwriting)
        return true
    }

    public static func load(in base: URL) -> [FrozenEstimate] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(base), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .flatMap { (try? DisclosureStore.decoder.decode([FrozenEstimate].self, from: Data(contentsOf: $0))) ?? [] }
    }
}
