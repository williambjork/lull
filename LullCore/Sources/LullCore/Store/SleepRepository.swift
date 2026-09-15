import Foundation

public protocol SleepRepository: AnyObject {
    func load() throws -> BabyDataset?
    func save(_ dataset: BabyDataset) throws
    func deleteAll() throws
}

/// JSON on disk, written atomically. Small enough for years of sleep events,
/// and trivially exportable if a real backend arrives later.
public final class FileSleepRepository: SleepRepository {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public convenience init(directory: URL, fileName: String = "lull-dataset.json") {
        self.init(fileURL: directory.appendingPathComponent(fileName))
    }

    /// Application Support/Lull/lull-dataset.json
    public static func inApplicationSupport(fileName: String = "lull-dataset.json") throws -> FileSleepRepository {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Lull", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return FileSleepRepository(directory: base, fileName: fileName)
    }

    public func load() throws -> BabyDataset? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        return try LullJSON.decoder.decode(BabyDataset.self, from: data)
    }

    public func save(_ dataset: BabyDataset) throws {
        let data = try LullJSON.encoder.encode(dataset)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

public final class InMemorySleepRepository: SleepRepository {
    private var dataset: BabyDataset?

    public init(dataset: BabyDataset? = nil) {
        self.dataset = dataset
    }

    public func load() throws -> BabyDataset? { dataset }
    public func save(_ dataset: BabyDataset) throws { self.dataset = dataset }
    public func deleteAll() throws { dataset = nil }
}
