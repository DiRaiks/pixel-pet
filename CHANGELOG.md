# Changelog

The project was built in milestones; each was merged into `main` once it had been checked live. All entries date from 2026-10-19.

## Unreleased

### Added
- **More moments.** A "?" when an agent waits for an answer rather than a permission; lying spent with a clock when a limit is used up; refilling when the 5-hour window resets; little copies popping out for subagents and coming back; an accordion squeeze when Claude compacts its context (new `PreCompact` hook, added to existing connections at launch); droopy on a low battery and a lightning bolt when plugged in; a tumbling throw that splats against the side of the screen; dizzy after being shaken; a lamp and tea after 11 pm; now and then a hookah break when nothing's going on (a setting turns it off).
- **YubiKey touch hint.** When a GPG signature waits for the key's button, the cube holds up a little YubiKey with its pad blinking, then cheers with a check mark once it's touched. It reads a single smart-card message from the system log with a filtered `log stream` that ends with the app. A setting turns it off.
- **Codex support.** Codex agents show as blocks on the left of the cube, Claude Code stays on the right. They are read from Codex's session files in `~/.codex/sessions`, so every Codex surface works (CLI, IDE extension, desktop app) and nothing needs installing. Finished, failed and interrupted turns count like Claude's for the cube's mood and celebrations. Codex limits (5 hours and weekly) show in the status panel and the menu, from the session files and a free `codex app-server` request. A setting turns it off. Codex sessions can't show as waiting for approval: that isn't written to the files.
- README pictures: animated states, looks, card screenshots and usage examples, generated with the new `--export-readme` flag.

### Changed
- **Livelier work.** While agents work the cube now has moments at the keyboard every 45–120 s (a sip of coffee, a stretch, a pause to think, a burst of fast typing), looks over at the agent blocks when one changes, and gets a mug after 10 minutes and a headband after 30 of work, counted across turns with pauses of up to 10 minutes allowed.
- **Talking pose** moved one pixel right, clear of the new left column.
- **Going home:** drop the pet anywhere along the top edge of a screen (at the edge, above it, or within 60 pt below) and it slides into that screen's home. Before, it had to land within 90 pt of the notch or burrow in the middle.

### Fixed
- **Moving the pet:** dropping it home, throwing it and sending it home or out from the menu now actually move the window. On macOS 26 and later the window animator ignores `setFrameOrigin`, so the pet stayed where it was let go. When dropped into its home, that could be above the top edge of the screen: out of sight, or showing only the bottom of a peeking cube that could not be grabbed. Cards also land exactly next to the pet now, instead of 6 pt off.
- **Pulling out of home:** a short tug is enough. Before, letting go anywhere within 90 pt pulled the pet right back in; now it returns only when released within 24 pt of its seat.
- **Quick question:** fenced code blocks in answers show as monospaced blocks. Before, they collapsed into one line that started with the language tag, like `bash git reset --soft HEAD~1`.
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

Checked the assumptions behind the plan: hooks from desktop sessions, statusline, `claude -p`, rendering cost, notch geometry, Translation and hook latency. The findings that still matter are in [DEVELOPMENT.md](docs/DEVELOPMENT.md#findings-worth-knowing).
