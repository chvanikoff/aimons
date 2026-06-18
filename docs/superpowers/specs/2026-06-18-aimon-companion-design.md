# AIMon — AI Companion Buddy: Design

- **Date:** 2026-06-18
- **Status:** Draft for review
- **Author:** Roman Chvanikov (with Claude)

## 1. Summary

AIMon is a macOS desktop companion. Each **live AI coding session** (Claude Code
first) spawns a small floating monster sprite, tied to that session, that lives on
your desktop over your other windows. The monster watches the session's transcript,
understands what the AI is actually doing, and pipes up occasionally in a text speech
bubble — commenting on progress, reacting to events, or sharing a random thought.

Monsters are randomized creatures with their own traits and persistent identity: each
project has a resident AIMon that comes back every session, and you keep a reassignable
"stable" of them. Run four parallel sessions and you get four independent monsters on
screen, each draggable and resizable.

v1 is a **pure companion** (watch, talk, drag, resize, pet — no upkeep). The data model
deliberately leaves room to grow into Tamagotchi-style care later.

## 2. Goals and Non-Goals

### Goals (v1)
- macOS menu-bar app (no dock icon), single process.
- Detect live Claude Code sessions and spawn one floating monster per session.
- "Read the work": parse the session transcript so the monster can comment on what the
  AI is actually doing (editing files, running tests, waiting for input, errored, done).
- Tiered speech, text-only:
  1. **Local LLM (Ollama)** when reachable — preferred.
  2. **External LLM** (optional, user-configured) — fallback.
  3. **Templates** (offline) — always-works floor.
- Randomized, procedurally generated pixel-art monsters with persistent, per-project
  identity and a reassignable stable.
- Floating, transparent, always-on-top, non-activating windows; drag to move, resize to
  scale, click to pet. Positions persist.
- Works the instant it's installed (zero Claude Code config), gets sharper with an
  optional one-click hook install.

### Non-Goals (v1) — explicitly deferred
- **Audio / TTS.** Text bubbles only. Maybe later.
- **Tamagotchi care mechanics** (hunger/mood decay, neglect consequences). Data model
  accommodates it; behavior is not built yet.
- **3D models.** Procedural 2D pixel-art only; the render layer is designed so 3D can
  drop in later (SceneKit/RealityKit).
- **Other AI CLIs** (Codex, Gemini, etc.). Architecture supports adapters; only the
  Claude Code adapter ships.
- **Windows / Linux.** macOS only, by decision.
- **Curated/AI-generated art packs.** The appearance layer is swappable so these can be
  added later without touching the brain.

## 3. Key Decisions (quick reference)

| Area | Decision | Rationale |
|---|---|---|
| Platform | macOS only | User has no other-platform interest; unlocks native frameworks. |
| Language/UI | Swift + AppKit + SpriteKit (→ SceneKit/RealityKit later) | Native overlays are a solved problem; cleanest 2D→3D path; lowest risk. |
| Packaging | SwiftPM executable booting `NSApplication` programmatically | Builds/runs from CLI without Xcode; fast iteration. |
| Process model | One process, N windows | Many companions stay cheap; no per-session app instances. |
| AI tool | Claude Code first, adapter protocol for others | Richest observable surface; extensible. |
| Session awareness | Read the transcript ("reads the work") | Enables content-aware commentary. |
| Session tracking | Baseline: FSEvents transcript watch (zero-config). Enhanced: optional hooks. | Works immediately; sharper if opted in. |
| Speech | Ollama → external LLM → templates, text only | "Works without, better with." |
| Identity | Per-project resident AIMon + reassignable stable | Builds attachment; flexible. |
| Lifecycle | Spawn on session start, despawn on session end; identity persists on disk | Screen shows only active sessions. |
| Mechanics | Pure companion v1; care-ready data model | Ship value now, grow later. |
| Art | Procedural now; swappable appearance layer for packs/AI/3D later | Zero art dependency; future-proof. |

## 4. Architecture

One process, six modules with clean boundaries:

