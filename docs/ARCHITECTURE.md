# Architecture

Pixel Pet is a single accessory app (no Dock icon, `LSUIElement`) built with SwiftPM. Most of the logic is pure Swift with no AppKit dependency, so it can be unit-tested. The app target wires that logic to windows, timers and system APIs.

## Modules

```
PetCore          pure logic, no AppKit: events, sessions, states, limits, config, geometry, policies
  ├── PetSprites       procedural pixel art: canvas, cube drawing, every state's frames, agent stack
  └── PetIntegrations  unix-socket server, finding and running the Claude Code and Codex CLIs, Codex session files
        └── PixelPet   the app: windows, rendering, input, hotkeys, cards, menus, settings, desktop sensing
```

| Target | Depends on | Holds |
|---|---|---|
| `PetCore` | — | `AgentEvent`, `SessionRegistry`, `PetBrain`, `PetState`, `PetPlayer`, `MotionPolicy`, `UsageLimits` and `Inbound`, `ProbePolicy`, `PetConfig` and `ConfigStore`, `HookSettings` and `HookInstaller`, `HomeSpot` and `HomeGeometry`, `Placement`, `DragTracker`, `Gaze`, `ReactionThrottle` and `Fullscreen`, `TranslationPlan` and `SelectionDecision`, `AskConversation`, `ClaudeStream` and `ClaudeTranslation`, `CodexRollout`, `AnswerText` |
| `PetSprites` | `PetCore` | `PixelCanvas`, `Palette` (`Skin`, `Accessory`, `Look`), `CubeDrawing` (`BodyStyle`), `SpriteFactory`, `AgentStack` |
| `PetIntegrations` | `PetCore` | `EventServer`, `ClaudeLocator`, `ClaudeProcess`, `LimitsProbe`, `ClaudeChat` and `ClaudeAsk`, the `ClaudeTranslation` runner (an extension), `CodexWatcher`, `CodexLocator`, `CodexLimitsProbe` |
| `PixelPet` | all three | `AppDelegate`, `PetController`, `PetPanel`, `SpriteLibrary`, `AgentMonitor`, `StatusMenu`, `StatusPanel` (cards), `TranslationCard`, `AskCard`, `SelectionReader`, `DesktopSensor`, `HotKey`, `SettingsWindow`, `OnboardingWindow`, `HookActions`, `SpriteExport` |

Rule of thumb: when a decision can be stated without AppKit (a priority, a timeout, a privacy rule, a piece of geometry), it lives in `PetCore` with tests. The app target only measures the world and acts on those decisions.

## Data flow

```
Claude Code ──hooks──────► pixelpet-hook ────────┐
Claude Code ──statusline─► pixelpet-statusline ──┤  ~/.pixelpet/pet.sock (one JSON payload per connection)
                                                 ▼
                                           EventServer (serial queue)
                                                 ▼  AsyncStream, in arrival order
                                           AgentMonitor (main actor)
                                Inbound.parse ──┬── hook event ──► SessionRegistry ──► reactions (celebrate, flip)
                                                └── statusline ──► sessions (model, context) + limits
claude -p (LimitsProbe, Ask, Translate) ── rate_limit_event ──► limits (merged)
                                                 ▼
                                PetBrain: base state, agent blocks, drain rows
                                                 ▼
DesktopSensor (cursor, idle, app switches, fullscreen, wake) ──► PetController ◄── input, hotkeys, menu
                                                 ▼
                         PetPlayer (frame clock) ──► SpriteLibrary ──► PetPanel (CALayer contents)
```

## Claude Code integration

### Hooks

`HookInstaller` writes two scripts to `~/.pixelpet/bin/`, sets the folder to mode 700, and merges entries into `~/.claude/settings.json`:

