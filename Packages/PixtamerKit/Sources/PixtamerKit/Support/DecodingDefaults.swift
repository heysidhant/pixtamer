import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `defaultValue` when the key is missing or holds a value
    /// this version cannot interpret (for example an enum case written by a newer release).
    /// Keeps persisted presets and settings readable as fields are added over time.
    func decode<T: Decodable>(_ key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
}