```
                 ┌───────────────────────────────────────────────┐
                 │                  App Shell                      │
                 │  (menu bar, settings, onboarding, lifecycle)    │
                 └───────────────────────────────────────────────┘
                          │                         │
        ┌─────────────────▼─────────┐     ┌─────────▼───────────────┐
        │     Session Watcher       │     │     AIMon Registry      │
        │  (Claude Code adapter)    │     │  (identity & persistence)│
        └─────────────┬─────────────┘     └─────────┬───────────────┘
                      │ SessionEvent                │ AIMon (traits)
                      ▼                              ▼
        ┌───────────────────────────────────────────────────────────┐
        │                    Companion Brain                          │
        │   (one per active AIMon: state machine + speech scheduling) │
        └───────────────┬───────────────────────────┬────────────────┘
              animation  │                           │ speech request
                         ▼                           ▼
        ┌────────────────────────────┐   ┌────────────────────────────┐
        │       Render Layer         │   │       Speech Engine         │
        │ (NSPanel + SpriteKit scene)│   │ Ollama → External → Template│
        └────────────────────────────┘   └────────────────────────────┘
```

### 4.1 Session Watcher — "the senses"
- **Purpose:** detect and follow AI sessions; emit normalized events.
- **Interface:** `protocol SessionSource { var events: AsyncStream<SessionEvent> { get } }`.
  Ships with `ClaudeCodeSource`; future `CodexSource` etc.
- **Depends on:** filesystem (FSEvents), optional local IPC server.
- See §6 for the Claude Code mechanism and `SessionEvent` model.

### 4.2 AIMon Registry — "identity & persistence"
- **Purpose:** own the stable of monsters and project→AIMon bindings; mint new monsters.
- **Interface:** `aimon(forProject: ProjectKey) -> AIMon` (returns existing binding or
  mints + binds a new one), `rebind(project:to:)`, `all() -> [AIMon]`.
- **Depends on:** on-disk store (§11), trait generator (§7).

### 4.3 Companion Brain — "behavior"
- **Purpose:** one instance per active AIMon. Translate `SessionEvent`s into a mood/state
  machine, choose animations, and decide *when* and *whether* to speak.
- **State machine:** `idle → working → waitingForYou → celebrating → error → idle` (plus
  `asleep` between sessions, though v1 despawns on end).
- **Speech scheduling:** event-triggered + occasional idle "random thoughts", governed by
  a global cooldown and intrusiveness settings (§8.3).
- **Depends on:** Speech Engine, Render Layer.

### 4.4 Speech Engine — "the voice" (text)
- See §8.

### 4.5 Render Layer — "the body"
- See §9.

### 4.6 App Shell
- See §10.

## 5. Data Flow

1. Claude Code runs a session and writes/updates its transcript JSONL.
2. **Session Watcher** observes (file growth and/or hook POSTs), parses, and emits a
   normalized `SessionEvent` (e.g. `.toolUse(.edit("auth.swift"))`, `.waitingForYou`).
3. On a `.started` event, the **App Shell** asks the **Registry** for the project's AIMon,
   spawns a **Companion Brain** + a **Render** window.
