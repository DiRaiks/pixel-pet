# Changelog

The project was built in milestones; each was merged into `main` once it had been checked live. All entries date from 2026-10-19.

## Unreleased

### Added
- **Drop a file on the cube to ask about it.** It opens its mouth while a file is over it, swallows it, and the question card opens with the file attached and questions to start with. Text, code, PDFs (their text) and images (scaled down), up to 3 at a time; folders and binaries get a shake of the head. The file goes to Claude only inside the question you send; the CLI still runs without tools.
- **Break reminder.** After an hour of work without five minutes away, the cube yawns and holds up a steaming mug; a click puts it off for 15 minutes, otherwise it comes back every 20 minutes until a break. Coming back from it earns a hop; the status panel counts the time when the reminder is near. Only the system idle time is read. Settings → Breaks (45, 60, 90 minutes or off).
- **Weekly recap.** Day sums of agent time, turns, steps, waits and the 5-hour limit, per project folder, in `~/.pixelpet/stats.json` (no text, 8 weeks). On Monday morning the cube unfolds a newspaper and reads it until clicked; the click (or the menu) opens last week's recap: time per day for Claude Code and Codex, top projects, the longest turn, waits, answers in the cube, the limit, and the change from the week before. Settings → Weekly recap.
- **Silent notifications.** While the cube can't be seen, a banner with no sound says when an agent needs permission or an answer, finishes a long turn or fails, and when the YubiKey waits for a touch. One per session, replaced and cleared as things move on; a click opens the app the session runs in. Only the project and what happened. Settings → Notifications. The app has an icon now: the cube.
- **Live activity in the status card.** Each session shows its current step ("Runs `npm test`", "Edits `App.swift`", "Thinking", "Waiting for permission: `rm -rf build`") with a clock that counts seconds, plus how long the turn has run and how many steps it took; finished sessions say when they were done and how long they worked. Only a few words of each tool call are kept, in memory.
- **Answer permission requests from the cube.** Claude Code's permission requests open a card by the cube with the command or file and the reason: Allow, Deny, "don't ask again" when Claude Code offers a rule, or hand it back to the terminal, VS Code or the Claude app (which comes to the front). The Claude app keeps its own dialog alongside, and the first answer counts. The hook waits up to a minute and only while the pet is shown; the command is never stored. A setting turns it off.
- **Reacting to the Mac.** Headphones go on when they connect (and stay on in every pose); the cube bobs to music, keeps quiet under a recording light while a mic or camera is in use, sweats with a thermometer when the Mac runs hot, shows a crossed-out Wi-Fi when the network is gone and a yellow battery in low power mode, cheers at 100%, flashes ✌️ for screenshots, greets dark and light mode, and wears a party hat on Friday evening. A click puts any of the ongoing ones away until it ends. Only on/off signals, no permissions; "React to the Mac" in Settings turns it off.
- **CI and releases.** GitHub Actions builds and tests every push and pull request on macOS 26, checks the release bundle and the scripts. A version tag builds a DMG and publishes it as a GitHub release; with the Developer ID and notary secrets set it is signed, notarized and stapled (`scripts/release.sh`).
- **English interface.** The UI is now English by default; Settings → Language switches it to Russian at once, menus included.
- **What the agent is doing.** While typing, a bubble over the cube shows the latest Claude Code tool: a terminal for commands, a magnifier for searches, a page of text for reading, a pencil for edits.
- **Nudges and small joys.** A wave when an agent has waited on you for over a minute (again every ~45 s); a rocket launch when an agent's `git push` goes through (the command is only matched, never stored); hearts when you rub the cursor back and forth over the pet; a sneeze among the idle fidgets (LM sneezes water); a jack-o'-lantern the last week of October and a little fir over New Year.
- **LM.** A second character next to the cube: LM, a round drop under a two-tone diamond, with big white eyes. "Character" in Settings switches between them; LM keeps his own aqua colors and wears no accessory, and plays the same states and moments as the cube, except that instead of rolling over when idle he catches a drop on his diamond or melts into a puddle and gathers back up. His pupils follow the cursor, and out of his home he peeks a little less than the cube, showing his eyes and the round bottom of the drop.
- **Call reminders.** With "Remind about calls" on, the cube reads the Mac's calendars: a headset and a ticking alarm clock 5 minutes before a meeting with a call link, the clock ringing in the last minute, and the next call in the status card; a click on the cube dismisses the reminder for that call. Off by default; asks for calendar access when turned on.
- **More looks.** Four colors (sky, sakura, vanilla, and night for dark wallpapers) and eight accessories (sunglasses, beanie, crown, bow, flower, propeller hat, scarf, mustache), plus "every day new" for both: a different look each day, the same all day long.
- **More moments.** A "?" when an agent waits for an answer rather than a permission; lying spent with a clock when a limit is used up; refilling when the 5-hour window resets; little copies popping out for subagents and coming back; an accordion squeeze when Claude compacts its context (new `PreCompact` hook, added to existing connections at launch); droopy on a low battery and a lightning bolt when plugged in; a tumbling throw that splats against the side of the screen; dizzy after being shaken; a lamp and tea from 10 pm to 5 am, by the Mac's clock; now and then a hookah break when nothing's going on (a setting turns it off).
- **YubiKey touch hint.** When a GPG signature waits for the key's button, the cube holds up a little YubiKey with its pad blinking, then cheers with a check mark once it's touched. It reads a single smart-card message from the system log with a filtered `log stream` that ends with the app. A setting turns it off.
- **Codex support.** Codex agents show as blocks on the left of the cube, Claude Code stays on the right. They are read from Codex's session files in `~/.codex/sessions`, so every Codex surface works (CLI, IDE extension, desktop app) and nothing needs installing. Finished, failed and interrupted turns count like Claude's for the cube's mood and celebrations. Codex limits (5 hours and weekly) show in the status panel and the menu, from the session files and a free `codex app-server` request. A setting turns it off. Codex sessions can't show as waiting for approval: that isn't written to the files.
- README pictures: animated states, looks, card screenshots and usage examples, generated with the new `--export-readme` flag.

