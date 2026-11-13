# Changelog

The project was built in milestones. Each milestone was merged into `main` after it was tested live. All entries are from 2026-10-19.

## Unreleased

### Added
- **Reacts to what you do.** When no agent is working, the cube reacts to you: keys pop up over it and it nods while you type, it holds a gamepad over games, eats popcorn over videos and wears glasses over code. It also gets dizzy after fast Space switches, watches an app's icon bounce when it opens, waves goodbye to an app you used for a long time, waves off an ejected USB stick, waves at a copy of itself on a new display and flips a badge when the keyboard layout changes. It needs no permissions and reads only the time since your last key press, never the keys; the setting is Settings → "Notice what I'm doing".
- **Codex subagents.** Agents that a Codex session starts now count as its subagents, as in Claude Code: a dot on its block, "+N sub." in the status card, and copies that pop out and come back. Codex's own helper threads (approval review, compaction) still don't show.
- **Updates.** The downloaded app checks for a new version once a day; when there is one, a box floats down on a balloon next to the cube. Click the cube to see what's new, then click Update: the cube unpacks the box, Sparkle checks the signature and Developer ID before it installs, and after the restart the cube pops out of a big box. Settings → Updates turns the check off (then the app never goes online by itself) or installs updates automatically, the menu has "Check for Updates…", and builds from source don't check.
- **YubiKey notification.** When the key waits for a touch, a notification banner appears too, in both languages, even when the cube is in sight. Settings → YubiKey → "Also send a notification" turns it off and keeps only the cube.
- **Works harder with more agents.** With 2–3 agents working at once, the pet types with both hands and sweats. With 4–5 it gets red cheeks and is out of breath; with 6 or more, steam comes off its top and sparks fly from the keys. Claude Code and Codex agents count together.
- **Paperclip character.** Settings → Character now has a third pet: a bent wire with two round eyes, in any of the colors. It plays every state the cube does and wears the headband, nightcap, headphones and party hat on its loop. It hangs a little further out of its home so you can see its eyes.
- **New installer window and app icon.** The DMG opens on a lavender window with the cube asking, a pixel arrow from Pixel Pet to Applications and a one-line hint. The new app icon shows a large cube on a lavender tile, so it is easier to find in the Dock. The app itself is now notarized and stapled, so it opens without a network check even after you copy it out of the DMG.
- **Voice input.** Turn it on in Settings → Listening, then press and hold the cube (or ⌃⌥L) and speak: the cube holds out a mic, and your words appear in a card as they are recognized. When you let go, the cube nods and you can send the text to Claude, the translator or the clipboard. Speech is recognized on your Mac by the system dictation model (Russian works), nothing is recorded or sent, and you choose the language in Settings → Listening.
- **A candle on some nights.** Every third night, a candle replaces the desk lamp: it flickers, lights the cube with a warm glow and burns down through the night, leaving drips and then a pool of wax by morning. The light stays the same all night. On holidays the lamp stays, because the pumpkin and the fir tree are there.
- **Drop a file on the cube to ask about it.** The cube opens its mouth, swallows the file and opens the question card with the file attached and suggested questions. It takes text, code, PDFs (their text) and images (scaled down), up to 3 at a time; it shakes its head at folders and binary files. The file goes to Claude only inside the question you send, and the CLI still runs without tools.
- **Break reminders.** After an hour of work without five minutes away, the cube yawns and holds up a hot mug. Click to put it off for 15 minutes; otherwise it comes back every 20 minutes until you take a break, and the cube hops when you return. It reads only the system idle time, the status panel shows the time when a reminder is close, and you set it in Settings → Breaks (45, 60, 90 minutes or off).
- **Weekly recap.** On Monday morning the cube reads a newspaper until you click it; the click (or the menu) opens last week's recap. It shows time per day for Claude Code and Codex, top projects, the longest turn, waits, answers given in the cube, the limit, and the change from the week before. Daily totals per project folder are saved in `~/.pixelpet/stats.json` (no text, 8 weeks), and the setting is Settings → Weekly recap.
- **Silent notifications.** When the cube is out of sight, a banner with no sound tells you when an agent needs permission or an answer, finishes a long turn or fails, or when the YubiKey waits for a touch. There is one banner per session, updated and cleared as things change, and a click opens the app the session runs in. Banners show only the project and what happened; the setting is Settings → Notifications, and the app now has an icon: the cube.
- **Live activity in the status card.** Each session shows its current step (for example "Runs `npm test`", "Edits `App.swift`", "Thinking", "Waiting for permission: `rm -rf build`") with a seconds counter, how long the turn has run and how many steps it took. Finished sessions show when they ended and how long they worked. Only a few words of each tool call are kept, and only in memory.
- **Answer permission requests from the cube.** When Claude Code asks for permission, a card next to the cube shows the command or file and the reason. Choose Allow, Deny, "don't ask again" (when Claude Code offers a rule), or send it back to the terminal, VS Code or the Claude app (which comes to the front); the Claude app also keeps its own dialog, and the first answer counts. The hook waits up to a minute and only while the pet is shown, the command is never stored, and a setting turns it off.
- **Reacts to your Mac.** The cube puts on headphones when they connect (and keeps them on in every pose), bobs to music, stays quiet under a recording light while the mic or camera is in use, and sweats with a thermometer when the Mac is hot. It shows a crossed-out Wi-Fi when the network is gone, a yellow battery in Low Power Mode, cheers at 100%, shows ✌️ for screenshots, greets dark and light mode, and wears a party hat on Friday evenings. Click to put away an ongoing reaction until it ends; it uses only on/off signals and no permissions, and "React to the Mac" in Settings turns it off.
- **CI and releases.** GitHub Actions builds and tests every push and pull request on macOS 26 and checks the release bundle and the scripts. A version tag builds a DMG and publishes it as a GitHub release, signed, notarized and stapled when the Developer ID and notary secrets are set (`scripts/release.sh`). The secrets live in a `release` environment that only `v*` tags can use, so branches and pull requests can't read them; a release needs a `v*` tag signed with the maintainer's YubiKey (checked against the two pinned signing subkeys) on a commit already on `main`, and `main` accepts only signed commits.
- **English interface.** The interface is now in English by default. Settings → Language switches it to Russian right away, menus included.
- **What the agent is doing.** While the cube types, a bubble above it shows the latest Claude Code tool: a terminal for commands, a magnifier for searches, a page of text for reading and a pencil for edits.
- **Nudges and small joys.** The cube waves when an agent has waited for you for over a minute (and again about every 45 s), and launches a rocket when an agent's `git push` succeeds (the command is only matched, never stored). Rub the cursor back and forth over the pet for hearts, and now and then it sneezes (LM sneezes water). A jack-o'-lantern shows in the last week of October and a small fir tree around New Year.
- **LM character.** LM is a second character next to the cube: a round drop under a two-tone diamond, with big white eyes; switch to him in Settings → Character. LM keeps his own aqua colors, wears no accessories and plays the same states and moments as the cube, but when idle he catches a drop on his diamond or melts into a puddle and comes back together instead of rolling over. His pupils follow the cursor, and he peeks out of his home a little less, showing his eyes and the round bottom of the drop.
- **Call reminders.** With "Remind about calls" on, the cube reads your Mac's calendars and shows a headset and a ticking alarm clock 5 minutes before a meeting with a call link; the clock rings in the last minute, and the status card shows the next call. Click the cube to dismiss the reminder for that call. It is off by default and asks for calendar access when you turn it on.
- **More looks.** Four colors (sky, sakura, vanilla, and night for dark wallpapers) and eight accessories (sunglasses, beanie, crown, bow, flower, propeller hat, scarf, mustache). "New every day" works for both: a different look each day, the same all day.
- **More moments.** A "?" when an agent waits for an answer, not a permission; lying tired with a clock when a limit is used up, and refilling when the 5-hour window resets; small copies popping out for subagents and coming back; an accordion squeeze when Claude compacts its context (a new `PreCompact` hook, added to existing connections at launch). Also: droopy on a low battery and a lightning bolt when plugged in, a tumbling throw that splats against the side of the screen, dizzy after shaking, a lamp and tea from 10 pm to 5 am (by the Mac's clock), and sometimes a hookah break when nothing is happening (a setting turns it off).
- **YubiKey touch hint.** When a GPG signature waits for you to touch the key, the cube holds up a small YubiKey with a blinking pad, then cheers with a check mark after you touch it. It reads one smart-card message from the system log with a filtered `log stream` that ends with the app. A setting turns it off.
- **Codex support.** Codex agents show as blocks to the left of the cube; Claude Code stays on the right. They are read from Codex's session files in `~/.codex/sessions`, so every Codex app works (CLI, IDE extension, desktop app) with nothing to install, and finished, failed and interrupted turns affect the cube's mood and celebrations like Claude's. Codex limits (5-hour and weekly) show in the status panel and the menu, a setting turns Codex support off, and Codex sessions can't show as waiting for approval because the files don't record it.
- **README pictures.** The README now has animated states, looks, card screenshots and usage examples, made with the new `--export-readme` flag.

### Changed
- **Clearer small icons.** The meeting alarm clock is now a round red clock with brass bells and two hands, placed so the bells stay on the canvas. The on-air bubble shows a studio mic on a stand with a separate recording dot, the break bubble a teal coffee mug with teal steam, and the YubiKey has a bigger silver plug and keeps clear of the outline. The battery for Low Power Mode and for a low battery is now in one place, top left.
- **Calmer long loops, and a press you can feel.** States that can last for hours now move less: typing, idle, sleep, music, overheating, the offline sign, the tired battery and the meeting clock are all calmer. An error's red flash and shake, and the low-limit shake, play once at the start; only the dizzy part repeats. When you press the pet, it moves down a pixel at once and comes back up when you let go, start dragging or it starts listening.
- **Livelier work.** The typing loop is now about 12 s of bursts at different lengths and speeds, with different pauses (a look at the screen, a blink, a short stop), instead of the same 1.2 s loop. While agents work, every 45–120 s the cube sips coffee, stretches, stops to think or types fast, and it looks at the agent blocks when one changes. It gets a mug after 10 minutes of work and a headband after 30, counted across turns with pauses of up to 10 minutes.
- **Subagents at the keyboard.** When subagents start while the cube is typing, it stays at the desk: a hard keystroke sends a small copy to the agent blocks, and the copy flies back into the keys when they finish. The bigger version, with copies popping out on both sides, still plays when the cube is resting.
- **Talking pose.** Moved one pixel right, away from the new left column.
- **Going home.** Drop the pet anywhere along the top edge of a screen (at the edge, above it, or up to 60 pt below) and it slides into that screen's home. Before, you had to drop it within 90 pt of the notch or the burrow in the middle.

### Fixed
- **A call isn't music.** With headphones on during a call, clicking the call away no longer makes the cube dance to the call. Music never shows while the mic or camera is on. Sound from a call app (Zoom, Teams, Slack, Telegram, FaceTime and others) or from an app that records while it plays (a call in the browser) doesn't count as music, even with the mic muted.
- **Props stay clear of hats and the outline.** A jump peaks lower when a hat would go off the top of the canvas, so a beanie keeps its pompom and a party hat stays visible. The tool bubble no longer cuts into a cap, crown or flower, a dropped file waits above a hat, and the roll, wave, rocket launch and hookah step to their spot and back instead of jumping several pixels. Stars, the anger mark, petting hearts, sneeze mist and the sleep bubble keep a pixel of space from the outline (and above a hat).
- **Animation glitches.** The "quiet" dots while listening no longer go past the canvas edge and now appear one by one over the mic, and the screenshot flash lights only the pet instead of a white square on the desktop. Celebration sparkles follow the body, and cheeks stay in place when the eyes look aside. The somersault now tilts more frame by frame instead of looking frozen, a throw no longer spins back a quarter turn before landing, and the hot thermometer no longer cools down every loop.
- **Cancelling a Claude job stops it at once.** If you closed the translation or question card before the `claude` process started (on a busy Mac), the process kept running in the background until its own timeout. Now it stops as soon as it starts.
- **Cards no longer cover the cube.** A card that grew after opening (for example, while a translation came in) could end up over the cube and hide its buttons. Now a card that no longer fits moves below the cube, or beside it when there is no room on either side.
- **Marks over tall hats.** The spent-limit clock and the "!" now move aside for a propeller hat, crown, beanie or party hat, as they already did for LM's diamond, instead of merging into the hat.
- **No music from system sounds.** The charger chime (PowerChime) or Siri can keep the speakers open for hours after a short sound, so the cube bobbed to music that wasn't playing. Now these macOS services are ignored, while a music player running next to them still counts.
- **No "working" after a turn ends.** After each turn, a helper in the Claude app runs a tool under the session's id (shown as `Runs true`), so the session looked busy for 5 minutes. Tool calls from inside an agent (`agent_id`) no longer wake a session between turns.
- **Resumed sessions show again.** A session that the Claude app unloaded and later resumed with the same id stayed hidden forever. Now a new start or prompt brings it back.
- **Quick-question cleanup deletes only its own folder.** It used to delete every `~/.claude/projects` folder ending in `-pixelpet-claude`, which could include the session history of your own project with that name. Now it removes only the exact folder Claude Code makes for the pet's workdir, and the old folder that earlier builds used for the limits check.
- **The hook answers only permission requests.** Any other reply over the socket is dropped, so nothing listening there can give other hooks a decision.
- **Release workflow.** Signing secrets reach only the steps that use them, and `actions/checkout` is pinned to a commit.
- **No mug right after the Mac wakes.** Time asleep (no check for longer than a break) now counts as a break, whatever the idle time says after waking.
- **Quitting stops the pet's own `claude` runs.** They used to keep running after the app quit, until their own timeout. `pkill` now also quits the app normally.
- **Esc ends a turn at once.** No hook reports a turn stopped with Esc, so the cube showed "Thinking" for 5 minutes, or forever if a tool was running. Now the app checks a quiet session's transcript for the interrupt line.
- **LM's newspaper is below his eyes.** The recap newspaper covered most of his face; for LM it is now two rows lower.
- **No dancing to silence after unplugging headphones.** A paused player's open stream moved to the speakers and made them look busy. Now a stream moved to a new output counts as music only after it stops once.
- **Translation card.** A second translation in the same languages stayed on "Translating…" forever; now it runs again. Long results scroll inside the card instead of being cut at 14 lines, and the card stays on screen as it grows.
- **SIGPIPE crash.** A `claude` run that exited before reading its input (a crash or a timeout kill) could crash the whole app with SIGPIPE. Pipes and the hook socket now ignore SIGPIPE, and so does the app.
- **Background subagents.** A turn that ended while background subagents were still running showed as done. Now the session stays working until the last one stops, then finishes and celebrates. A new message no longer forgets subagents that are still running.
- **Moving the pet.** Dropping it home, throwing it, and sending it home or out from the menu now really move the window; on macOS 26 and later the pet stayed where you let go. A pet dropped home could end up above the top of the screen, out of sight or showing only a bottom edge you could not grab. Cards now also sit exactly next to the pet instead of 6 pt away.
- **Pulling out of home.** A short pull is now enough. Before, letting go anywhere within 90 pt pulled the pet back in; now it goes back only when you let go within 24 pt of its seat.
- **Code blocks in quick answers.** Fenced code blocks in answers now show as monospaced blocks. Before, they collapsed into one line that started with the language name, like `bash git reset --soft HEAD~1`.
- **No hand when dragging.** The grabbing hand drawn over the cube is gone. It was left from the prototype and showed as a stray triangle above the cube's head.

### Docs
- **New docs.** Added an English README, architecture and development guides, and this changelog.

## Animations v2

- **Frame timing.** Each frame has its own length: key poses stay longer and in-between frames are quick. One timer fires per frame and never stretches a frame.
- **New style.** Hue-shifted shading with two shade steps, a rim light and a colored outline, plus blush and breathing shown through the highlight.
- **Looks.** Skins (lavender, mint, peach, graphite) and accessories (glasses, headphones, cap), chosen in settings.
- **Rotation.** Sprites rotate with a 3×3 supersampled majority vote. Accessories turn with the body, and the face stays upright.
- **Redrawn states.** Working (typing on a keyboard), sleep (nightcap and bubble), error (shake, then dizzy) and landing (jelly bounces).
- **New states.**
  - Yawn and tumble, played as idle fidgets every 1.5–4 minutes.
  - Shy, after the cursor rests on the cube for 2 s.
  - Angry, after 5 clicks within 3 s.
  - A somersault with confetti when a turn of 10+ minutes ends.
- **Debug.** New `--export-sprites` flag.

## M8: Polish

- **Settings window.** Size, do not disturb, reactions, sleep, launch at login, hooks and statusline, question model, event log, translation languages and Accessibility.
- **Welcome window.** Shown on first launch.
- **Launch at login.** Uses `SMAppService` and handles the "requires approval" case.
- **`scripts/install.sh`.** Installs the app into `~/Applications`.
- **Reduce Motion.** No jumps, throws or card animations. Alarm states hold one frame, agent blocks stop spinning, and skipped events show a still frame for 1.5 s instead.

## M7: Desktop reactions

- **Eyes and glances.** Eyes follow the cursor, and the cube looks at the app you switch to.
- **Fullscreen.** It dims over fullscreen apps.
- **Sleep and wake.** It falls asleep after a time without input, hops when you come back and greets you after the Mac wakes.
- **Light on resources.** No extra permissions are needed. Idle CPU use stays at 0.5–0.8%.

## M6: Quick question

- **Quick question (⌃⌥K).** Opens a card that streams a `claude -p` answer (haiku by default, no tools).
- **Follow-ups.** Follow-up questions use `--resume`.
- **Separate runs.** Each run's events are tied to their own conversation and turn.
- **Cleanup.** Question sessions are cleaned up on "New", on quit and on launch.

## M5: Translation

- **Translate (⌃⌥T).** Translates the selected text. It reads the selection through Accessibility, with a ⌘C fallback that restores the clipboard exactly.
- **Privacy.** Password fields and an empty selection are never read through ⌘C.
- **Engines.** Apple Translation works offline (about 120–200 ms en↔ru), with an optional "via Claude" button.

## M4: Home

- **Home.** The cube can live in the notch, or in a drawn burrow on screens without one.
- **Peeking.** It peeks out for alerts and errors.
- **Going home.** A throw or drop near home pulls it in.
- **Do not disturb (⌃⌥P).** Keeps it home except for errors.
- **Back in place.** It goes back to its seat after display sleep or unlock.

## M3: Limits and status panel

- **Limits.** Read from the `rate_limit_event` of a tiny, rate-limited `claude -p` probe and from the statusline of terminal sessions. Data for each window is merged.
- **Status card.** Shows sessions and limits.
- **Low-limit state.** The body drains from the top as the 5-hour window is used up.

## M2: Agents

- **Claude Code hooks.** Hooks for 12 events send their data through `sh` + `nc` to a unix socket.
- **Session registry.** Tracks working, waiting and failed sessions and subagents.
- **Agent blocks.** Blocks appear next to the cube, and the menu bar shows a counter.
- **Safe settings merge.** The merge is backed up, gives the same result when run again, and can be undone.

## M1: Skeleton

- **Project setup.** SwiftPM project and app bundling.
- **Renderer.** A transparent, non-activating panel with a `CALayer` renderer of procedural frames, ported from the prototype.
- **Interaction.** Alpha hit-testing, dragging with throws, and a menu-bar icon.

## M0: Spike

**Assumptions checked.** Hooks from desktop sessions, statusline, `claude -p`, rendering cost, notch geometry, Translation and hook latency. The findings that still matter are in [DEVELOPMENT.md](docs/DEVELOPMENT.md#findings-worth-knowing).
