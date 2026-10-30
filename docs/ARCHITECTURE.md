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
| `PetCore` | — | `AgentEvent`, `SessionRegistry`, `PetBrain`, `PetState`, `PetPlayer`, `MotionPolicy`, `UsageLimits` and `Inbound`, `ProbePolicy`, `PetConfig` and `ConfigStore`, `HookSettings` and `HookInstaller`, `HomeSpot` and `HomeGeometry`, `Placement`, `DragTracker`, `Gaze`, `ReactionThrottle` and `Fullscreen`, `TranslationPlan` and `SelectionDecision`, `AskConversation` and `Attachment`, `ClaudeStream` and `ClaudeTranslation`, `CodexRollout`, `AnswerText` |
| `PetSprites` | `PetCore` | `PixelCanvas`, `Palette` (`Skin`, `Accessory`, `Figure`, `Look`), `CubeDrawing` (`BodyStyle`), `SpriteFactory`, `AgentStack` |
| `PetIntegrations` | `PetCore` | `EventServer`, `ClaudeLocator`, `ClaudeProcess`, `LimitsProbe`, `ClaudeChat` and `ClaudeAsk`, `AttachmentLoader`, the `ClaudeTranslation` runner (an extension), `CodexWatcher`, `CodexLocator`, `CodexLimitsProbe` |
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

