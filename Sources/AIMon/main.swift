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

// Hidden dev mode: `AIMon --identity-test` prints sample identities so name/rarity/trait quality
// can be eyeballed without the GUI.
if CommandLine.arguments.contains("--identity-test") {
    let sampleCWDs = [
        "/Users/roman/Projects/aimon", "/Users/roman/Projects/web", "/Users/roman/work/api",
        "/tmp/scratch", "/Users/roman/Projects/game-engine", "/Users/roman/dotfiles",
        "/Users/roman/Projects/ml-thing", "/Users/roman/sideproject", "/Users/roman/Projects/cli-tool",
        "/Users/roman/Projects/aimon-test", "/Users/roman/Projects/zeta", "/Users/roman/Projects/omega",
    ]
    for cwd in sampleCWDs {
        let seed = ProjectIdentity.seed(forCWD: cwd)
        let p = PersonalityGenerator.personality(seed: seed)
        let name = NameGenerator.name(seed: seed)
        let rarity = RarityGenerator.rarity(seed: seed)
        print(String(format: "%-12@ %-10@ [%@] enth:%-3d pat:%-3d chaos:%-3d wis:%-3d snark:%-3d  (%@)",
                     name as NSString, rarity.displayName as NSString, p.archetype.rawValue as NSString,
                     p.enthusiasm, p.patience, p.chaos, p.wisdom, p.snark, (cwd as NSString).lastPathComponent as NSString))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar agent: no dock icon
app.run()
