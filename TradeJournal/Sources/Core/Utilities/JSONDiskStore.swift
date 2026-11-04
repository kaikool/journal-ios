import Foundation

/// Unified, thread-safe JSON file persistence utility for local Application Support caches and AI stores.
public enum JSONDiskStore {
    public static func appSupportFileURL(
        directory: String = "TradeJournal",
        filename: String
    ) -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent(directory, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    public static func load<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url = url,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func save<T: Encodable>(_ value: T, to url: URL?) {
        guard let url = url,
              let data = try? JSONEncoder().encode(value) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    public static func saveAsync<T: Encodable & Sendable>(
        _ value: T,
        to url: URL?,
        priority: TaskPriority = .utility
    ) {
        guard let url = url else { return }
        Task.detached(priority: priority) {
            save(value, to: url)
        }
    }
}
