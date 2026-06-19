# AIMon — Game Mechanics

How the creatures ("aimons") work under the hood. All values are from the current source.

## Identity — deterministic per project

Every aimon is derived from the **project's working directory path** (cwd), so the same project
always shows the same creature, forever (even if the save file is deleted).

- **Seed** = FNV-1a 64-bit hash of the cwd.
- From that seed (via separate mixed streams, so they vary independently) come the creature's:
  **appearance** (color, shape, eyes), **name** (Pokémon-style invented morphemes), **rarity**, and
  **base personality**.
- You can't reroll a project's creature — it's fixed by the path. A different folder = a different
  creature.

## Rarity — the gacha roll

Rolled from the seed, with these odds (fixed cumulative weights out of 1000):

| Rarity | Chance |
|---|---|
| Common | 50% |
| Uncommon | 30% |
| Rare | 13% |
| Epic | 5.5% |
| Legendary | 1.3% |
| Mythic | 0.2% |

Rarity is **per project** (deterministic), not a per-launch dice roll. It affects three things:
1. **Trait budget** (rarer = more personality points — see below).
2. **Appearance** — accent spots, brighter/more-saturated body, and a shimmering "foil" rim on
   Legendary/Mythic.
3. **Aidex card styling** — frame color, stars (1–6), foil sheen, glow.

## Personality — a fixed point budget

Five traits, each 0–100: **enthusiasm, patience, chaos, wisdom, snark**.

Instead of rolling each trait independently (which clustered everything near max), each rarity has a
**fixed pool of points** spread across the five traits — so personalities are lean, spiky, and
unique:

| Rarity | Total points |
|---|---|
| Common | 150 |
| Uncommon | 185 |
| Rare | 220 |
| Epic | 255 |
| Legendary | 300 |
| Mythic | 350 |

The split is seed-weighted (random shape, exact total). The **dominant trait** sets a coarse
*archetype* — cheerful / grumpy / chill / dramatic — used to pick template lines.

## XP & Evolution

Aimons gain **XP** from being around while you work:

| Source | XP |
|---|---|
| A genuinely new session starts (greeting) | +3 |
| The detected activity changes (edit / run / test / error / waiting) | +1 each |
| It shares an idle musing | +1 |

> Relaunching the app does **not** grant XP — only real activity does.

**Three stages**, by total XP:

| Stage | XP |
|---|---|
| 1 | 0–7 |
| 2 | 8–24 |
| 3 | 25+ |

When a creature evolves it:
- Gains **+30 points per tier** into its "maturity" traits (wisdom +14, patience +10,
  enthusiasm +6 per stage; capped at 100). Chaos and snark are left alone — they're character.
- **Changes how it looks**: Stage 2 sprouts little horns; Stage 3 adds a bright core gem; both get
  brighter with a slight hue drift.
- **Re-renders live**, hops, and announces *"✨ I evolved!"*.

The traits shown in the Aidex and used for speech are the **effective** personality (base budget +
evolution bonus).

## Behavior — personality drives how it acts

Beyond *what* they say, traits set *how* they act:

- **Talkativeness** = mostly enthusiasm + snark + impatience, minus a little wisdom.
  - **Speech cooldown** (min gap between any two lines): ~3s (chatty) … ~12s (reserved).
  - **Idle musing interval**: chatty ≈ every 3–7 min; reserved ≈ every 8–12 min (first one comes
    sooner, ~1.5–3 min after appearing).
  - **Idle chance**: reserved creatures (≈40%) sometimes just stay quiet; chatty ones (≈100%)
    always chime in.
- **Liveliness** = enthusiasm + chaos → the idle bob's **height** (bigger) and **speed** (faster).

Recomputed whenever a creature evolves (a matured creature gets calmer/wiser, so it quiets down a
bit).

## Speech — how lines are generated

**When** an aimon speaks (each gated by its cooldown, and only while visible):
- A session **starts** (greeting — only for sessions opened *after* the app launches; ones already
  running at launch stay quiet).
- A session **joins** or **leaves** the project (the count changes).
- An **idle** stretch (a random musing).
- **Activity**: it reads the live session transcript and reacts — but **only to tests running and
  errors**. Editing / running / waiting are detected (and earn XP) but deliberately *not* spoken,
  to avoid being chatty.

**How** a line is produced — two tiers, "works without, better with":
1. **Template floor** (always available, fully offline): hand-written line pools chosen by
   *(trigger × archetype)*.
2. **Local LLM upgrade** (optional): if an **Ollama** server is running at `localhost:11434`, the
   app sends a persona-driven prompt to `/api/generate` (model **`llama3.2:3b`**, temperature 0.9,
   ~40 tokens, non-streaming). The persona is written from the creature's strongest traits, so each
   one sounds distinct. The prompt asks for one short in-character sentence (≤14 words, no emoji, no
   file paths).

**The race**: when an event fires, the app waits up to **4 seconds** for Ollama. If it answers in
time, that line is shown; otherwise the instant template is used. Exactly **one** bubble per event.
Bubbles stay up ~10–24s, scaled to how much there is to read.

### About models / Ollama
- The app **does not download or manage any models.** It simply *calls* Ollama if it happens to be
  running. To get LLM-flavored speech you install Ollama yourself and `ollama pull llama3.2:3b`.
- **No Ollama? Totally fine** — you just get the template lines, which cover every situation.

## When do aimons appear at all?

- The app polls every ~2 seconds for live **Claude Code** (`claude`) processes and shows **one
  monster per project directory** that has a live session. Close the session → the monster leaves.
- No Claude Code sessions → no monsters. (The Aidex still shows everything you've ever collected.)

## Interacting

- **Drag** to move · **scroll** to resize · **single-click** = re-show its last line (or a greeting)
  · **double-click** = bring that session's terminal app to the front.
- Menu bar (👾): **Show/Hide** (hidden = silent and out of the way), **Open the Aidex** (⌘S),
  **Quit**.

## Where it's all saved

`~/Library/Application Support/AIMon/registry.json` — per project: id, seed, name, rarity, base
personality, XP, timestamps, and last window position. If deleted, identities re-mint identically
from the path (but XP and positions reset).
