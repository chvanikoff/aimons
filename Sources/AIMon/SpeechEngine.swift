import Foundation
import AIMonCore

/// Decides what a monster says, and presents exactly ONE line per speech (on the main thread):
/// the Ollama line if it answers within a short deadline, otherwise the always-available template
/// fallback. One bubble per event — no instant-placeholder-then-swap (that produced a jarring
/// second bubble whenever the model answered after the first bubble had dismissed).
final class SpeechEngine {
    private let ollama: OllamaProvider?
    private let deadline: TimeInterval

    init(ollama: OllamaProvider? = OllamaProvider(), deadline: TimeInterval = 4) {
        self.ollama = ollama
        self.deadline = deadline
    }

    func speak(_ context: SpeechContext, present: @escaping (String) -> Void) {
        Task {
            let line = await resolveLine(for: context)
            await MainActor.run { present(line) }
        }
    }

    private func resolveLine(for context: SpeechContext) async -> String {
        if let ollama, let llm = await firstWithinDeadline({ try? await ollama.line(for: context) }),
           !llm.isEmpty {
            Log.lifecycle.debug("ollama line: \(llm)")
            return llm
        }
        return TemplateSpeech.line(trigger: context.trigger, archetype: context.archetype,
                                   variant: context.sessionCount)
    }

    /// Run `work`, but give up (returning nil) once `deadline` passes — a late LLM reply is then
    /// ignored rather than popping a second bubble.
    private func firstWithinDeadline(_ work: @escaping () async -> String?) async -> String? {
        let deadline = self.deadline
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
