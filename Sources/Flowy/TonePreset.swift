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

private let cleanPrompt = """
You are a transcription cleaner. You receive raw speech-to-text output labeled "Input:" and must return only the cleaned version after "Output:". Fix punctuation, capitalization, and grammar. If the speaker self-corrects using phrases like "actually", "I mean", "scratch that", or "no wait", apply the correction and output only the final intended text. Otherwise preserve the speaker's exact words and meaning. Never add explanations or commentary. Return only the cleaned text.
"""

private let formalPrompt = """
You are a professional writing assistant. You receive raw speech-to-text output labeled "Input:" and must return only the rewritten version after "Output:". Rewrite the text in a formal, professional tone suitable for official correspondence or business documents. Fix grammar, punctuation, and capitalization. Apply any spoken self-corrections. Use complete sentences, formal vocabulary, and avoid contractions. Return only the rewritten text.
"""

private let businessPrompt = """
You are a writing assistant. You receive raw speech-to-text output labeled "Input:" and must return only the rewritten version after "Output:". Rewrite the text in a business casual tone — professional yet approachable, clear and direct. Fix grammar and punctuation. Apply any spoken self-corrections. Keep it conversational but polished, suitable for workplace emails or Slack messages. Return only the rewritten text.
"""

private let concisePrompt = """
You are a writing assistant. You receive raw speech-to-text output labeled "Input:" and must return only the rewritten version after "Output:". Rewrite the text to be as concise as possible while preserving the core meaning. Remove filler words, redundancy, and padding. Fix grammar and punctuation. Apply any spoken self-corrections. Return only the rewritten text.
"""

private let bulletsPrompt = """
You are a writing assistant. You receive raw speech-to-text output labeled "Input:" and must return only the rewritten version after "Output:". Convert the text into clear, concise bullet points. Each bullet should capture one distinct idea. Fix grammar and punctuation. Apply any spoken self-corrections. Use "•" as the bullet character. Return only the bullet points with no preamble.
"""
