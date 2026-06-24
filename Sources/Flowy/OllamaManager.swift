import Foundation
import AppKit

enum OllamaInstallStatus: Equatable {
    case checking
    case notInstalled
    case stopped       // binary present but server not responding
    case running
    case installing
}

struct RecommendedModel: Identifiable {
    let id: String
    let name: String
    let label: String
    let tagline: String
    let sizeMB: Int

    var sizeLabel: String {
        sizeMB >= 1000 ? String(format: "%.1f GB", Double(sizeMB) / 1000.0) : "\(sizeMB) MB"
    }
}

struct ModelPullState {
    var layers: [String: (completed: Int64, total: Int64)] = [:]
    var done = false
    var error: String?

    var progress: Double? {
        if done { return 1.0 }
        let total = layers.values.map(\.total).reduce(0, +)
        let completed = layers.values.map(\.completed).reduce(0, +)
        guard total > 0 else { return nil }
        return min(1.0, Double(completed) / Double(total))
    }
}

@MainActor
final class OllamaManager: ObservableObject {
    @Published var installStatus: OllamaInstallStatus = .checking
    @Published var installMessage: String = ""
    @Published var installedModels: [String] = []
    @Published var pullStates: [String: ModelPullState] = [:]

    private var pullTasks: [String: Task<Void, Never>] = [:]

    nonisolated static let binaryPaths = [
        "/opt/homebrew/bin/ollama",
        "/usr/local/bin/ollama",
        "/usr/bin/ollama",
    ]

    nonisolated static let recommendedModels: [RecommendedModel] = [
        .init(id: "gemma3:1b",       name: "gemma3:1b",       label: "Gemma 3 1B",    tagline: "Recommended",  sizeMB: 815),
        .init(id: "llama3.2:3b",     name: "llama3.2:3b",     label: "Llama 3.2 3B",  tagline: "Better quality", sizeMB: 2000),
        .init(id: "phi4-mini:3.8b",  name: "phi4-mini:3.8b",  label: "Phi 4 Mini",    tagline: "Balanced",     sizeMB: 2500),
        .init(id: "mistral:7b",      name: "mistral:7b",       label: "Mistral 7B",   tagline: "Best quality", sizeMB: 4100),
    ]

    func checkStatus(endpoint: String) async {
        installStatus = .checking
        let binFound = Self.binaryPaths.contains { FileManager.default.fileExists(atPath: $0) }
        guard binFound else { installStatus = .notInstalled; return }

        if await OllamaClient.isReachable(endpoint: endpoint) {
            installedModels = (try? await OllamaClient.listModels(endpoint: endpoint)) ?? []
            installStatus = .running
        } else {
            installStatus = .stopped
        }
    }

    func installOllama() async {
        installStatus = .installing
        installMessage = "Installing Ollama via Homebrew…"

        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brew = brewPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            installMessage = "Homebrew not found. Download Ollama from ollama.com or install Homebrew first."
            installStatus = .notInstalled
            return
        }

        do {
            let (code, out) = try await shell(brew, ["install", "--cask", "ollama"])
            if code == 0 {
                installMessage = "Starting Ollama…"
                launchOllamaApp()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                installMessage = ""
                installStatus = .running
            } else {
                installMessage = out.isEmpty ? "Installation failed (exit \(code))." : String(out.prefix(300))
                installStatus = .notInstalled
            }
        } catch {
            installMessage = error.localizedDescription
            installStatus = .notInstalled
        }
    }

    func startServer(endpoint: String) {
        launchOllamaApp()
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await checkStatus(endpoint: endpoint)
        }
    }

    func pullModel(_ name: String, endpoint: String) {
        cancelPull(name)
        pullStates[name] = ModelPullState()

        pullTasks[name] = Task {
            do {
                for try await p in OllamaClient.pull(endpoint: endpoint, model: name) {
                    guard !Task.isCancelled else { break }
                    if let err = p.error {
                        pullStates[name] = ModelPullState(done: false, error: err)
                        break
                    }
                    if p.status == "success" {
                        pullStates[name] = ModelPullState(done: true)
                        break
                    }
                    if let d = p.digest, let c = p.completed, let t = p.total, t > 0 {
                        var s = pullStates[name] ?? ModelPullState()
                        s.layers[d] = (c, t)
                        pullStates[name] = s
                    }
                }
            } catch {
                if !Task.isCancelled {
                    pullStates[name] = ModelPullState(done: false, error: error.localizedDescription)
                }
            }
            pullTasks.removeValue(forKey: name)
            installedModels = (try? await OllamaClient.listModels(endpoint: endpoint)) ?? installedModels
        }
    }

    func cancelPull(_ name: String) {
        pullTasks[name]?.cancel()
        pullTasks.removeValue(forKey: name)
        pullStates.removeValue(forKey: name)
    }

    func isInstalled(_ name: String) -> Bool {
        let base = name.split(separator: ":").first.map(String.init)?.lowercased() ?? name.lowercased()
        return installedModels.contains {
            let ib = $0.split(separator: ":").first.map(String.init)?.lowercased() ?? $0.lowercased()
            return ib == base || $0.lowercased() == name.lowercased()
        }
    }

    private func launchOllamaApp() {
        if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
        } else if let bin = Self.binaryPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["serve"]
            try? p.run()
        }
    }

    private func shell(_ path: String, _ args: [String]) async throws -> (Int32, String) {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    p.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    cont.resume(returning: (p.terminationStatus, out))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
