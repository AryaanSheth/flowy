import Foundation

struct OllamaStatus {
    var reachable: Bool
    var models: [String]
    var error: String?
}

enum OllamaClient {
    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let system: String
        let stream: Bool
        let options: Options
    }

    private struct Options: Encodable {
        let temperature: Double
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    private struct TagsResponse: Decodable {
        let models: [TagModel]
    }

    private struct TagModel: Decodable {
        let name: String
    }

    static func enhance(endpoint: String, model: String, system: String, text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let url = try apiURL(endpoint: endpoint, path: "/api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GenerateRequest(
            model: model,
            prompt: trimmed,
            system: system,
            stream: false,
            options: Options(temperature: 0.1)
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GenerateResponse.self, from: data)
            .response
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func status(endpoint: String) async -> OllamaStatus {
        do {
            let models = try await listModels(endpoint: endpoint)
            return OllamaStatus(reachable: true, models: models, error: nil)
        } catch {
            return OllamaStatus(reachable: false, models: [], error: error.localizedDescription)
        }
    }

    static func listModels(endpoint: String) async throws -> [String] {
        let url = try apiURL(endpoint: endpoint, path: "/api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(TagsResponse.self, from: data)
            .models
            .map(\.name)
    }

    private static func apiURL(endpoint: String, path: String) throws -> URL {
        let base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else {
            throw FloweyError.message("Invalid Ollama endpoint")
        }
        return url
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw FloweyError.message(body)
        }
    }
}