- **Hook command.** The single-quoted script path is registered for 12 events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop` and `SessionEnd`. Each entry has a 5 s timeout. The entries are recognized by their exact command string, which is how install, uninstall and the installed check stay idempotent.
- **Statusline.** It is added only when the user has no `statusLine` of their own. A foreign statusline is reported as such and left alone.

How the settings file is written:

- A missing or blank file counts as empty. Unparseable JSON or an unexpected `hooks` shape is an error; the installer never overwrites data it does not understand.
- Writes go through symlinks and keep the file's permissions. A timestamped backup is made first, and nothing is written if nothing changed.
- `JSONSerialization` re-sorts the keys of the rewritten file. This is a known cosmetic side effect.

`refreshScriptIfInstalled()` runs at launch, so the scripts always match the running build.

The hook script itself is `sh` + `nc -U -w 1`. It measured about 10 ms per call in the spike. It produces no output, always exits 0 and always drains stdin. When `PIXELPET_INTERNAL` is set it does nothing; this is how the pet's own `claude -p` runs stay out of the agent list.

### Socket and parsing

`EventServer` listens on `~/.pixelpet/pet.sock`:

- The socket is mode 600, in a mode-700 folder.
- Each connection carries one raw payload, read until EOF.
- A connection may take at most 1 s, and a payload may be at most 16 MB, because hook payloads can include large tool output.
- A stale socket file is cleared at start. On stop, the file is removed only if it still has our inode.

`Inbound.parse` routes each payload by its shape:

- A payload with `hook_event_name` becomes an `AgentEvent`. The exception is `"Status"`: some CLI versions tag statusline payloads that way.
- A payload with `session_id` plus `model` or `context_window` is a statusline snapshot (model, context %, `rate_limits`).

`AgentEvent.parse` keeps only the session id, cwd and a small `Kind` enum. Prompt text and tool input are dropped right there.

### Session rules (`SessionRegistry`)

- **Creation.** A session is created by any event, not only `SessionStart`: sessions that were already open when the hooks were installed never send one.
- **Working and waiting.** A prompt or a tool start means working. A permission request means waiting. So do the `permission_prompt` and `elicitation_dialog` notifications, and an open `AskUserQuestion` or `ExitPlanMode` call until its matching `PostToolUse`. A Claude desktop turn that ends with a `wrap_up` call carrying a non-empty `ask` also waits after `Stop`.
- **Turn ends.** `Stop` ends the turn, and so does an `idle_prompt` notification. `StopFailure` marks the session as failed.
- **Subagents.** These are tracked between `SubagentStart` and `SubagentStop`, so the post-turn summary agent that stops without having started is ignored.
- **Reactions.** A finished turn earns a celebration only after at least 20 s of active work; time spent waiting for the user does not count. A turn of 10 minutes or more earns the somersault (`finishedBig` → `flip`).
- **Interrupts.** A working session with no tool running and no events for 5 minutes is treated as interrupted, because Esc sends no `Stop`.
- **Expiry.** Sessions with no events for 30 minutes are dropped. Sessions waiting on a permission prompt or an open question tool never go stale; a turn-end question from Claude desktop fades to idle after 30 minutes. Ended session ids are remembered (up to 500), so late events cannot bring them back.

### Turning sessions into a picture (`PetBrain`)

`PetBrain.baseState` picks the state in priority order:

1. error, if a session failed within the last 3 s;
2. alert;
3. low limit (5-hour usage ≥ 85% or weekly ≥ 90%);
4. working;
5. idle.

On top of that base state:

- `restState` turns idle into sleep after `sleepAfterMinutes` without user input. The idle time is read live each time the decision is made.
- At home, `homeState` maps error and alert to `peekHold` and everything else to `burrowed`. Under do not disturb, alerts stay `burrowed` too.
- At home, one-shots become a `peek`, or nothing under do not disturb.

`PetBrain.cubes` maps sessions to agent blocks. A finished session flashes green for 1.5 s.

`nextChange` tells `AgentMonitor` when the picture will change on its own, so a single timer is enough and nothing polls fast.

### Limits

There are three sources, merged window by window. Within one window usage only grows, so the window that resets later wins, and for the same window the higher usage wins:

1. **`rate_limit_event` from every `claude -p` run.** This is the main source. Statusline never runs for Claude desktop sessions.
2. **Statusline snapshots** from terminal sessions.
3. **The last known limits**, saved in the config so the panel is not blank after a restart.

When nothing else reports limits, `LimitsProbe` runs a one-word `claude -p` with haiku and no tools. `ProbePolicy` allows it at these points:

| Trigger | Condition |
|---|---|
| Launch, or opening the panel | Only if the known limits are older than 10 minutes |
| Agents are active | Only if both the known limits and the last probe are older than 30 minutes |
| Manual refresh | Any time the gates below allow |

Gates that apply to every trigger, manual refresh included:

- only one probe runs at a time;
- a 60 s cooldown follows every successful probe;
- after a failure, a backoff of 5, 15, then 30 minutes.

### Running the CLI (`ClaudeProcess`)

`ClaudeLocator` looks for the `claude` binary in this order:

1. an explicit path;
2. `PATH`;
3. the newest copy bundled with Claude desktop, under `~/Library/Application Support/Claude/claude-code/<version>/<hash>/claude.app/Contents/MacOS/claude`.

Every run of the binary:

- uses `--setting-sources project` (no user hooks or settings), `--tools ""` and stream-json output;
- runs in `$TMPDIR/pixelpet-claude`;
- strips `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL` and the Bedrock, Vertex and Foundry switches from the environment, so the run bills the subscription;
- sets `PIXELPET_INTERNAL=1`;
- passes text over stdin (the probe passes its fixed prompt as an argument instead);
- on cancel or timeout, gets SIGTERM and then SIGKILL.

The three callers:

| Caller | Model | Notes |
|---|---|---|
| `LimitsProbe` | haiku | One-word prompt, `--no-session-persistence` |
| `ClaudeAsk` (quick question) | `askModel` | Appended system prompt; follow-ups use `--resume <session>` |
| `ClaudeTranslator` | sonnet | `--no-session-persistence`, streamed |

`ClaudeStream` parses the stream. An answer counts as done at `message_stop`; the `result` line arrives about 1.5 s later and is not waited for.

`AskConversation` binds every run's events to an epoch (bumped by "New") and a turn index. Late events from an old conversation or a finished turn are dropped. The next question waits until the previous CLI process has exited. Quick-question sessions live in `~/.claude/projects/*-pixelpet-claude` and are deleted on "New", on quit and on launch.

## Codex integration

Codex has hooks too, but they must be trusted one by one in its CLI, they replace nothing that Codex shows elsewhere, and it isn't documented whether the desktop app runs them. Its session files, on the other hand, are written by every Codex surface (CLI, IDE extension, desktop app) and need no setup, so the pet reads those.

- **Following.** `CodexWatcher` listens to FSEvents under `~/.codex/sessions` on its own serial queue to find new and newly touched files. FSEvents goes quiet about a file that stays open for writing, and Codex keeps its session file open for the whole session, so each followed file also gets a kqueue source (`extend` / `write`) that fires on every append; at most 32 files are followed, and one left alone for a day is let go. A big file is never read whole: at start, and for files that show up later, it reads the first line (the session's metadata, up to 1 MB) and the last 512 KB, dropping the cut-off line the tail starts in. After that only appended bytes are read, again capped to the last 512 KB after a long gap; an unfinished last line waits for the rest. At start only files modified in the last 30 minutes are opened. Subagent files are remembered and skipped. Lines over 4 MB are dropped. A file that got shorter is read again from the start. `~/.codex` is never created: without it the watcher checks once a minute until it appears. `stop()` cancels a catch-up between files, and the FSEvents stream retains the watcher, so no callback outlives it.
- **Only Codex agents.** Ordinary ChatGPT conversations, including those in the desktop app, run in the cloud and write nothing here; only Codex threads do (CLI, IDE extension, the Codex side of the app).
- **Parsing.** `CodexRollout` maps lines to the same `AgentEvent`s the Claude Code hooks produce, each with the line's own timestamp:

  | Codex line | Event |
  |---|---|
  | `session_meta` | session start (id, folder); subagent threads (`thread_source` other than `user`) are skipped |
  | `turn_context` | session start with the model and folder |
  | `event_msg` `task_started` | prompt submitted (working) |
  | `event_msg` `task_complete` | stopped (celebration rules apply) |
  | `event_msg` `turn_aborted` | interrupted: idle, no celebration |
  | `event_msg` `error` | failed |
  | any line inside an open turn | still working; read from the middle of a file, a `turn_id` opens the turn. Lines of a turn that already ended are ignored |
  | `event_msg` `token_count` | Codex limits (`rate_limits.primary` / `secondary`, told apart by window length) |

  Approval prompts aren't written to the files, so Codex sessions never show as waiting.
- **State.** `AgentMonitor` keeps Codex sessions in a second `SessionRegistry` without the silent-work timeout: Codex writes `turn_aborted` when a turn is stopped, so a quiet turn (a long build) stays working. The pet's mood takes both registries into account (a failing or working Codex agent shows like a Claude one); the drained body and the low-limit look stay tied to Claude's limits. Only events at most 10 s old trigger reactions, and catch-up batches never do, so turns found in a file read late are not celebrated. Batches from a watcher that was switched off are dropped.
- **Limits.** Besides the `token_count` lines, `CodexLimitsProbe` asks a short-lived `codex app-server` over JSON-RPC (`initialize`, `initialized`, `account/rateLimits/read`) at launch and when the panel opens, under the same `ProbePolicy` rules as Claude's probe. No model request is made. The server quits when its input closes, so `ClaudeProcess` keeps the input open (`until`) and stops the process once the answer arrives.
- **Finding Codex.** `CodexLocator` accepts only native Mach-O binaries: `PATH`, then the copy inside ChatGPT.app or Codex.app, then the newest standalone release under `~/.codex/packages/standalone/releases`. The npm `codex` is a Node script, and apps launched from Finder have no Node on their PATH.

## Rendering

- **Window.** `PetPanel` is a borderless, non-activating `NSPanel` that joins all Spaces and works over fullscreen apps. It never takes focus. Fully transparent pixels are click-through via an alpha hit-test. `constrainFrameRect` is overridden so that at home the window can hang over the menu bar.
- **Layers, not SpriteKit.** The spike measured SpriteKit at 2–8% CPU and about 125 MB. Swapping `CGImage`s in a `CALayer` costs 0.1–0.2% and about 12 MB. Window movement (throws, easing home) is done by Core Animation in the render server.
- **Frames.** `SpriteFactory` draws every state procedurally on a 32×32 `PixelCanvas`. It started as a port of [`prototype/sprites.html`](prototype/sprites.html). `SpriteLibrary` renders all base frames for the current `Look` once (a few hundred KB) and caches variants made on demand in a bounded cache: limit drain rows, gaze direction. The window scale is a whole number (×2 to ×6) with nearest-neighbor filtering.
- **Style.** Shading is hue-shifted: two shade steps, a rim light, a colored outline, blush, and breathing through the highlight.
  - **Skins:** lavender, mint, peach and graphite (`mono`), plus the red `error` skin.
  - **Accessories:** glasses, headphones, cap.
  - **Rotation** (flip, tumble) uses 3×3 supersampling with a deterministic majority vote. Accessories turn with the body, while the face is redrawn upright.
- **Timing.** Each `PetState` has a duration per frame, so key poses are held and in-betweens are quick. `PetPlayer` plays a looping base state with an optional one-shot on top. `PetController` schedules exactly one timer per frame, timed to the end of the current frame, with a tolerance of 25% capped at 50 ms. While agent blocks are visible, the clock also keeps their shared 10 Hz beat. The timer stops entirely while the pet is hidden or occluded, or frozen under Reduce Motion.
- **Agent stack.** `AgentStack` draws the 3×3 blocks on a separate 32×32 overlay: Claude Code at x 27–29 to the right of the body, Codex mirrored at x 2–4 on the left, each with its subagent dot on the outer side. Poses the pet holds while agents run keep clear of both columns (a test checks the left one). At home the stack is hidden, and the menu-bar counter stands in for it.
- **Reduce Motion.** `MotionPolicy` lists the states that hold one frame (alert, error, dragged, low limit) and the one-shots that are skipped (hop, celebrate, drop, dive, peek, flip, tumble, yawn, shy, angry). Some skipped events get a held "cue" frame for 1.5 s instead, so they still register.

### States

`PetState` has 20 cases.

| Kind | States |
|---|---|
| Looping (moods) | `idle`, `working`, `alert`, `lowLimit`, `error`, `sleep` |
| Looping (home and helpers) | `burrowed`, `peekHold`, `dragged`, `talk` |
| One-shots | `hop`, `celebrate`, `drop`, `peek`, `dive`, `yawn`, `shy`, `angry`, `flip`, `tumble` |

## Home: notch and burrow

`HomeSpot` and `HomeGeometry` compute a home spot at the top center of each screen. On a notched screen, the notch's center is the gap between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`; the window then hangs so the eyes sit just under the cut-out. Other screens get a drawn black "burrow".

How the pet moves between the desk and home:

- **Drop.** Letting go with the pet's top at or above a screen's top edge, or within 60 pt below it, anywhere along it, sends it to that screen's home; so does ending within 90 pt of the home itself. Both the release point and the landing point of a throw are checked.
- **Pull out.** A drag that starts at home takes the pet back only if it is let go within 24 pt of its seat, so a short tug is enough to get it out. Other homes keep the normal rules during that drag.
- **Hover.** Hovering over the home makes the pet peek out after a short delay, so the cursor passing over the menu bar does not trigger it.
- **Do not disturb.** This sends the pet home. Leaving clears it only if the pet really ends up on the desk.
- **Screen changes.** The home display is remembered. After display sleep or unlock the window is re-seated, because macOS reports different geometry while the screen is locked.

## Desktop reactions

`DesktopSensor` needs no extra permissions. It uses mouse monitors, the system idle counter and window bounds, and never reads window titles.

- **Gaze.** The eyes follow the cursor within 300 pt, by ±1 px. The mouse monitor runs only while reactions are on and the pet is visible and on the desk, throttled to 10 Hz.
- **Glance.** The pet glances toward the frontmost window of an app the user switches to: normal apps only, at most once every 10 s.
- **Fullscreen.** The pet dims over a fullscreen window instead of hiding.
- **Away and back.** Sleep uses the live idle time, the pet hops when the user returns, and it greets after the Mac wakes.

`PetController` adds the personality layer:

- **Fidgets** (yawn, tumble) play every 90–240 s, only while idle on the desk with reactions on, no card open and Reduce Motion off.
- **Shy** after the cursor rests on the pet for 2 s, at most once a minute.
- **Angry** after 5 clicks within 3 s. The status card still opens, and clicks at home do not count.

## Translation and selection

- **Reading the selection.** `SelectionReader` asks the focused element for `AXSelectedText`. If the app does not expose it, the reader sends ⌘C and restores the clipboard exactly. Restored items carry the nspasteboard.org marker types, so clipboard managers skip them.
- **Privacy rules.** These are pure and tested in `SelectionDecision`: password fields are never read; an empty selection never falls back to ⌘C, because IDEs copy the whole line then; ⌘C is never sent to the pet itself; and it is never used when the clipboard holds something that cannot be restored exactly, such as promised files.
- **Direction.** `TranslationPlan` translates your language to the foreign one and everything else into yours. Only the language part of BCP-47 codes is compared.
- **Engines.** Apple Translation runs offline through SwiftUI's `translationTask` (en↔ru in about 120–200 ms). Missing language packs are downloaded through the system sheet from the card. "Via Claude" streams a sonnet translation instead.

## Cards, menus and settings

- **Cards.** The status, translation and quick-question cards are borderless panels rather than `NSPopover`: glass popovers tint with the wallpaper and lose contrast.
  - Placement: above the pet when there is room, otherwise below.
  - Only one card is open at a time.
  - A click in another app closes the card.
  - Cards opened from a hotkey appear without animation.
  - The quick-question card accepts typing without activating the app.
- **Edit menu.** A minimal one is installed so that ⌘C/⌘V/⌘A/⌘Z and ⌘W work in text fields of an accessory app.
- **Hotkeys.** These are global, registered with Carbon `RegisterEventHotKey`, which needs no permissions.
- **Settings and onboarding.** Both are SwiftUI views over an `@Observable` `SettingsModel`. Launch at login uses `SMAppService.mainApp`, including the "requires approval" case.
- **Single instance.** A second copy of the app quits at launch, so two pets never fight over the socket.

## Configuration

`ConfigStore` reads and writes `~/.pixelpet/config.json` as pretty-printed JSON with sorted keys. Every field has a default and is clamped on decode. An unreadable file is moved to `config.json.bak` and defaults are used.

| Key | Default | Meaning |
|---|---|---|
| `scale` | 4 | Pixel scale, 2–6 |
| `origin` | — | Desk position, global coordinates |
| `isHidden` | false | Pet hidden from the screen |
| `isHome` | false | Lives in the notch or burrow |
| `homeDisplay` | — | Display id of the home; empty means the menu-bar screen |
| `doNotDisturb` | false | Stay home; come out only for errors |
| `desktopReactions` | true | Gaze, glances, dimming, fidgets |
| `sleepAfterMinutes` | 10 | 0 means never; clamped to 0–1440 |
| `nativeLanguage` / `foreignLanguage` | `ru` / `en` | Translation direction |
| `askModel` | `haiku` | Model for quick questions |
| `skin` / `accessory` | `lavender` / `none` | Look |
| `watchCodex` | true | Follow Codex sessions and limits |
| `lastCodexLimits` | — | Last known Codex limits |
| `logEvents` | false | Write `~/.pixelpet/events.log` (ids, project and event names only; rotates at 1 MB) |
| `lastLimits` | — | Last known limits |
| `onboarded` | false | Welcome window was seen |