4. The **Brain** updates its state machine, sets an animation, and — if its speech policy
   allows — builds a context (recent transcript summary + the AIMon's personality) and
   requests a line from the **Speech Engine**.
5. The **Speech Engine** returns text (Ollama → external → template) and the **Render
   Layer** shows it in a bubble.
6. On `.ended`, the Brain + window despawn; the AIMon's identity and last position persist
   in the **Registry** for next time.

## 6. Session Tracking (Claude Code)

Two tiers, both feeding the same normalized `SessionEvent` stream.

### 6.1 Baseline — zero-config transcript watching
- Claude Code writes a transcript per session at
  `~/.claude/projects/<cwd-slug>/<session-uuid>.jsonl`, where `<cwd-slug>` is the working
  directory path with separators replaced (e.g. `-Users-roman-Projects-aimon`). The slug
  yields the **ProjectKey** for identity binding (§7).
- Watch that tree with **FSEvents**. Interpret:
  - new `.jsonl` file → `.started` (parse `cwd`/session id).
  - file grows → read appended lines, classify into `.working` / `.toolUse(...)` /
    `.message(...)`.
  - last line is an assistant turn with no following user turn + no growth for *N* s →
    `.waitingForYou` (heuristic).
  - no growth for a longer idle threshold → `.idle`.
  - error markers in tool results → `.error`.
  - file unmodified past a session-stale threshold → `.ended` (heuristic; hooks make this
    precise).
- **Requires no Claude Code configuration.** Reading files under the user's home directory
  needs no special entitlement for a non-sandboxed app.

### 6.2 Enhanced — optional hook install
- A one-click Settings action installs Claude Code hooks (`SessionStart`, `Stop`,
  `Notification`, `PostToolUse`) into the user's Claude settings. Each hook is a tiny
  command that POSTs its JSON payload to a localhost endpoint the app exposes
  (`127.0.0.1:<port>`, loopback only).
- Benefits: precise spawn/despawn lifecycle and accurate "⏳ waiting for *you*" /
  notification moments that are fuzzy from files alone.
- Fully reversible (uninstall button). The baseline keeps working if hooks are absent.

### 6.3 `SessionEvent` model (sketch)
```swift
struct SessionRef { let id: String; let projectKey: ProjectKey; let cwd: URL }

enum SessionEvent {
    case started(SessionRef)
    case working(SessionRef, summary: String?)          // appended assistant/tool activity
    case toolUse(SessionRef, ToolActivity)               // .edit(path), .run(cmd), .read(path)...
    case waitingForYou(SessionRef)
    case idle(SessionRef)
    case error(SessionRef, message: String?)
    case ended(SessionRef)
}
```

## 7. AIMon Identity & Generation

### 7.1 Trait model
Each AIMon is fully derived from a stable **seed** (so it's reproducible and shareable):
```swift
struct AIMon: Codable {
    let id: UUID
    let seed: UInt64                  // drives appearance + name + base personality
    var name: String                  // generated, user-renamable
    var personality: Personality      // tone vector: e.g. cheer, snark, verbosity, chaos
    var appearanceSeed: UInt64        // subset of seed used by the appearance layer
    var createdAt: Date
    var care: CareState?              // reserved for Tamagotchi era; nil in v1
}
```
- **Personality** is a small set of scalars that bias both animation and speech prompts
  (and template selection). Deterministic from seed, user-tweakable later.

### 7.2 Procedural appearance (swappable)
- `protocol AppearanceProvider { func sprite(for: AIMon, state: CompanionState) -> SpriteSet }`.
- v1 implementation: `ProceduralAppearance` — assembles a symmetric pixel creature from the
  seed (body shape, palette from hue/sat, eyes, optional horns/antennae) with a few
  animation frames (idle wiggle, talk, celebrate, sleep).
- Because consumers only touch the protocol, later we can add `PackAppearance` (curated
  sprites), `AIGeneratedAppearance`, or `Model3DAppearance` (SceneKit) without changing the
  Brain or Render layer.

### 7.3 Binding & lifecycle
- On `.started`, Registry maps `projectKey → AIMon`. If unbound, mint a new random AIMon
  (random seed) and bind it. User can rebind a project to any AIMon in the stable, or mint
  a fresh one.
- Identity, name, personality, and last on-screen position persist across sessions; the
  on-screen window exists only while the session is live.

## 8. Speech Engine

### 8.1 Provider tiers
```swift
protocol SpeechProvider {
    var isAvailable: Bool { get async }
    func line(for context: SpeechContext) async throws -> String
}
```
- `OllamaProvider` — POSTs to `http://localhost:11434` (configurable). Preferred when
  reachable. Model configurable (e.g. a small fast local model).
- `ExternalLLMProvider` — optional, user-configured endpoint + key. Supports an
  OpenAI-compatible endpoint and Anthropic. Off unless configured.
- `TemplateProvider` — offline pools keyed by `(state, personality)`. Always available.

Selection order each time a line is needed: **Ollama (if available) → External (if
configured) → Template**. The Template line can also render *instantly* as a placeholder
while an LLM line generates, then swap in.

### 8.2 Context & prompt
`SpeechContext` carries: AIMon personality, current state, and a short rolling summary of
recent transcript activity (e.g. "edited 3 files in auth/, ran tests, 2 failed"). The
prompt instructs the model to speak in-character, briefly (one short bubble), and to avoid
leaking secrets/paths verbatim.

### 8.3 Cadence & intrusiveness (UX-critical)
An annoying pet gets deleted, so defaults are conservative and tunable:
- Speak on **meaningful** events (task done, tests pass/fail, waiting-for-you, error), not
  every file edit.
- Occasional **idle thoughts** at long random-ish intervals.
- **Global cooldown** between bubbles (per AIMon).
- **Focus/quiet mode** and per-project mute. Bubbles auto-dismiss after a few seconds.

## 9. Render & Windowing

- **Per AIMon:** one borderless, transparent, **non-activating** `NSPanel`
  (`.nonactivatingPanel`, clear background, `level = .floating`, `collectionBehavior`
  including `.canJoinAllSpaces` / `.stationary` as appropriate), sized to the sprite +
  bubble. Keeping each window small and shaped to the creature largely sidesteps
  per-pixel click-through complexity.
- **Content:** an `SKView` hosting a SpriteKit scene that renders the monster animation and
  the speech bubble (SpriteKit nodes, or a small hosted SwiftUI/AppKit view for crisp text).
- **Interaction:**
  - Drag the sprite → move the window (and persist position).
  - Resize handle / pinch → scale sprite + window.
  - Click/tap the sprite → "pet" reaction animation (+ maybe a templated quip).
  - Transparent area outside the sprite's alpha is click-through so it never blocks work.
- **Persistence:** last position/scale per (project, AIMon) stored in the Registry.

## 10. App Shell

- **Menu-bar item** (`NSStatusItem`): list of active AIMons, quick mute/focus toggle,
  open Settings, quit.
- **Settings:** Ollama host/model; external LLM endpoint + key; speech cadence/intrusiveness;
  per-project enable/disable & rebind; hook install/uninstall; launch-at-login; art toggle.
- **Onboarding:** first-run explainer; offer (don't force) the hook install; confirm Ollama
  detection; show a sample monster.
- **No dock icon** (agent/accessory activation policy).

## 11. Persistence & File Layout

`~/Library/Application Support/AIMon/`
- `registry.json` — the stable (AIMons) + project bindings + per-binding window state.
- `settings.json` — user settings (LLM config, cadence, etc.).
- `templates/` — speech template pools (bundled defaults, user-extendable later).
- Caches as needed (e.g. last transcript offsets per session).

## 12. Extensibility (designed-for, not built)
- **More CLIs:** add `SessionSource` adapters (Codex, Gemini).
- **Care/Tamagotchi:** populate `AIMon.care`; add decay + reactions in the Brain.
- **Richer art / 3D:** new `AppearanceProvider` implementations.
- **External providers:** more `SpeechProvider`s.
- **Audio:** a future output channel parallel to bubbles.

## 13. Build, Run & Verification
- **Structure:** SwiftPM package, executable target that creates `NSApplication`,
  `NSApp.setActivationPolicy(.accessory)`, builds `NSStatusItem` + windows in code.
- **Run:** `swift run` from CLI; no Xcode required (Xcode optional for debugging).
- **Verification reality:** the assistant can compile and reason about the code but cannot
  visually run a floating-window GUI in its sandbox. So we build in small, runnable
  increments and **the user launches each increment and eyeballs it**. Each milestone ends
  with a concrete "run this, you should see X" check.

## 14. Testing Strategy
- **Unit-testable core (no GUI):** transcript parsing → `SessionEvent`s (fixture JSONL
  files), Registry binding/minting, trait/appearance determinism (same seed → same
  output), template selection, provider-selection fallback logic, speech-cadence/cooldown
  gating.
- **Mockable boundaries:** `SessionSource`, `SpeechProvider`, clock (for cadence tests).
- **Manual/visual:** windowing, animation, interaction — via the per-milestone run checks.

## 15. Risks & Mitigations
- **Overlay window behavior** (always-on-top, non-activating, click-through, multi-space):
  the standard risk for this app — *mitigated by choosing AppKit/SpriteKit*, where these are
  well-trodden. Still validated by an early runnable window spike.
- **FSEvents heuristics** for "waiting"/"ended" can be fuzzy: mitigated by the optional
  hooks tier for precision.
- **Speech intrusiveness**: mitigated by conservative defaults, cooldowns, focus/quiet mode.
- **Transcript format drift** (Claude Code changes its JSONL): isolate parsing behind the
  adapter; fixture-test it; degrade gracefully to coarse signals.
- **Privacy**: everything local by default; external LLM is opt-in; prompts avoid leaking
  raw secrets; loopback-only IPC.

## 16. Milestones / Build Order (to be detailed in the plan)
1. **Floating-window spike:** one transparent, always-on-top, draggable SpriteKit window
   showing a static procedural monster. Proves the riskiest piece. *(Run check.)*
2. **Procedural appearance + Registry:** seed→monster, persistence, naming.
3. **Session Watcher (baseline FSEvents):** real spawn/despawn from live Claude Code
   sessions; coarse states.
4. **Companion Brain + Template speech:** state machine, bubbles, cadence/cooldown — fully
   offline.
5. **Transcript "reads the work":** content-aware summaries feeding context.
6. **Speech Engine LLM tiers:** Ollama, then external provider.
7. **Optional hooks tier + Settings/menu-bar polish + onboarding.**
8. **Multi-session hardening:** several monsters at once, positions, focus mode.

## 17. Open Questions / Deferred
- Exact default speech cadence numbers (tune during build 4).
- Default local Ollama model recommendation.
- Whether to ship a tiny hook helper binary vs. a `curl` one-liner for the hook command.
- Stable-management UI depth (rename, rebind, "release" a monster).
