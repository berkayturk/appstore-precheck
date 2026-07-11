import Foundation

/// On-device persistence: notes are JSON files in the app's Documents
/// directory. No networking anywhere in the target.
struct LocalStore {
    private let dir = FileManager.default.urls(for: .documentDirectory,
                                               in: .userDomainMask)[0]

    func save(_ text: String, id: UUID) throws {
        let url = dir.appendingPathComponent("\(id.uuidString).json")
        let data = try JSONEncoder().encode(["text": text])
        try data.write(to: url, options: .atomic)
    }

    func load(id: UUID) throws -> String {
        let url = dir.appendingPathComponent("\(id.uuidString).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: String].self, from: data)["text"] ?? ""
    }
}