- **Hook command.** The single-quoted script path is registered for 13 events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`, `SessionEnd` and `PreCompact`. A connection made by an older build, with fewer events, gets the missing ones added at launch (`upgradeIfPartlyInstalled`, with the usual backup). Each entry has a 5 s timeout, except `PermissionRequest` with 75 s (`PermissionWait.hookTimeout`), since that hook waits for the pet's answer; an older install's timeouts are updated at launch (`hasStaleTimeouts` / `updateTimeouts`). The entries are recognized by their exact command string, which is how install, uninstall and the installed check stay idempotent.
- **Statusline.** It is added only when the user has no `statusLine` of their own. A foreign statusline is reported as such and left alone.

How the settings file is written:

- A missing or blank file counts as empty. Unparseable JSON or an unexpected `hooks` shape is an error; the installer never overwrites data it does not understand.
- Writes go through symlinks and keep the file's permissions. A timestamped backup is made first, and nothing is written if nothing changed.
- `JSONSerialization` re-sorts the keys of the rewritten file. This is a known cosmetic side effect.

`refreshScriptIfInstalled()` runs at launch, so the scripts always match the running build.

The hook script itself is `sh`, `sed` and `nc -U`. It streams the payload to the socket (adding `pixelpet_app` / `pixelpet_term`), prints whatever comes back and always exits 0 and drains stdin. The pet closes every connection right after reading it (about 10 ms per call, as measured in the spike), except a permission request it answers; that one waits, at most 70 s. When `PIXELPET_INTERNAL` is set it does nothing; this is how the pet's own `claude -p` runs stay out of the agent list.

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
- **Answering permission requests.** The hook script tags every payload with where the session runs (`__CFBundleIdentifier`, `TERM_PROGRAM`, only `[A-Za-z0-9._-]` kept) and keeps its `nc` open until the pet closes the connection (at most 70 s). It prints what came back only when the payload is a `PermissionRequest`, so nothing else listening on the socket can feed other hooks a decision. Whether to wait is the server's call, from the parsed JSON: `EventServer` keeps a `PermissionRequest` connection instead of closing it and hands the app a `HookReply`; the first `send` writes the hook's output (or nothing) and closes, and it closes empty by itself after 66 s. `PermissionDesk` waits only while the setting is on and the pet is on screen (not hidden, covered or in do-not-disturb), at most 16 at a time, and lets go at once if the card can't be shown. Answers carry the request's id and the buttons go live 0.5 s after a request appears, so a click meant for the previous card can't answer the next. `HookReply.onGone` checks twice a second whether the hook is still there (kqueue write EOF) and drops the card if not. `PermissionPrompt` parses what to show (the main parameter and the rest of the input; the model's description; Claude Code's `permission_suggestions` and what they cover), `PermissionAnswer.hookOutput` writes `decision.behavior` allow/deny (with `updatedPermissions` for "don't ask again", a `message` for deny); the checkbox names the rule only when it's a single plain rule. The main parameter is the built-in tool's own (command, file, URL, query) or, for other tools, the first of `command`, `file_path`, `path`, `url`, `query`, `pattern`, shown plain; the rest of the input follows as `key: value` lines (JSON only for nested values), except for shell and edit tools, whose other parameters Claude Code's prompt doesn't show either. A `command` parameter makes the title say "run a command", and a session in the Claude app is called "Claude" rather than "Claude Code". Everything is shown with bidi, zero-width and control characters spelled out as `<U+…>`, and `PermissionQueue` shows them oldest first. The Claude app shows its own dialog at the same time and keeps the hook running for up to a minute after it's answered there, and no hook reports that answer or the stopped turn a denial causes. So while a session waits for a permission, `AgentMonitor` reads the lines appended to its transcript (`transcript_path`, twice a second, `TranscriptTail`): the call's `tool_result` (matched by the hook's `tool_use_id`, or the session's last `PreToolUse` of that tool) closes the card and puts the session back to working (`permissionSettled`), and a `[Request interrupted by user…]` entry makes it idle. Only `type: user` entries count, since request copies (`api-request-blob`) repeat old history; the watch ends with the session's next hook event. A held hook that goes away (`HookReply.onGone`) settles the request the same way. After `PermissionWait.window` (60 s), on ✕ or "Answer in …", or when the session ends, nothing is printed and Claude Code asks the usual way; "Answer in …" also activates that app (`AgentHost`, no Automation permission). `AskUserQuestion` and `ExitPlanMode` keep their own flow.
- **Breaks.** `BreakClock` (PetCore) gets the system idle time (`PetController.userIdleProvider`, the same one sleep uses) every 30 s: input within 5 minutes continues the stretch of work, 5 minutes idle ends it, and so does a longer gap between looks (the Mac asleep), whatever the idle time reads after waking. Past `breakMinutes` it shows the mug for 3 minutes, then hides it for 20 (`repeatAfter`); `snooze` (a click) hides it for 15. A stretch that reached the reminder earns `welcomeBack` (a hop) when work resumes after the break. `PetController.resolvedRest` returns `breakHint` (after a `yawn` one-shot) over work and rest but not over an error, an agent that waits, a call, do-not-disturb, a dimmed pet (fullscreen) or home. `workedNearReminder` feeds the status panel's "No break for" line in the last 15 minutes before the reminder and while it's due.
- **Weekly recap.** `AgentStats` (PetCore) keeps sums per local day ("yyyy-MM-dd"): per project folder Claude and Codex active seconds, turns and steps; waits for the user (count and seconds), answers from the permission card, the 5-hour limit's peak and hits (a window counts once, by its reset time); and the day's longest turn. `AgentMonitor.count` records a turn when a session's `finishedAt` changes (`lastWork` is the turn's active work, waits left out, from `SessionRegistry.finish`) and a wait when a session leaves `waiting`; Codex lines read late don't count. `StatsKeeper` holds the stats, writes `~/.pixelpet/stats.json` (`StatsStore`) at most once a minute and on quit, prunes to 8 weeks, and records nothing while the setting is off. `AgentStats.summary(of:)` builds a `WeekSummary` for an ISO week (Monday first, local time zone). `RecapPlan.due` is true once per week (`recapShownFor`) from Monday 6:00 when last week had agent time on at least two days; `AppDelegate.checkRecap` looks at launch and every 5 minutes, only while the pet is on screen, and calls `PetController.setNews`: the pet plays `newspaperOpen` and rests in `newspaper` while its mood is idle and not in do-not-disturb; a click on it (or the menu item) opens `RecapPanel` and clears the news.
- **Notifications.** `NoticePlan.action` (PetCore) compares a session before and after each event, with the registry's reaction: a reaction `finished`/`finishedBig` or `failed` posts that, a new wait (or a change of what it waits for) posts `permission` or `question`, and starting to work or leaving a wait clears it; a session that ends, or that `prune` drops, clears too. `NoticePlan.posts` lets a post through for `NotificationMode.always`, or `whenHidden` while the pet isn't on screen, never in do-not-disturb; a permission the card by the pet is showing isn't posted. `Notifier` (UserNotifications) posts banners with no sound under one identifier per session (`claude-…`, `codex-…`, `key-touch`), so a post replaces the last one; a generation counter keeps a post that's still waiting for authorization from landing after a clear. It asks for `.alert` only, the first time it posts, and hands the session's host bundle (`AgentEvent.host`, from the hook's tags) to the click handler, which activates that app. `NoticeText` writes the project and what happened, never the step's object. The key's notification follows `PetController.onTouching`. Codex lines read late (catch-up) clear but don't post.
- **Stopped turns.** Esc fires no hook. Every hook payload carries `transcript_path`, kept on the session; `AgentMonitor.checkInterrupts` runs every 3 s and, for a working or waiting session quiet for 4 s whose transcript has grown since the last look, reads the file's last 64 KB: when the newest user or assistant entry is "[Request interrupted by user…]" (`PermissionPrompt.endsInterrupted`), it applies `.interrupted` and the session goes idle at once instead of after the 5-minute quiet timeout (or never, when a tool was running).
- **Steps and the turn.** `AgentEvent.parse` turns a `PreToolUse` input into an `AgentStep`: an action (runs, reads, edits, writes, searches, finds files, opens, searches the web, subagent, or the tool's name) and a short object (the command's first line, a file name without its path, a pattern, a URL's host, a query, a subagent's description), cut to 60 characters with hidden characters spelled out; the rest of the input is dropped, and steps are never logged or written. The session keeps the current `step` and `stepSince` (cleared to "thinking" by the call's `PostToolUse`), `turnStartedAt` and the turn's `steps` count (questions don't count), and `lastTurn` when the turn ends. The status card shows the step with an m:ss clock, the turn's length and steps, and "Done N ago, took M" afterwards; it ticks every second while open (`CardPanel.tickInterval`). Codex reports no tools, so its rows show only the turn clock.
- **Working and waiting.** A prompt or a tool start means working. A permission request means waiting. So do the `permission_prompt` and `elicitation_dialog` notifications, and an open `AskUserQuestion` or `ExitPlanMode` call until its matching `PostToolUse`. A Claude desktop turn that ends with a `wrap_up` call carrying a non-empty `ask` also waits after `Stop`. Each wait records what it waits for (`waitingFor`): a permission (permission requests and prompts) or a question (the question tools, elicitations, turn-end questions).
- **Turn ends.** `Stop` ends the turn, and so does an `idle_prompt` notification. `StopFailure` marks the session as failed.
- **Subagents.** These are tracked between `SubagentStart` and `SubagentStop`, so the post-turn summary agent that stops without having started is ignored. Tool calls carrying an `agent_id` (they ran inside a subagent) while the session is between turns (`betweenTurns`: after a finished, failed or interrupted turn, or a start with no prompt yet) don't make it work again: the Claude app's post-turn helper runs a tool now and then with no `PostToolUse` to follow. The session's own agent (no `agent_id`) picking up again after `Stop` still counts.
- **Reactions.** A finished turn earns a celebration only after at least 20 s of active work; time spent waiting for the user does not count. A turn of 10 minutes or more earns the somersault (`finishedBig` → `flip`).
- **Interrupts.** A working session with no tool running and no events for 5 minutes is treated as interrupted, because Esc sends no `Stop`.
- **Background subagents.** A `Stop` while subagents are still running (background agents) keeps the session working (`turnEnded`); it finishes, celebrating by the work done, when the last `SubagentStop` arrives. Subagents carry over a new prompt; the silent-work timeout clears ones whose stop never came.
- **Expiry.** Sessions with no events for 30 minutes are dropped. Sessions waiting on a permission prompt or an open question tool never go stale; a turn-end question from Claude desktop fades to idle after 30 minutes. Ended session ids are remembered (up to 500), so late events cannot bring them back; a `SessionStart` or prompt with that id does, since the Claude app ends a session it unloads and later resumes it under the same id.

### Turning sessions into a picture (`PetBrain`)

`PetBrain.baseState` picks the state in priority order:

1. error, if a session failed within the last 3 s;
2. alert if any waiting session needs a permission, otherwise question;
3. exhausted, when a limit is used up (≥ 100%);
4. low limit (5-hour usage ≥ 85% or weekly ≥ 90%);
5. working;
6. idle.

On top of that base state:

- `restState` turns idle into sleep after `sleepAfterMinutes` without user input. The idle time is read live each time the decision is made. Idle on a low battery (`PowerReading.isLow`, from `PowerMonitor`'s IOKit notifications) becomes `tired`.
- At home, `homeState` maps error, alert and question to `peekHold` and everything else to `burrowed`. Under do not disturb, alerts stay `burrowed` too.
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
- is tracked while it runs, and `ClaudeProcesses.terminateAll` stops what's left when the app quits (SIGTERM to the app quits it the normal way, through a dispatch signal source);
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

**Files.** `PetView` takes file URLs dragged onto it: while they're over the pet it rests in `catchOpen`; a drop goes to `Asker.attach`, which reads up to `Attachment.maxFiles` with `AttachmentLoader` (PetIntegrations) off the main thread: text and code when the bytes are UTF-8 with no NUL early on, cut to `Attachment.maxText`; a PDF's text through PDFKit, or its first page rendered when it has none; images through ImageIO's thumbnail at `Attachment.imageSide`, JPEG for photos and PNG otherwise. Folders, unknown types, files over 30 MB and empty ones are refused with a reason. Taken files play `swallow` and open the card; none taken plays `shakeHead`. The next question carries them: `Attachment.prompt` puts each text in a `<file name="…">` block before the question; with any image the message goes as one `--input-format stream-json` line with image blocks (`Attachment.streamMessage`). `AskConversation.Turn.files` keeps the names for the history.

`AskConversation` binds every run's events to an epoch (bumped by "New") and a turn index. Late events from an old conversation or a finished turn are dropped. The next question waits until the previous CLI process has exited. Quick-question sessions live in the `~/.claude/projects` folder Claude Code names after the pet's workdir (`ClaudeWorkdir.projectFolderName`: every character but ASCII letters and digits becomes "-", for the path as given and resolved) and are deleted on "New", on quit and on launch; only those exact names (and the old probe workdir's) are removed, never a project that merely ends the same way.

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
  - **Skins:** lavender, mint, peach, graphite (`mono`), sky, sakura, vanilla and night (dark body, light outline and face), plus the red `error` skin. New skins stay clear of the agent colors (teal, amber, red) so the pet is never mistaken for a block's state.
  - **Accessories:** glasses, sunglasses, headphones, cap, beanie, crown, bow, flower, propeller hat, scarf, mustache. Head accessories (`isOnHead`) keep the work headband off.
  - **Figures:** the cube, or LM (`Figure.lidman`): a round drop with a V cut into its top and a two-tone diamond above it, big white eyes. `drawLidMan` replaces only the body and `lidManFace` the face, so states and props are shared. The diamond gets the rows above the body (at least 4: the top of a big jump comes a little lower for LM), so it squashes rather than leaving the canvas; turning frames can still graze an edge. That rule is off in the home hole (`BodyStyle.inHole`), where LM peeks out 2 rows less than the cube (`SpriteFactory.lidManPeekRaise`): his eyes and the round bottom of the drop. His big pupils follow the gaze (cursor, glances) like the cube's eyes. LM always uses the `lidman` skin and no accessory, and marks drawn over the middle of the head ("!", the spent clock) step aside for the diamond (`Look.headMarkShift`); smaller marks (sparkles, spawn copies) may overlap it.
  - **Every day new** (`Look.resolve` with `daily`): the skin and the accessory are picked from the date alone, so a day keeps its look across restarts and two days in a row never match; the pet redraws at midnight and after waking.
  - **Rotation** (flip, tumble) uses 3×3 supersampling with a deterministic majority vote. Accessories turn with the body, while the face is redrawn upright.
- **Timing.** Each `PetState` has a duration per frame, so key poses are held and in-betweens are quick. `PetPlayer` plays a looping base state with an optional one-shot on top. `PetController` schedules exactly one timer per frame, timed to the end of the current frame, with a tolerance of 25% capped at 50 ms. While agent blocks are visible, the clock also keeps their shared 10 Hz beat. The timer stops entirely while the pet is hidden or occluded, or frozen under Reduce Motion.
- **Agent stack.** `AgentStack` draws the 3×3 blocks on a separate 32×32 overlay: Claude Code at x 27–29 to the right of the body, Codex mirrored at x 2–4 on the left, each with its subagent dot on the outer side. Poses the pet holds while agents run keep clear of both columns (a test checks the left one). At home the stack is hidden, and the menu-bar counter stands in for it.
- **Reduce Motion.** `MotionPolicy` lists the states that hold one frame (alert, error, dragged, low limit) and the one-shots that are skipped (hop, celebrate, drop, dive, peek, flip, tumble, drip, melt, wave, launch, purr, sneeze, the Mac's one-shots, yawn, shy, angry); the Mac's ongoing states hold one frame. Some skipped events get a held "cue" frame for 1.5 s instead, so they still register.

### States

`PetState` has 20 cases.

| Kind | States |
|---|---|
| Looping (moods) | `idle`, `working`, `alert`, `lowLimit`, `error`, `sleep` |
| Looping (home and helpers) | `burrowed`, `peekHold`, `dragged`, `talk` |
| One-shots | `hop`, `celebrate`, `drop`, `peek`, `dive`, `yawn`, `shy`, `angry`, `flip`, `tumble`, `drip`, `melt`, `wave`, `launch`, `purr`, `sneeze` |

## Home: notch and burrow

`HomeSpot` and `HomeGeometry` compute a home spot at the top center of each screen. On a notched screen, the notch's center is the gap between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`; the window then hangs so the eyes sit just under the cut-out. Other screens get a drawn black "burrow".

