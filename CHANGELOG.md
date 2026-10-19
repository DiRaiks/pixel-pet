# Changelog

The project was built in milestones; each was merged into `main` once it had been checked live. All entries date from 2026-10-19. The detailed Russian log is in [docs/SPEC.md](docs/SPEC.md#журнал-изменений).

## Unreleased

### Fixed
- **Dragging:** the grabbing hand drawn over the cube is gone. It was left over from the prototype, and since you hold the cube by the middle it showed as a stray triangle above its head.

### Docs
- Added an English README, architecture and development guides, and this changelog.

## Animations v2

- **Frame timing.** Every frame has its own duration: key poses are held and in-betweens are quick. One timer fires per frame and never stretches a frame.
- **New style.** Hue-shifted shading with two shade steps, a rim light and a colored outline, plus blush and breathing through the highlight.
- **Looks.** Skins (lavender, mint, peach, graphite) and accessories (glasses, headphones, cap), chosen in settings.
- **Rotation.** Sprites rotate with a 3×3 supersampled majority vote. Accessories turn with the body, while the face stays upright.
- **Redrawn states.** Working (typing on a keyboard), sleep (nightcap and bubble), error (shake, then dizzy) and the landing (jelly bounces).
- **New states.**
  - Yawn and tumble, played as idle fidgets every 1.5–4 minutes.
  - Shy, after the cursor rests on the cube for 2 s.
  - Angry, after 5 clicks within 3 s.
  - A somersault with confetti when a turn of 10+ minutes finishes.
- **Debug.** New `--export-sprites` flag.

## M8: Polish

- **Settings window.** Size, do not disturb, reactions, sleep, launch at login, hooks and statusline, question model, event log, translation languages and Accessibility.
- **Welcome window.** Shown on first launch.
- **Launch at login.** Uses `SMAppService`; the "requires approval" case is handled.
- **`scripts/install.sh`.** Installs the app into `~/Applications`.
- **Reduce Motion.** No jumps, throws or card animations. Alarm states hold one frame, agent blocks stop spinning, and skipped events show a held frame for 1.5 s instead.

## M7: Desktop reactions

- Eyes follow the cursor, and the cube glances at the app you switch to.
- It dims over fullscreen apps.
- It falls asleep after a period without input, hops when you return and greets you after the Mac wakes.
- No extra permissions are needed. Idle CPU stays at 0.5–0.8%.

## M6: Quick question

- **⌃⌥K** opens a card that streams a `claude -p` answer (haiku by default, no tools).
- Follow-ups use `--resume`.
- Each run's events are bound to their own conversation and turn.
- Question sessions are cleaned up on "New", on quit and on launch.

## M5: Translation

- **⌃⌥T** translates the selection. It is read through Accessibility, with a ⌘C fallback that restores the clipboard exactly.
- **Privacy.** Password fields and an empty selection are never read through ⌘C.
- **Engines.** Apple Translation works offline (about 120–200 ms en↔ru), with an optional "via Claude" button.

## M4: Home

- The cube can live in the notch, or in a drawn burrow on screens without one.
- It peeks out for alerts and errors.
- A throw or drop near home pulls it in.
- **Do not disturb (⌃⌥P)** keeps it home except for errors.
- It is re-seated after display sleep or unlock.

## M3: Limits and status panel

- **Limits** come from the `rate_limit_event` of a tiny, rate-limited `claude -p` probe, and from the statusline of terminal sessions. Observations are merged per window.
- **Status card** shows sessions and limits.
- **Low-limit state.** The body drains from the top as the 5-hour window is used up.

## M2: Agents

- Claude Code hooks for 12 events forward payloads through `sh` + `nc` to a unix socket.
- A session registry tracks working, waiting, failed and subagents.
- Agent blocks appear next to the cube, and the menu bar shows a counter.
- The settings merge is safe: backed up, idempotent and reversible.

## M1: Skeleton

- SwiftPM project and app bundling.
- A transparent, non-activating panel with a `CALayer` renderer of procedural frames ported from the prototype.
- Alpha hit-testing, dragging with throws, and a menu-bar icon.

## M0: Spike

Checked the assumptions behind the plan: hooks from desktop sessions, statusline, `claude -p`, rendering cost, notch geometry, Translation and hook latency. See [docs/spike-notes.md](docs/spike-notes.md).
