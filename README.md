# AIMon

Pixel-art desktop companions for your coding sessions.

AIMon is a macOS menu-bar app that spawns a small pixel-art creature — an *aimon* — for the project
you're working in. Each one is generated deterministically from the project, with its own
appearance, name, rarity, personality, and backstory. It watches what you do, reacts to tests and
errors, speaks (via built-in lines or a local model), earns experience, and evolves over time.

## Features

- One creature per project, generated deterministically from the project path.
- Reactive speech: it comments on sessions starting, tests running, and errors — offline with
  built-in lines, or richer and more in-character through a local model (Ollama).
- Personality system: five traits (enthusiasm, patience, chaos, wisdom, snark), budgeted by rarity,
  that shape what a creature says, how often it speaks, and how lively it moves.
- Rarity and evolution: rarities from Common to Mythic affect appearance; creatures earn experience
  from real activity and evolve through three stages.
- The Aidex: a gallery of collectible cards — one per creature — that flip to reveal each one's
  backstory.
- Drag to move, scroll to resize, single-click to repeat the last line, double-click to focus the
  session's terminal.

## Requirements

- macOS 13 (Ventura) or later
- Claude Code (more coding agents planned) — creatures track its live sessions
- Optional: [Ollama](https://ollama.com) for model-generated speech; without it, built-in lines are used

## Install

From source:

```
git clone https://github.com/chvanikoff/aimons.git
cd aimons
swift run AIMon
```

Or build a distributable disk image with `./scripts/package-dmg.sh`. AIMon runs as a menu-bar agent
— there is no dock icon or main window.

## Speech (optional)

Without Ollama, creatures speak using built-in template lines that cover every situation. For
richer speech, install Ollama and pull a small model:

```
ollama pull llama3.2:3b
```

Toggle Ollama, choose an installed model, or download the recommended one from the Settings menu
item.

## How it works

See [docs/GAME-MECHANICS.md](docs/GAME-MECHANICS.md) for the full breakdown: rarity odds, the
trait-point budget, experience and evolution, and the tiered speech engine.

## Development

The code is split into a pure, unit-tested core library (`AIMonCore`) and the macOS app (`AIMon`).

```
swift test     # unit tests
swift build    # debug build
./scripts/package-dmg.sh   # release .app + .dmg
```

## License

[MIT](LICENSE)
