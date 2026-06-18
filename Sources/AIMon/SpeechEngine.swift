import Foundation
import AIMonCore

/// Decides what a monster says. Presents the always-available template line instantly (a snappy
/// floor), then asynchronously upgrades it with an Ollama line if one arrives — the tiered
/// "works without, better with" design (spec §8.1). `present` is always invoked on the main thread.
final class SpeechEngine {
    private let ollama: OllamaProvider?

    init(ollama: OllamaProvider? = OllamaProvider()) {
        self.ollama = ollama
    }

    func speak(_ context: SpeechContext, present: @escaping (String) -> Void) {
        present(TemplateSpeech.line(trigger: context.trigger, archetype: context.archetype,
                                    variant: context.sessionCount))   // instant floor (on main)
        guard let ollama else { return }
        Task {
            guard let line = try? await ollama.line(for: context), !line.isEmpty else { return }
            await MainActor.run { present(line) }                     // upgrade, swapped in
            Log.lifecycle.debug("ollama line: \(line)")
        }
    }
}
