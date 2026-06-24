import Foundation

struct OllamaStatus {
    var reachable: Bool
    var models: [String]
    var error: String?
}

struct PullProgress: Decodable {
    let status: String
    let digest: String?
    let completed: Int64?
    let total: Int64?
    let error: String?
}

enum OllamaClient {
    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let system: String
        let stream: Bool
        let options: Options
        let keepAlive: String

        enum CodingKeys: String, CodingKey {
            case model
            case prompt
            case system
            case stream
            case options
            case keepAlive = "keep_alive"
        }
    }

    private struct Options: Encodable {
        let temperature: Double
        let numPredict: Int

        enum CodingKeys: String, CodingKey {
            case temperature
            case numPredict = "num_predict"
        }
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

    static func enhance(
        endpoint: String,
        model: String,
        system: String,
        text: String,
        timeoutSeconds: TimeInterval = LocalPolishResolver.requestTimeoutSeconds
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let url = try apiURL(endpoint: endpoint, path: "/api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GenerateRequest(
            model: model,
            prompt: "Input: \(trimmed)\nOutput:",
            system: system,
            stream: false,
            options: Options(
                temperature: 0.1,
                numPredict: OllamaGenerationPolicy.maxResponseTokens(for: trimmed)
            ),
            keepAlive: "10m"
        ))

        let (data, response) = try await withTimeout(seconds: timeoutSeconds) {
            try await URLSession.shared.data(for: request)
        }
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GenerateResponse.self, from: data)
            .response
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func warmUp(endpoint: String, model: String) async {
        do {
            let url = try apiURL(endpoint: endpoint, path: "/api/generate")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = LocalPolishResolver.warmUpTimeoutSeconds
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(GenerateRequest(
                model: model,
                prompt: "ok",
                system: "Reply with ok.",
                stream: false,
                options: Options(
                    temperature: 0,
                    numPredict: OllamaGenerationPolicy.warmUpMaxResponseTokens
                ),
                keepAlive: "10m"
            ))

            let (_, response) = try await withTimeout(seconds: LocalPolishResolver.warmUpTimeoutSeconds) {
                try await URLSession.shared.data(for: request)
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                FlowyLog.warn("Ollama warm-up returned HTTP \(http.statusCode)")
            }
        } catch {
            FlowyLog.warn("Ollama warm-up skipped: \(error.localizedDescription)")
        }
    }

    static func isReachable(endpoint: String) async -> Bool {
        do { _ = try await listModels(endpoint: endpoint); return true } catch { return false }
    }

    static func pull(endpoint: String, model: String) -> AsyncThrowingStream<PullProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = try apiURL(endpoint: endpoint, path: "/api/pull")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 600
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(["name": model] as [String: String])

                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw FlowyError.message("HTTP \(http.statusCode)")
                    }

                    let decoder = JSONDecoder()
                    var buffer = Data()
                    for try await byte in asyncBytes {
                        if byte == 10 {
                            if !buffer.isEmpty,
                               let p = try? decoder.decode(PullProgress.self, from: buffer) {
                                continuation.yield(p)
                            }
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
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
            throw FlowyError.message("Invalid Ollama endpoint")
        }
        return url
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw FlowyError.message(body)
        }
    }

    private static func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(max(0.1, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw FlowyError.message("Timed out after \(String(format: "%.1f", seconds))s")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
