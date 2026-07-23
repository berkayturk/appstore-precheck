import Foundation

final class ChatService {
    let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func send(_ userText: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["content": userText])
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }
}
