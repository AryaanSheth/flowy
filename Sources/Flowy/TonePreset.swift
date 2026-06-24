import Foundation

struct TonePreset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var prompt: String   // empty = bypass Ollama (Raw)

    static let builtIns: [TonePreset] = [
        .init(id: "raw",      name: "Raw",            prompt: rawPrompt),
        .init(id: "clean",    name: "Clean",           prompt: cleanPrompt),
        .init(id: "formal",   name: "Formal",          prompt: formalPrompt),
        .init(id: "business", name: "Business Casual", prompt: businessPrompt),
        .init(id: "concise",  name: "Concise",         prompt: concisePrompt),
        .init(id: "bullets",  name: "Bullet Points",   prompt: bulletsPrompt),
    ]
}

// MARK: – Built-in prompts

private let rawPrompt = ""

private let cleanPrompt = AppConfig.defaultOllamaPrompt

private let formalPrompt = """
Rewrite as formal professional prose. Fix grammar, punctuation, capitalization, and spoken self-corrections. Preserve meaning. Return only the final text.
"""

private let businessPrompt = """
Rewrite in a business casual tone. Be clear, direct, and conversational. Fix grammar, punctuation, and self-corrections. Return only the final text.
"""

private let concisePrompt = """
Make this concise while preserving meaning. Remove filler and redundancy. Fix grammar, punctuation, and self-corrections. Return only the final text.
"""

private let bulletsPrompt = """
Convert to concise bullet points. One idea per bullet. Fix grammar, punctuation, and self-corrections. Use "•". Return only bullets.
"""
