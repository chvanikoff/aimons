import AppKit
import AIMonCore

// Hidden dev mode: `AIMon --speech-test` exercises the real Ollama speech path once and exits,
// so the LLM tier can be verified headlessly (no GUI / window needed).
if CommandLine.arguments.contains("--speech-test") {
    let ctx = SpeechContext(archetype: .grumpy, trigger: .sessionJoined(count: 2),
                            projectName: "aimon", sessionCount: 2)
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let line = try await OllamaProvider().line(for: ctx)
            print("OLLAMA OK: \(line)")
        } catch {
            print("OLLAMA FAIL (falls back to template): \(error)")
            print("template floor: \(TemplateSpeech.line(trigger: ctx.trigger, archetype: ctx.archetype, variant: ctx.sessionCount))")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar agent: no dock icon
app.run()