How the pet moves between the desk and home:

- **Drop.** Letting go with the pet's top at or above a screen's top edge, or within 60 pt below it, anywhere along it, sends it to that screen's home; so does ending within 90 pt of the home itself. Both the release point and the landing point of a throw are checked.
- **Pull out.** A drag that starts at home takes the pet back only if it is let go within 24 pt of its seat, so a short tug is enough to get it out. Other homes keep the normal rules during that drag.
- **Hover.** Hovering over the home makes the pet peek out after a short delay, so the cursor passing over the menu bar does not trigger it.
- **Do not disturb.** This sends the pet home. Leaving clears it only if the pet really ends up on the desk.
- **Screen changes.** The home display is remembered. After display sleep or unlock the window is re-seated, because macOS reports different geometry while the screen is locked.

### Moments from events

`AgentMonitor` compares each refresh with the last one: more subagents than before plays `spawn`, all of them gone plays `recall` (over a typing pet, `PetState.atDesk` swaps in `spawnDesk` / `recallDesk`, which keep it at the keyboard), and the 5-hour window resetting after at least 10% use plays `refill` (`UsageLimits.refilled`). `PreCompact` (and Codex's `compacted` lines) play `compact`. Plugging in plays `plugIn`. `PetController.moment` lets these through only on the desk, over a calm or working pet with nothing else playing; catch-up batches never trigger them.

## Desktop reactions

`DesktopSensor` needs no extra permissions. It uses mouse monitors, the system idle counter and window bounds, and never reads window titles.

- **Gaze.** The eyes follow the cursor within 300 pt, by ±1 px. The mouse monitor runs only while reactions are on and the pet is visible and on the desk, throttled to 10 Hz.
- **Glance.** The pet glances toward the frontmost window of an app the user switches to: normal apps only, at most once every 10 s.
- **Fullscreen.** The pet dims over a fullscreen window instead of hiding.
- **Throws.** A release faster than 1,200 pt/s plays `thrown` (quarter turns, lossless) while the window flies, then the landing once it arrives: `splatLeft`/`splatRight` when the aim was clamped at that side of the screen (`Placement.throwOutcome`), `dizzy` if the drag was shaken (`DragTracker.isShaken`: four quick horizontal reversals of at least 20 pt within 1.2 s), otherwise `drop`.
- **Late night.** From 22:00 to 05:00 by the Mac's local time, desk poses get a lamp and tea instead of coffee (`NightDesk`); the desk is redrawn at the next boundary.
- **Away and back.** Sleep uses the live idle time, the pet hops when the user returns, and it greets after the Mac wakes.

`PetController` adds the personality layer:

- **Fidgets** (yawn, tumble, sneeze; for LM `drip` or `melt` about half and half in place of tumble, `Breaks.fidget(lidMan:)`; about a sixth are sneezes) play every 90–240 s, only while idle on the desk with reactions on, no card open and Reduce Motion off.
- **Tool bubble.** `ToolKind.current` takes the `currentTool` of the working Claude session heard from last and maps built-in tools to an icon (run, search, read, edit); `PetController.workProps` adds it at the desk (`WorkProps.toolRun` and friends), and it lingers 2.5 s after a tool ends so it doesn't blink between calls. Other tools, Codex and MCP show none.
- **Waving.** `SessionRegistry` keeps `waitingSince` per session; `AgentMonitor` passes the oldest wait to `PetController.setWaitingSince`, which schedules `wave` with `WaitNudge.next` (a minute in, then every 45 s) over a resting `alert` or `question`, not at home, over a card or under Reduce Motion; a wave the pet was too busy for is retried a few seconds later.
- **Rocket.** `AgentEvent.parse` marks a successful `PostToolUse` of Bash whose command runs `git push` (`isGitPush`: quoted text blanked first, so a commit message mentioning it doesn't count; not `-n`/`--dry-run`) as `pushed`; the command itself is not kept. `AgentMonitor` plays `launch` through `moment`, at most once a minute (a launch that couldn't play doesn't use up the minute).
- **Petting.** `PetView` reports mouse moves; `PettingDetector` counts direction changes of 4 pt+ strokes, three within 1.2 s pet the pet (`purr`), at most every 10 s, on the desk over an idle, working or tired pet; strokes only count while the pet is free to answer.
- **Holidays.** `Holiday.on` by the Mac's date adds `WorkProps.pumpkin` (October 25–31) or `.fir` (December 20 – January 7), drawn wherever the pet stands on the floor (`SpriteFactory.showsFloorProps`: not at home, in the air or against a wall); the midnight redraw changes them. New art keeps out of the agent columns (0-4 and 27-31) below row 8; a test checks it.
- **The Mac.** `MacMonitor` (app target) listens without polling and asks for no permission, reading flags only: CoreAudio (the default output's transport, Bluetooth or the built-in headphone jack, and whether it runs; whether the default input runs), CoreMediaIO (any camera running), `ProcessInfo` thermal and low-power notifications, `NWPathMonitor`, a live Spotlight query for new screenshots (`kMDItemIsScreenCapture`), and the distributed theme notification. `SoundDebounce` makes 10 s of sound music and keeps it through 5 s gaps; when the default output changes, a stream already open on the new device (a paused player's, moved over from unplugged headphones) doesn't count until it stops once (`outputChanged`); `OfflineDebounce` waits 5 s. The resulting `MacState` reaches `PetController.setMac`: `MacState.rest(insteadOf:)` replaces only an idle rest (mic/camera, then heat, network, low power, music), headphones go into the look (`LookExtras.headphones`, drawn by the body in every upright pose) with a put-on or take-off one-shot. Screenshots, the theme and `PowerReading.becameFull` play one-shots through `moment`. `PartyTime` adds `LookExtras.partyHat` on Friday from 17:00; the day-change timer also wakes then. Virtual and aggregate audio devices never count as running. The first reading and the reset when stopping are applied without animation; headphones settle 1.5 s before the look (and every sprite) is rebuilt; a full battery is celebrated once per plug-in; one-offs wait while on air. A click over one of these resting states adds it to `MacDismissals`, which `rest(insteadOf:skipping:)` passes over until `MacState.isActive` says its condition ended. Worn headphones take the place of a head accessory, like the call headset. The "React to the Mac" setting (`macReactions`) stops the monitor and drops the hat.
- **Shy** after the cursor rests on the pet for 2 s, at most once a minute.
- **Hookah breaks** (`Breaks`): about one idle fidget in four is a hookah when the setting allows it, and a big finished task (the somersault) is followed by one about a third of the time, if the pet is idling on the desk by then. About one in four ends in a big cloud (`hookahCloud`) instead of rings. The hookah stands in columns 20–26, clear of the Claude blocks.
- **Angry** after 5 clicks within 3 s. The status card still opens, and clicks at home do not count.
- **Typing loop.** `working` plays `TypingScript`: about 12 s of bursts (4–13 keys) with a jittered pace, a key now and then held longer, and varied pauses (a look up at the screen, a blink, a short stop), generated from a fixed seed so it doesn't read as a loop yet stays deterministic. It has no smile; smiles come with moments and finishes.
- **Work moments** (sip, stretch, think, rush) play every 45–120 s while the pet types at the desk, never twice in a row (`WorkMoments`). The same gates as fidgets apply, plus: only over the plain typing loop.
- **Glances** at the agent blocks: when an agent on one side finishes, fails, starts waiting or working, or joins others (`WorkMoments.noticeable`), the pet looks left (Codex) or right (Claude), at most once every 8 s. The first blocks at launch, catch-up batches, the green flash fading and sessions dropping off don't count. A moment playing at the keyboard stops when the typing does (talking, an alert, Reduce Motion).
- **Desk props** grow with the work session (`WorkSession`, `WorkStage`): the time the pet spends typing, across turns and agents. Pauses of up to 10 minutes between turns are neither counted nor ending it; a longer break clears the desk. A mug after 10 minutes, a headband after 30. `AgentMonitor` wakes up at the next threshold. They are drawn into every desk pose (`PetState.isAtDesk`) and cached as variants by `SpriteLibrary`; Reduce Motion keeps them.

## YubiKey touch

- **Signal.** While a YubiKey waits for its button during a GPG operation, macOS's smart-card reader service (`usbsmartcardreaderd`, subsystem CryptoTokenKit) logs "Time extension received" about three times a second; the messages stop once it is touched or gpg gives up (about 14 s). This holds when GnuPG reaches the key through the system's PC/SC; its own CCID driver would bypass the service.
- **Watching.** `TouchWatcher` keeps one `log stream --level debug --style ndjson` running, filtered by predicate to exactly that message (no measurable CPU, about 4 MB). It runs under a small `sh` watchdog that kills the stream when the app's pid is gone, so a crash leaves nothing behind. A stream that ends on its own is restarted after 10 s, doubling up to 5 minutes while it keeps dying young. Each launch has a generation, so output from an old stream is never mixed in.
- **Deciding.** `TouchWait` (PetCore) starts a wait after two signals within 1.2 s and ends it after 1.2 s of silence; signals dated in the future (clock set back) count as stale.
- **Showing.** `PetController` puts `touchKey` (desk) or `touchKeyHome` (out of the hole) above every other resting state, even do-not-disturb, and cuts into whatever one-shot plays. When the wait ends it plays `touchDone`, unless the wait lasted 13 s or more: then gpg most likely timed out and there is nothing to celebrate. Under Reduce Motion the key is shown as a still frame.

## Calls

- **Reading.** `MeetingMonitor` (app target, only while `meetingAlerts` is on) asks for full calendar access the first time, then reads the next day of events from EventKit: again on `EKEventStoreChanged`, every 15 minutes, and at each phase boundary (wall-clock timer). All-day, cancelled and declined events are skipped; `MeetingLink` keeps only those with a call link in the URL, location or notes. Titles stay in memory.
- **Deciding.** `MeetingPlan` (PetCore): `soon` from 5 to 1 minute before a call, `now` from 1 minute before to 1 minute after; `nextChange` says when to wake up; `upcoming` is the next call within the hour, for the status card.
- **Showing.** `PetController` puts `meetingSoon` / `meetingNow` above working, resting and talking, below an agent that needs you, an error and the YubiKey. At home the last minute brings the pet out of the hole (not under do-not-disturb). The headset takes the place of a head accessory while it's on. A click on the pet in either state dismisses that call (`MeetingMonitor.dismissCurrent`, by start time; `MeetingPlan` skips dismissed calls) instead of opening the card.
- **Calendars macOS knows.** EventKit only sees calendars added to macOS; apps with their own sync (Notion Calendar) need the account added in Internet Accounts too.

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
| `uiLanguage` | `en` | Interface language: `en` or `ru` |
| `macReactions` | true | React to headphones, music, mic/camera, heat, power, network, screenshots, theme |
| `skin` / `accessory` | `lavender` / `none` | Look |
| `figure` | `cube` | `cube` or `lidman` (LM); LM ignores `skin` and `accessory` |
| `watchCodex` | true | Follow Codex sessions and limits |
| `touchHint` | true | Show when a YubiKey waits for a touch |
| `approveFromPet` | true | Answer Claude Code's permission requests from a card by the pet |
| `hookah` | true | Hookah breaks |
| `meetingAlerts` | false | Get ready for calls from the Mac's calendars |
| `lastCodexLimits` | — | Last known Codex limits |
| `logEvents` | false | Write `~/.pixelpet/events.log` (ids, project and event names only; rotates at 1 MB) |
| `lastLimits` | — | Last known limits |
| `onboarded` | false | Welcome window was seen |