### Changed
- **Livelier work.** The typing loop is now about 12 s of bursts of different length and pace with different pauses between them (a look up at the screen, a blink, a short stop), instead of the same 1.2 s with a smile each time. While agents work the cube also has moments at the keyboard every 45–120 s (a sip of coffee, a stretch, a pause to think, a burst of fast typing), looks over at the agent blocks when one changes, and gets a mug after 10 minutes and a headband after 30 of work, counted across turns with pauses of up to 10 minutes allowed.
- **Subagents at the keyboard.** When subagents start while the cube is typing, it no longer gets up from the desk: a harder keystroke sends a little copy over to the agent blocks, and when they're done it flies back into the keys. The big version, copies popping out on either side, stays for a cube at rest.
- **Talking pose** moved one pixel right, clear of the new left column.
- **Going home:** drop the pet anywhere along the top edge of a screen (at the edge, above it, or within 60 pt below) and it slides into that screen's home. Before, it had to land within 90 pt of the notch or burrow in the middle.

### Fixed
- **Quick-question cleanup removes only its own folder.** It deleted every `~/.claude/projects` folder ending in `-pixelpet-claude`, which would include the session history of a project of yours in a folder by that name; now it removes only the exact folder Claude Code makes for the pet's workdir, and the leftover one older builds used for the limits check.
- **The hook prints an answer only for a permission request.** Anything else coming back over the socket is dropped, so whatever might be listening there can't hand other hooks a decision.
- **Release workflow.** Signing secrets reach only the steps that use them, and `actions/checkout` is pinned to a commit.
- **No mug right after the Mac wakes.** Time asleep (no look for more than a break's length) now counts as a break, whatever the idle time reads after waking.
- **Quitting stops the pet's own `claude` runs.** They used to run on after the app quit, until their own timeout; `pkill` now quits the app the normal way too.
- **A turn stopped with Esc ends at once.** No hook reports it, so the cube kept "Thinking" for 5 minutes (or for good, with a tool running); a quiet session's transcript is now checked for the interrupt line.
- **LM's newspaper sits under his eyes.** The recap paper covered most of his face; it's two rows lower for him.
- **No dancing to silence after unplugging headphones.** A paused player's open stream moves to the speakers and keeps them looking busy; a stream carried over to a new output no longer counts as music until it stops once.
- **Translation card.** A second translation in the same languages sat on "Translating…" for good (a fresh session configuration compared equal to the last one, so it never ran); it now re-runs the configuration. Long results scroll inside the card instead of cutting off at 14 lines, and the card stays on screen as it grows.
- **SIGPIPE.** A `claude` run that exited before reading its input (a crash, a timeout kill) could take the whole app down with SIGPIPE while the text was still being written. Pipes and the hook socket now opt out of SIGPIPE, and the app ignores it.
- **Background subagents.** A turn that ends while background subagents still run kept showing as done; the session now stays working until the last one stops, then finishes and celebrates. A new message no longer forgets subagents that are still running.
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
