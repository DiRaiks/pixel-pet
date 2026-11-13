# Architecture

Pixel Pet is one accessory app (`LSUIElement`, no Dock icon) built with SwiftPM. Most of the logic is pure Swift with no AppKit, so unit tests can cover it. The app target connects that logic to windows, timers and system APIs.

## Modules

```
PetCore          pure logic, no AppKit: events, sessions, states, limits, config, geometry, policies
  ├── PetSprites       procedural pixel art: canvas, cube drawing, every state's frames, agent stack
  └── PetIntegrations  unix-socket server, finding and running the Claude Code and Codex CLIs, Codex session files
        └── PixelPet   the app: windows, rendering, input, hotkeys, cards, menus, settings, desktop sensing
```

| Target | Depends on | Holds |
|---|---|---|
| `PetCore` | — | `AgentEvent`, `SessionRegistry`, `PetBrain`, `PetState`, `PetPlayer`, `MotionPolicy`, `UsageLimits` and `Inbound`, `ProbePolicy`, `PetConfig` and `ConfigStore`, `HookSettings` and `HookInstaller`, `HomeSpot` and `HomeGeometry`, `Placement`, `DragTracker`, `Gaze`, `ReactionThrottle` and `Fullscreen`, `TranslationPlan` and `SelectionDecision`, `AskConversation` and `Attachment`, `ClaudeStream` and `ClaudeTranslation`, `CodexRollout`, `AnswerText`, `PermissionPrompt`, `NoticePlan`, `AgentStats` and `RecapPlan`, `BreakClock`, `MacState`, `ActivityState`, `MeetingPlan`, `TouchWait`, `ListenClock` |
| `PetSprites` | `PetCore` | `PixelCanvas`, `Palette` (`Skin`, `Accessory`, `Figure`, `Look`), `CubeDrawing` (`BodyStyle`), `SpriteFactory`, `AgentStack` |
| `PetIntegrations` | `PetCore` | `EventServer` and `HookReply`, `ClaudeLocator`, `ClaudeProcess`, `LimitsProbe`, `ClaudeChat` and `ClaudeAsk`, `AttachmentLoader`, the `ClaudeTranslation` runner (an extension), `CodexWatcher`, `CodexLocator`, `CodexLimitsProbe`, `TouchWatcher` |
| `PixelPet` | all three | `AppDelegate`, `PetController`, `PetPanel`, `SpriteLibrary`, `AgentMonitor`, `StatusMenu`, `StatusPanel` (cards), `TranslationCard`, `AskCard`, `PermissionCard`, `SelectionReader`, `DesktopSensor`, `MacMonitor`, `ActivitySensor`, `MeetingMonitor`, `SpeechListener`, `Notifier`, `UpdateCenter`, `HotKey`, `SettingsWindow`, `OnboardingWindow`, `HookActions`, `SpriteExport` |

The rule: if a decision can be stated without AppKit (a priority, a timeout, a privacy rule, some geometry), it lives in `PetCore` and has tests. The app target only measures the world and acts on those decisions.

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

`HookInstaller` writes two scripts to `~/.pixelpet/bin/`, sets that folder to mode 700, and merges entries into `~/.claude/settings.json`.

- **Hook command.** The single-quoted script path is registered for 13 events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`, `SessionEnd` and `PreCompact`.
  - Upgrades: if our command is on exactly the previous build's events (`isOlderInstall`: all but `PreCompact`), `upgradeIfOlderInstall` adds the missing ones at launch, with the usual backup. Any other partial set (for example, an event the user removed by hand) stays as it is.
  - Timeouts: each entry has 5 s. `PermissionRequest` has 75 s (`PermissionWait.hookTimeout`), because that hook waits for the pet's answer. At launch, an older install's timeouts are updated (`hasStaleTimeouts` / `updateTimeouts`).
  - The entries are recognized by their exact command string. This keeps install, uninstall and the "installed" check idempotent.
- **Statusline.** It is added only when the user has no `statusLine` of their own. A foreign statusline is reported as foreign and left alone.

How the settings file is written:

- A missing or blank file counts as empty. Unparseable JSON or an unexpected `hooks` shape is an error. The installer never overwrites data it does not understand.
- Writes follow symlinks and keep the file's permissions. A timestamped backup is made first. Nothing is written if nothing changed.
- `JSONSerialization` re-sorts the keys of the rewritten file. This is a known cosmetic side effect.

`refreshScriptIfInstalled()` runs at launch, so the scripts always match the running build.

The hook script uses only `sh`, `tr`, `sed`, `grep` and `nc -U`:

- It streams the payload to the socket and adds `pixelpet_app` / `pixelpet_term`.
- It always drains stdin and always exits 0.
- The pet closes every connection right after reading it (about 10 ms per call, measured in the spike). The exception is a permission request the pet answers: that connection waits, at most 70 s.
- When `PIXELPET_INTERNAL` is set, the script does nothing. This keeps the pet's own `claude -p` runs out of the agent list.

### Socket and parsing

`EventServer` listens on `~/.pixelpet/pet.sock`:

- The socket is mode 600, in a mode-700 folder.
- Each connection carries one raw payload, read until EOF.
- A connection may take at most 1 s. A payload may be at most 16 MB, because hook payloads can include large tool output.
- A stale socket file is removed at start. On stop, the file is removed only if it still has our inode.

`Inbound.parse` routes each payload by its shape:

- A payload with `hook_event_name` becomes an `AgentEvent`. The exception is `"Status"`: some CLI versions tag statusline payloads that way.
- A payload with `session_id` plus `model` or `context_window` is a statusline snapshot (model, context %, `rate_limits`).

`AgentEvent.parse` keeps only the session id, the cwd and a small `Kind` enum. It drops prompt text and tool input right there.

### Session rules (`SessionRegistry`)

- **Creation.** Any event creates a session, not only `SessionStart`. Sessions that were already open when the hooks were installed never send `SessionStart`.
- **Answering permission requests.** The pet can answer a `PermissionRequest` from a card next to it.
  - *Hook side.* The hook script tags every payload with where the session runs (`__CFBundleIdentifier`, `TERM_PROGRAM`, only `[A-Za-z0-9._-]` kept). It keeps `nc` open until the pet closes the connection (at most 70 s). It prints the reply only for a `PermissionRequest`, so nothing else listening on the socket can feed a decision to other hooks.
  - *Server side.* The server decides whether to wait, from the parsed JSON. `EventServer` keeps a `PermissionRequest` connection open and gives the app a `HookReply`. The first `send` writes the hook's output (or nothing) and closes. If nothing is sent, the connection closes empty after 66 s.
  - *When the pet waits.* `PermissionDesk` waits only while the setting is on and the pet is on screen (not hidden, covered or in do-not-disturb). It holds at most 16 requests. It releases a request at once if the card cannot be shown.
  - *Safe clicks.* Answers carry the request's id. The buttons become active 0.5 s after a request appears, so a click meant for the previous card cannot answer the next one.
  - *Hook gone.* `HookReply.onGone` checks twice a second whether the hook is still connected (kqueue write EOF). If not, the card is removed.
  - *What the card shows.* `PermissionPrompt` parses the main parameter, the rest of the input, the model's description, and Claude Code's `permission_suggestions` with what they cover.
    - The main parameter is the built-in tool's own (command, file, URL, query). For other tools it is the first of `command`, `file_path`, `path`, `url`, `query`, `pattern`, shown as plain text.
    - The rest of the input follows as `key: value` lines (JSON only for nested values). Shell and edit tools show no other parameters, because Claude Code's own prompt does not show them either.
    - A `command` parameter makes the title say "run a command". A session in the Claude app is called "Claude", not "Claude Code".
    - Bidi, zero-width and control characters are spelled out as `<U+…>`.
    - `PermissionQueue` shows requests oldest first.
  - *The answer.* `PermissionAnswer.hookOutput` writes `decision.behavior` allow or deny. "Don't ask again" adds `updatedPermissions`; deny adds a `message`. The checkbox names the rule only when it is a single plain rule.
  - *Answered elsewhere.* The Claude app shows its own dialog at the same time. It keeps the hook running for up to a minute after the user answers there. No hook reports that answer, or the stopped turn that a denial causes. So, while a session waits for a permission, `AgentMonitor` reads the lines appended to its transcript (`transcript_path`, twice a second, `TranscriptTail`):
    - The call's `tool_result` closes the card and puts the session back to working (`permissionSettled`). It is matched by the hook's `tool_use_id`, or by the session's last `PreToolUse` of that tool.
    - A `[Request interrupted by user…]` entry makes the session idle.
    - Only `type: user` entries count, because request copies (`api-request-blob`) repeat old history.
    - The watch ends with the session's next hook event.
    - A held hook that goes away (`HookReply.onGone`) settles the request the same way.
  - *Giving up.* After `PermissionWait.window` (60 s), on ✕ or "Answer in …", or when the session ends, the pet prints nothing and Claude Code asks the usual way. "Answer in …" also activates that app (`AgentHost`, no Automation permission).
  - `AskUserQuestion` and `ExitPlanMode` keep their own flow.
- **Breaks.** `BreakClock` (PetCore) reads the system idle time every 30 s (`PetController.userIdleProvider`, the same source sleep uses).
  - Input within 5 minutes continues the stretch of work. 5 minutes idle ends it. A longer gap between two reads (the Mac was asleep) also ends it, whatever the idle time says after waking.
  - Past `breakMinutes`, the pet shows the mug for 3 minutes, then hides it for 20 (`repeatAfter`). `snooze` (a click) hides it for 15.
  - A stretch that reached the reminder earns `welcomeBack` (a hop) when work starts again after the break.
  - `PetController.resolvedRest` returns `breakHint` (after a `yawn` one-shot) over work and rest. It does not show over an error, an agent that waits, a call, do-not-disturb, a dimmed pet (fullscreen) or home.
  - `workedNearReminder` feeds the status panel's "No break for" line. It shows in the last 15 minutes before the reminder and while the reminder is due.
- **Weekly recap.**
  - `AgentStats` (PetCore) keeps sums per local day ("yyyy-MM-dd"): Claude and Codex active seconds, turns and steps per project folder; waits for the user (count and seconds); answers from the permission card; the 5-hour limit's peak and hits (a window counts once, by its reset time); and the day's longest turn.
  - `AgentMonitor.count` records a turn when a session's `finishedAt` changes. `lastWork` is the turn's active work without waits, from `SessionRegistry.finish`. It records a wait when a session leaves `waiting`. Codex lines read late do not count.
  - `StatsKeeper` holds the stats. It writes `~/.pixelpet/stats.json` (`StatsStore`) at most once a minute and on quit, and keeps 8 weeks. It records nothing while the setting is off.
  - `AgentStats.summary(of:)` builds a `WeekSummary` for an ISO week (Monday first, local time zone).
  - `RecapPlan.due` is true once per week (`recapShownFor`), from Monday 6:00, when last week had agent time on at least two days.
  - `AppDelegate.checkRecap` runs 20 s after launch and then every 5 minutes, only while the pet is on screen. When due, it calls `PetController.setNews`. The pet plays `newspaperOpen` and rests in `newspaper` while its mood is idle and do-not-disturb is off. A click on the pet (or the menu item) opens `RecapPanel` and clears the news.
- **Notifications.**
  - `NoticePlan.action` (PetCore) compares a session before and after each event, together with the registry's reaction:
    - reaction `finished` / `finishedBig` or `failed`: post that;
    - a new wait, or a change of what it waits for: post `permission` or `question`;
    - starting to work or leaving a wait: clear;
    - a session that ends, or that `prune` drops: clear.
  - `NoticePlan.posts` allows a post for `NotificationMode.always`, or for `whenHidden` while the pet is not on screen. It never posts in do-not-disturb. A permission that the card by the pet is showing is not posted.
  - `Notifier` (UserNotifications) posts banners with no sound. It uses one identifier per session (`claude-…`, `codex-…`, `key-touch`), so a new post replaces the last one. A generation counter stops a post that still waits for authorization from landing after a clear.
  - It asks for `.alert` only, the first time it posts. It gives the session's host bundle (`AgentEvent.host`, from the hook's tags) to the click handler, which activates that app.
  - `NoticeText` writes the project and what happened, never the step's object.
  - The key's notification follows `PetController.onTouching` and its own setting (`touchNotification`), not `NotificationMode`. The key waits on the user right now, so it posts even with the pet in sight and in do-not-disturb.
  - Codex lines read late (catch-up) clear notifications but do not post.
- **Stopped turns.** Esc fires no hook. Every hook payload carries `transcript_path`, which is kept on the session. `AgentMonitor.checkInterrupts` runs every 3 s. For a working or waiting session that has been quiet for 4 s and whose transcript has grown since the last check, it reads the file's last 64 KB. If the newest user or assistant entry is "[Request interrupted by user…]" (`PermissionPrompt.endsInterrupted`), it applies `.interrupted`. The session then goes idle at once, instead of after the 5-minute quiet timeout (or never, if a tool was running).
- **Steps and the turn.**
  - `AgentEvent.parse` turns a `PreToolUse` input into an `AgentStep`: an action and a short object.
    - Actions: runs, reads, edits, writes, searches, finds files, opens, searches the web, subagent, or the tool's name.
    - Objects: the command's first line, a file name without its path, a pattern, a URL's host, a query, or a subagent's description. It is cut to 60 characters, with hidden characters spelled out.
    - The rest of the input is dropped. Steps are never logged or written to disk.
  - The session keeps the current `step` and `stepSince` (the call's `PostToolUse` clears it to "thinking"), `turnStartedAt`, the turn's `steps` count (questions don't count), and `lastTurn` when the turn ends.
  - The status card shows the step with an m:ss clock, the turn's length and steps, and afterwards "Done N ago, took M". While open, it updates every second (`CardPanel.tickInterval`).
  - Codex reports no tools, so its rows show only the turn clock.
- **Working and waiting.**
  - A prompt or a tool start means working.
  - Waiting: a permission request; the `permission_prompt` and `elicitation_dialog` notifications; an open `AskUserQuestion` or `ExitPlanMode` call until its matching `PostToolUse`; and a Claude desktop turn that ends with a `wrap_up` call with a non-empty `ask` (waits after `Stop`).
  - Each wait records what it waits for (`waitingFor`): a permission (permission requests and prompts) or a question (the question tools, elicitations, turn-end questions).
- **Turn ends.** `Stop` ends the turn, and so does an `idle_prompt` notification. `StopFailure` marks the session as failed.
- **Subagents.** They are tracked between `SubagentStart` and `SubagentStop`, so the post-turn summary agent (which stops without a start) is ignored.
  - A tool call with an `agent_id` (it ran inside a subagent) does not make the session work again while the session is between turns (`betweenTurns`: after a finished, failed or interrupted turn, or after a start with no prompt yet). The reason: the Claude app's post-turn helper sometimes runs a tool with no `PostToolUse` after it.
  - The session's own agent (no `agent_id`) starting again after `Stop` still counts.
- **Reactions.** A finished turn earns a celebration only after at least 20 s of active work. Time spent waiting for the user does not count. A turn of 10 minutes or more earns the somersault (`finishedBig` → `flip`).
- **Interrupts.** A working session with no tool running and no events for 5 minutes is treated as interrupted, because Esc sends no `Stop`.
- **Background subagents.** A `Stop` while subagents still run keeps the session working (`turnEnded`). The session finishes, and celebrates by the work done, when the last `SubagentStop` arrives. Subagents carry over to a new prompt. The silent-work timeout clears subagents whose stop never came.
- **Expiry.**
  - Sessions with no events for 30 minutes are dropped.
  - Sessions waiting on a permission prompt or an open question tool never expire. A turn-end question from Claude desktop goes back to idle after 30 minutes.
  - Ended session ids are remembered (up to 500), so late events cannot bring them back. A `SessionStart` or prompt with that id does bring it back, because the Claude app ends a session when it unloads it and later resumes it with the same id.

### Turning sessions into a picture (`PetBrain`)

`PetBrain.baseState` picks the state in this priority order:

1. error, if a session failed within the last 3 s;
2. alert, if any waiting session needs a permission; otherwise question, if any session waits;
3. exhausted, when a limit is used up (≥ 100%) and no agent is working (working agents mean the limit did not stop them);
4. low limit (5-hour usage ≥ 85% or weekly ≥ 90%);
5. working;
6. idle.

On top of that base state:

- `restState` turns idle into sleep after `sleepAfterMinutes` without user input. The idle time is read live each time.
- Idle on a low battery (`PowerReading.isLow`: 20% or less and not on the adapter, from `PowerMonitor`'s IOKit notifications) becomes `tired`.
- At home, `homeState` maps error, alert and question to `peekHold`, and everything else to `burrowed`. Under do-not-disturb, alert and question stay `burrowed` too.
- At home, one-shots become a `peek`, or nothing under do-not-disturb.

`PetBrain.cubes` maps sessions to agent blocks. A finished session flashes green for 1.5 s.

`nextChange` tells `AgentMonitor` when the picture will change without a new event. So one timer is enough, and nothing polls fast.

### Limits

There are three sources, merged window by window. Within one window, usage only grows. So the window that resets later wins, and for the same window the higher usage wins.

1. **`rate_limit_event` from every `claude -p` run.** This is the main source, because the statusline never runs for Claude desktop sessions.
2. **Statusline snapshots** from terminal sessions.
3. **The last known limits**, saved in the config, so the panel is not empty after a restart.

When nothing else reports limits, `LimitsProbe` runs a one-word `claude -p` with haiku and no tools. `ProbePolicy` allows it at these points:

| Trigger | Condition |
|---|---|
| Launch, or opening the panel | Only if the known limits are older than 10 minutes |
| Agents are active | Only if both the known limits and the last probe are older than 30 minutes |
| Manual refresh | Any time the gates below allow |

Gates for every trigger, manual refresh included:

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
- is tracked while it runs. `ClaudeProcesses.terminateAll` stops the remaining runs when the app quits. SIGTERM to the app quits it the normal way, through a dispatch signal source;
- removes `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL` and the Bedrock, Vertex and Foundry switches from the environment, so the run bills the subscription;
- sets `PIXELPET_INTERNAL=1`;
- passes text over stdin (the probe passes its fixed prompt as an argument instead);
- on cancel or timeout, gets SIGTERM and then SIGKILL.

The three callers:

| Caller | Model | Notes |
|---|---|---|
| `LimitsProbe` | haiku | One-word prompt, `--no-session-persistence` |
| `ClaudeAsk` (quick question) | `askModel` | Appended system prompt; follow-ups use `--resume <session>` |
| `ClaudeTranslation.run` | sonnet | `--no-session-persistence`, streamed |

`ClaudeStream` parses the stream. An answer is done at `message_stop`. The `result` line arrives about 1.5 s later; the pet does not wait for it.

**Files.** `PetView` accepts file URLs dragged onto it.

- While files are over the pet, it rests in `catchOpen`.
- A drop goes to `Asker.attach`. It reads up to `Attachment.maxFiles` with `AttachmentLoader` (PetIntegrations), off the main thread:
  - text and code: when the bytes are UTF-8 with no NUL near the start; cut to `Attachment.maxText`;
  - PDF: its text through PDFKit, or its first page as an image when it has no text;
  - images: through ImageIO's thumbnail at `Attachment.imageSide`, JPEG for photos, PNG otherwise.
- Folders, unknown types, files over 30 MB and empty files are refused with a reason.
- If files are taken, the pet plays `swallow` and opens the card. If none is taken, it plays `shakeHead`.
- The next question carries the files. `Attachment.prompt` puts each text in a `<file name="…">` block before the question. With any image, the message goes as one `--input-format stream-json` line with image blocks (`Attachment.streamMessage`). `AskConversation.Turn.files` keeps the names for the history.

`AskConversation` binds every run's events to an epoch (increased by "New") and a turn index. Late events from an old conversation or a finished turn are dropped. The next question waits until the previous CLI process has exited.

Quick-question sessions live in the `~/.claude/projects` folder that Claude Code names after the pet's workdir (`ClaudeWorkdir.projectFolderName`: every character except ASCII letters and digits becomes "-", for the path as given and as resolved). They are deleted on "New", on quit and on launch. Only those exact folder names (and the old probe workdir's) are removed, never a project whose name only ends the same way.

## Codex integration

Codex has hooks too, but the pet does not use them:

- each hook must be trusted one by one in the Codex CLI;
- they add nothing that Codex does not already show elsewhere;
- it is not documented whether the desktop app runs them.

Codex session files, on the other hand, are written by every Codex surface (CLI, IDE extension, desktop app) and need no setup. So the pet reads those.

- **Following.** `CodexWatcher` listens to FSEvents under `~/.codex/sessions`, on its own serial queue, to find new and changed files.
  - FSEvents stops reporting a file that stays open for writing, and Codex keeps its session file open for the whole session. So each followed file also gets a kqueue source (`extend` / `write`) that fires on every append.
  - At most 32 files are followed. A file with no change for a day is released.
  - A big file is never read whole. At start, and for files that appear later, the watcher reads the first line (the session's metadata, up to 1 MB) and the last 512 KB. It drops the partial line where the tail starts.
  - After that, only appended bytes are read, again capped to the last 512 KB after a long gap. An unfinished last line waits for the rest.
  - At start, only files modified in the last 30 minutes are opened.
  - Spawned agents' files are followed like the others. Codex's helper threads are remembered and skipped.
  - Lines over 4 MB are dropped. A file that got shorter is read again from the start.
  - `~/.codex` is never created. Without it, the watcher checks once a minute until it appears.
  - `stop()` cancels a catch-up between files. The FSEvents stream retains the watcher, so no callback runs after it is gone.
- **Only Codex agents.** Ordinary ChatGPT conversations, including those in the desktop app, run in the cloud and write nothing here. Only Codex threads write files (CLI, IDE extension, the Codex side of the app).
- **Parsing.** `CodexRollout` maps lines to the same `AgentEvent`s that the Claude Code hooks produce. Each event has the line's own timestamp.

  | Codex line | Event |
  |---|---|
  | `session_meta` | session start (id, folder); see below for threads Codex started itself |
  | `turn_context` | session start with the model and folder |
  | `event_msg` `task_started` | prompt submitted (working) |
  | `event_msg` `task_complete` | stopped (celebration rules apply) |
  | `event_msg` `turn_aborted` | interrupted: idle, no celebration |
  | `event_msg` `error` | failed |
  | any line inside an open turn | still working; when reading from the middle of a file, a `turn_id` opens the turn. Lines of a turn that already ended are ignored |
  | `event_msg` `token_count` | Codex limits (`rate_limits.primary` / `secondary`, told apart by window length) |

  **Threads that Codex started itself** are recognized by `session_meta`: a `thread_source` other than `user`, or, in older files, a `source` of `{"subagent": …}`.

  - **Spawned agents** (`spawn_agent`): a `thread_spawn` source that names its parent, or `thread_source` `subagent` with no source kind and a top-level `parent_thread_id`. Such an agent counts as its parent's subagent:
    - its turn starting, and every line inside the turn, become the parent session's `subagentStarted` (with the agent's own id);
    - its turn completing, aborting or failing becomes `subagentStopped`;
    - nothing else from its file reaches the parent, not even its folder.
  - Result: the parent's block gets its dot, the pet plays `spawn` and `recall`, and a parent whose turn ended first keeps working until its agents are done. This matches Claude Code's background subagents.
  - An agent spawned by a spawned agent counts for the session at the top of the chain.
  - `CodexWatcher` remembers each agent's parent (up to 256) and settles each batch before it goes out:
    - If a link of the chain is not followed (a parent quiet for longer than the catch-up window, or released), the watcher finds its file by the id in the file name and opens it. Its lines go first.
    - Events whose chain does not end at a followed, user-started session (no parent file, a helper thread) are dropped, so no session is invented.
    - The batch is sorted by time. At start, one batch holds every file, and a parent's end must not come before its agent's start.
  - Spawned agents' files count toward the 32 followed files like any other.
  - Codex does not write spawning or closing an agent into the parent's file. It writes only the agent's own turns.
  - Codex's other threads (approval review, compaction, memory consolidation, or a subagent that names no parent) are skipped.

  Approval prompts are not written to the files, so Codex sessions never show as waiting.
- **State.** `AgentMonitor` keeps Codex sessions in a second `SessionRegistry`, without the silent-work timeout. Codex writes `turn_aborted` when a turn is stopped, so a quiet turn (a long build) stays working.
  - The pet's mood uses both registries (a failing or working Codex agent shows like a Claude one). The drained body and the low-limit look stay tied to Claude's limits.
  - Only events at most 10 s old trigger reactions, and catch-up batches never do. So turns found in a file read late are not celebrated.
  - Batches from a watcher that was switched off are dropped.
- **Limits.** Besides the `token_count` lines, `CodexLimitsProbe` asks a short-lived `codex app-server` over JSON-RPC (`initialize`, `initialized`, `account/rateLimits/read`). It runs at launch and when the panel opens, under the same `ProbePolicy` rules as Claude's probe. It makes no model request. The server quits when its input closes, so `ClaudeProcess` keeps the input open (`until`) and stops the process once the answer arrives.
- **Finding Codex.** `CodexLocator` accepts only native Mach-O binaries. It checks `PATH`, then the copy inside ChatGPT.app or Codex.app, then the newest standalone release under `~/.codex/packages/standalone/releases`. The npm `codex` is a Node script, and apps launched from Finder have no Node on their PATH.

## Rendering

- **Window.** `PetPanel` is a borderless, non-activating `NSPanel`. It joins all Spaces and works over fullscreen apps. It never takes focus. Fully transparent pixels let clicks through (alpha hit-test). `constrainFrameRect` is overridden so that, at home, the window can hang over the menu bar.
- **Layers, not SpriteKit.** The spike measured SpriteKit at 2–8% CPU and about 125 MB. Swapping `CGImage`s in a `CALayer` costs 0.1–0.2% and about 12 MB. Core Animation moves the window (throws, easing home) in the render server.
- **Frames.** `SpriteFactory` draws every state procedurally on a 32×32 `PixelCanvas`. It started as a port of [`prototype/sprites.html`](prototype/sprites.html).
  - `SpriteLibrary` renders all base frames for the current `Look` once (a few hundred KB).
  - Variants made on demand (limit drain rows, gaze direction) go into a bounded cache.
  - The window scale is a whole number (×2 to ×6), with nearest-neighbor filtering.
- **Style.** Shading is hue-shifted: two shade steps, a rim light, a colored outline, blush, and breathing through the highlight.
  - **Skins:** lavender, mint, peach, graphite (`mono`), sky, sakura, vanilla and night (dark body, light outline and face), plus the red `error` skin. New skins avoid the agent colors (teal, amber, red), so the pet never looks like a block's state.
  - **Accessories:** glasses, sunglasses, headphones, cap, beanie, crown, bow, flower, propeller hat, scarf, mustache. Head accessories (`isOnHead`) hide the work headband.
  - **Figures:** the cube, LM and the paperclip.
  - **LM** (`Figure.lidman`): a round drop with a V cut into its top, a two-tone diamond above it, and big white eyes.
    - `drawLidMan` replaces only the body and `lidManFace` only the face, so states and props are shared with the cube.
    - The diamond gets the rows above the body (at least 4; the top of a big jump is a little lower for LM). So the diamond squashes instead of leaving the canvas. Turning frames can still touch an edge.
    - That rule is off in the home hole (`BodyStyle.inHole`). There LM peeks out 2 rows less than the cube (`SpriteFactory.lidManPeekRaise`): his eyes and the round bottom of the drop.
    - His big pupils follow the gaze (cursor, glances) like the cube's eyes.
    - LM always uses the `lidman` skin and no accessory.
    - Marks drawn over the middle of the head ("!", the spent clock) move aside for the diamond (`Look.headMarkShift`). Smaller marks (sparkles, spawn copies) may overlap it.
  - **The paperclip** (`Figure.clip`, `ClipDrawing.swift`): a two-pixel wire bent like a paperclip standing on end.
    - It is traced from line and arc segments (`WireSegment`) and lit from the upper left: the skin's highlight on the lit half, its outline on the other half.
    - Its lower part fills the body box, so desks and props line up.
    - The top loop (over the left strands) rises like LM's diamond: 60% of the height, at most 8 rows, one row below the canvas top. The body keeps 5 rows free for it.
    - Both free ends stop in the box below the eyes. The outer end, on the right with space above it, is what makes it read as a paperclip. When the ends stopped behind the eyes they were hidden, and the shape looked like a U-magnet.
    - Two round eyes (6×7 rings) sit in front of the wire on the loop. Every `Eyes` case is drawn inside them (lids in the skin's fill), and the pupils follow the gaze. The eyes use the darker of the face color and the fill, so the night skin's light face does not disappear on white.
    - It uses the color setting and wears no accessory. It does wear the headband, nightcap, call headset, headphones and party hat (halfway down the loop, over the eyes).
    - Its eyes sit high, so it hangs 6 rows further out of the home hole (`SpriteFactory.clipPeekDrop`).
  - **Every day new** (`Look.resolve` with `daily`): the skin and accessory are picked from the date alone. A day keeps its look across restarts, and two days in a row never match. The pet redraws at midnight and after waking.
  - **Rotation** (flip, tumble) uses 3×3 supersampling with a deterministic majority vote. Accessories turn with the body; the face is redrawn upright.
- **Timing.** Each `PetState` has a duration per frame, so key poses are held and in-between frames are quick.
  - `PetPlayer` plays a looping base state with an optional one-shot on top.
  - `PetController` schedules exactly one timer per frame, set to the end of the current frame, with a tolerance of 25% capped at 50 ms.
  - While agent blocks are visible, the clock also keeps their shared 10 Hz beat.
  - The timer stops completely while the pet is hidden or occluded, or frozen under Reduce Motion.
- **Agent stack.** `AgentStack` draws the 3×3 blocks on a separate 32×32 overlay: Claude Code at x 27–29 to the right of the body, Codex mirrored at x 2–4 on the left. Each block has its subagent dot on the outer side. Poses the pet holds while agents run stay clear of both columns (a test checks the left one). At home the stack is hidden, and the menu-bar counter replaces it.
- **Reduce Motion.** `MotionPolicy` has three lists:
  - `stillFrame`: looping states that hold one frame, for example alert, error, dragged, low limit, the key touch, question, exhausted, the call, the Mac's resting states, the newspaper, the break hint, listening and the activity rests.
  - `allowsOneShot`: one-shots that are mostly movement are skipped (hop, celebrate, drop, dive, peek, flip, tumble, drip, melt, yawn, shy, angry, wave, launch, purr, sneeze, the Mac's one-shots, work moments and glances, spawn and recall, compact, throws, hookah, and others).
  - `cue`: some skipped one-shots show one held frame for 1.5 s instead, so the event still registers (for example celebrate, peek, shy, angry, refill, plug-in, dizzy, the USB, display and layout one-offs).

### States

`PetState` has 88 cases. The full list, with frame durations, is in `Sources/PetCore/PetState.swift`; `loops` says which ones loop.

| Kind | States |
|---|---|
| Looping (moods) | `idle`, `working`, `alert`, `question`, `lowLimit`, `exhausted`, `error`, `sleep`, `tired` |
| Looping (home and helpers) | `burrowed`, `peekHold`, `dragged`, `talk`, `catchOpen`, `listening`, `listenQuiet` |
| Looping (rests over idle or work) | `music`, `onAir`, `overheated`, `lowPower`, `offline`, `typingAlong`, `gamepad`, `popcorn`, `coding`, `touchKey`, `touchKeyHome`, `meetingSoon`, `meetingNow`, `newspaper`, `breakHint`, `updateWait`, `updateUnpack` |
| One-shots (pet) | `hop`, `celebrate`, `drop`, `peek`, `dive`, `yawn`, `shy`, `angry`, `flip`, `tumble`, `drip`, `melt`, `wave`, `launch`, `purr`, `sneeze`, `thrown`, `dizzy`, `splatLeft`, `splatRight`, `hookah`, `hookahCloud` |
| One-shots (agents and work) | `workSip`, `workStretch`, `workThink`, `workRush`, `glanceLeft`, `glanceRight`, `refill`, `spawn`, `recall`, `spawnDesk`, `recallDesk`, `compact`, `touchDone` |
| One-shots (the Mac and the user) | `headphonesOn`, `headphonesOff`, `batteryFull`, `screenshot`, `darkMode`, `lightMode`, `plugIn`, `appLaunched`, `appQuit`, `usbIn`, `usbOut`, `newDisplay`, `layoutSwitch` |
| One-shots (cards and features) | `newspaperOpen`, `swallow`, `shakeHead`, `listenIn`, `listenOut`, `updateArrive`, `updateDone` |

## Home: notch and burrow

`HomeSpot` and `HomeGeometry` compute a home spot at the top center of each screen. On a notched screen, the notch's center is the gap between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`; the window hangs so the eyes sit just under the cut-out. Other screens get a drawn black "burrow".

How the pet moves between the desk and home:

- **Drop.** The pet goes to a screen's home when it is released with its top at or above that screen's top edge, or within 60 pt below it, anywhere along the edge. It also goes home when it ends within 90 pt of the home itself. For a throw, both the release point and the landing point are checked.
- **Pull out.** A drag that starts at home puts the pet back only if it is released within 24 pt of its seat. So a short pull is enough to get it out. Other homes keep the normal rules during that drag.
- **Hover.** Hovering over the home makes the pet peek out after a short delay, so a cursor that only passes over the menu bar does not trigger it.
- **Do not disturb.** Turning it on sends the pet home. Turning it off clears it only if the pet really ends up on the desk.
- **Screen changes.** The home display is remembered. After display sleep or unlock the window is placed again, because macOS reports different geometry while the screen is locked.

### Moments from events

`AgentMonitor` compares each refresh with the previous one:

- More subagents than before plays `spawn`; all of them gone plays `recall`. `SubagentMoments` limits this: a spawn at most every 30 s, and a recall only after a shown spawn whose subagents ran at least 5 s. Over a typing pet, `PetState.atDesk` uses `spawnDesk` / `recallDesk` instead, which keep it at the keyboard.
- The 5-hour window resetting after at least 10% use plays `refill` (`UsageLimits.refilled`).
- `PreCompact` (and Codex's `compacted` lines) play `compact`.
- Plugging in plays `plugIn`.

`PetController.moment` lets these through only on the desk, over a calm or working pet, with nothing else playing. Catch-up batches never trigger them.

## Desktop reactions

`DesktopSensor` needs no extra permissions. It uses mouse monitors, the system idle counter and window bounds. It never reads window titles.

- **Gaze.** The eyes follow the cursor within 300 pt, by ±1 px. The mouse monitor runs only while reactions are on and the pet is visible and on the desk. It is throttled to 10 Hz.
- **Glance.** The pet glances toward the frontmost window of an app the user switches to. Normal apps only, at most once every 10 s.
- **Fullscreen.** Over a fullscreen window the pet dims instead of hiding.
- **Throws.** A release at 1,200 pt/s or faster plays `thrown` (quarter turns, lossless) while the window flies. When it arrives, the landing is:
  - `splatLeft` / `splatRight` if the aim was clamped at that side of the screen (`Placement.throwOutcome`);
  - `dizzy` if the drag was shaken (`DragTracker.isShaken`: four quick horizontal reversals of at least 20 pt within 1.2 s);
  - otherwise `drop`.
- **Late night.** From 22:00 to 05:00 (the Mac's local time), desk poses get a lamp and tea instead of coffee (`NightDesk`).
  - Every third night (`NightDesk.light`, picked from the evening's date, so it never changes in the middle of a night) a candle replaces the lamp. On holidays the pumpkin or fir stands in that spot instead.
  - The candle burns down in four steps (`candleMelt`, carried in `WorkProps.candle(melted:)`). It flickers through the frames; it is drawn in `overlays`, so its glow tints the body without adding pixels.
  - The desk is redrawn every hour through the night (`nextRedraw`).
- **Away and back.** Sleep uses the live idle time. The pet hops when the user returns, and greets after the Mac wakes.

`PetController` adds the personality layer:

- **Fidgets.** Yawn, tumble and sneeze (about a sixth are sneezes). For LM, `drip` or `melt` (about half and half) replace tumble (`Breaks.fidget(lidMan:)`). They play every 90–240 s, only while idle on the desk, with reactions on, no card open and Reduce Motion off.
- **Tool bubble.** `ToolKind.current` takes the `currentTool` of the working Claude session heard from last. It maps built-in tools to an icon (run, search, read, edit). `PetController.workProps` adds it at the desk (`WorkProps.toolRun` and similar). It stays 2.5 s after a tool ends, so it does not blink between calls. Other tools, Codex and MCP show no bubble.
- **Waving.** `SessionRegistry` keeps `waitingSince` per session. `AgentMonitor` passes the oldest wait to `PetController.setWaitingSince`. That schedules `wave` with `WaitNudge.next`: one minute after the wait starts, then every 45 s. It plays over a resting `alert` or `question`, but not at home, over a card or under Reduce Motion. If the pet was too busy, the wave is tried again a few seconds later.
- **Rocket.** `AgentEvent.parse` marks a successful `PostToolUse` of Bash whose command runs `git push` as `pushed`. `isGitPush` blanks quoted text first, so a commit message that mentions it does not count; `-n` / `--dry-run` do not count either. The command itself is not kept. `AgentMonitor` plays `launch` through `moment`, at most once a minute. A launch that could not play does not use up the minute.
- **Petting.** `PetView` reports mouse moves. `PettingDetector` counts direction changes of strokes of 4 pt or more. Three within 1.2 s pet the pet (`purr`), at most every 10 s, on the desk, over an idle, working or tired pet. Strokes count only while the pet is free to react.
- **Holidays.** `Holiday.on` (by the Mac's date) adds `WorkProps.pumpkin` (October 25–31) or `.fir` (December 20 – January 7). They are drawn wherever the pet stands on the floor (`SpriteFactory.showsFloorProps`: not at home, in the air or against a wall). The midnight redraw changes them. New art stays out of the agent columns (0–4 and 27–31) below row 8; a test checks it.
- **The Mac.** `MacMonitor` (app target) listens without polling, asks for no permission, and reads flags only.
  - Sources:
    - CoreAudio: the default output's transport (Bluetooth or the built-in headphone jack) and whether it runs; whether the default input runs;
    - CoreMediaIO: whether any camera runs;
    - `ProcessInfo` thermal and low-power notifications;
    - `NWPathMonitor`;
    - a live Spotlight query for new screenshots (`kMDItemIsScreenCapture`);
    - the distributed theme notification.
  - Debouncing: `SoundDebounce` treats 10 s of sound as music and keeps it through gaps of up to 5 s. When the default output changes, a stream already open on the new device (for example a paused player moved over from unplugged headphones) does not count until it stops once (`outputChanged`). `OfflineDebounce` waits 5 s.
  - Audio details: virtual and aggregate audio devices never count as running. The output counts as playing only when some process has output running that is neither of these:
    - a macOS service that keeps its stream open (PowerChime, corespeechd: `AudioClient.isSystemService`);
    - a call (`AudioClient.isCall`): the same process also has input running (a call in the browser), or it is a call app such as Zoom, Teams, Slack, Telegram or FaceTime (helpers included, since some let go of a muted mic), or `avconferenced`.

    `MacMonitor` reads `kAudioHardwarePropertyProcessObjectList` and listens to each process's `kAudioProcessPropertyIsRunningOutput` and `kAudioProcessPropertyIsRunningInput`, because the device flag stays on when a player starts next to such a service. If the list cannot be read, the device flag alone decides.
  - Result: the `MacState` goes to `PetController.setMac`.
    - `MacState.rest(insteadOf:)` replaces only an idle rest, in this order: mic/camera, heat, network, low power, music.
    - Headphones become part of the look (`LookExtras.headphones`, drawn by the body in every upright pose), with a put-on or take-off one-shot. Worn headphones replace a head accessory, like the call headset.
    - Screenshots, the theme and `PowerReading.becameFull` play one-shots through `moment`.
    - `PartyTime` adds `LookExtras.partyHat` on Friday from 17:00. The day-change timer also wakes then.
  - Timing rules: the first reading, and the reset when stopping, apply without animation. Headphones settle for 1.5 s before the look (and every sprite) is rebuilt. A full battery is celebrated once per plug-in. One-offs wait while on air.
  - A click over one of these resting states adds it to `MacDismissals`. `rest(insteadOf:skipping:)` skips it until `MacState.isActive` says its condition ended.
  - Calls and music: music never shows during a call (`MacState.inCall`: the mic or camera is on, or a call's sound plays, `callSound`), even with the call clicked away. Sound during a call is the call. A call clicked away stays away while either lasts, so muting in an app that lets go of the mic does not bring it back. Known limits: a call in the browser with the mic muted and let go plays like any page; a call app's videos and voice notes, and apps that record while they play (a DAW, a screen recorder), never count as music.
  - The "React to the Mac" setting (`macReactions`) stops the monitor and removes the hat.
- **Shy** after the cursor rests on the pet for 2 s, at most once a minute.
- **Hookah breaks** (`Breaks`). When the setting allows it, about one idle fidget in four is a hookah. A big finished task (the somersault) is followed by one about a third of the time, if the pet is idle on the desk by then. About one in four ends in a big cloud (`hookahCloud`) instead of rings. The hookah stands in columns 20–26, clear of the Claude blocks.
- **Angry** after 5 clicks within 3 s. The status card still opens. Clicks at home do not count.
- **Typing loop.** `working` plays `TypingScript`: about 12 s of bursts (4–13 keys) at a varied pace, sometimes a key held longer, and varied pauses (a look up at the screen, a blink, a short stop). It is generated from a fixed seed, so it does not feel like a loop but stays deterministic. It has no smile; smiles come with moments and finishes.
- **Work moments** (sip, stretch, think, rush) play every 45–120 s while the pet types at the desk, never the same one twice in a row (`WorkMoments`). The fidget gates apply, and they play only over the plain typing loop.
- **Glances** at the agent blocks. When an agent on one side finishes, fails, starts waiting or working, or joins others (`WorkMoments.noticeable`), the pet looks left (Codex) or right (Claude), at most once every 8 s. These do not count: the first blocks at launch, catch-up batches, the green flash fading, and sessions being dropped. A moment that plays at the keyboard stops when the typing stops (talking, an alert, Reduce Motion).
- **Desk props** grow with the work session (`WorkSession`, `WorkStage`): the time the pet spends typing, across turns and agents.
  - Pauses of up to 10 minutes between turns are not counted and do not end the session. A longer break clears the desk.
  - A mug appears after 10 minutes, a headband after 30. `AgentMonitor` wakes at the next threshold.
  - Props are drawn into every desk pose (`PetState.isAtDesk`) and cached as variants by `SpriteLibrary`. Reduce Motion keeps them.
- **Strain** grows with the number of blocks working at once, Claude Code and Codex together (`PetBrain.strain`: 1 → 0, 2–3 → 1, 4–5 → 2, 6+ → 3). It is passed as `WorkProps.strain(_:)` and redrawn when the level changes.
  - Only the typing loop shows it: more keys lit per stroke, sweat (one side, then both), then a held out-of-breath mouth and red cheeks. At the top level: steam from the figure's top row, sparks from the keys, a squeeze for the blink, and one pixel of shake on the dips only.
  - Everything else follows the clock in 300 ms steps, so hours of typing stay calm.

## YubiKey touch

- **Signal.** While a YubiKey waits for its button during a GPG operation, macOS's smart-card reader service (`usbsmartcardreaderd`, subsystem CryptoTokenKit) logs "Time extension received" about three times a second. The messages stop once the key is touched or gpg gives up (about 14 s). This works when GnuPG reaches the key through the system's PC/SC. GnuPG's own CCID driver would bypass the service.
- **Watching.** `TouchWatcher` keeps one `log stream --level debug --style ndjson` running, filtered by predicate to exactly that message (no measurable CPU, about 4 MB).
  - It runs under a small `sh` watchdog that kills the stream when the app's pid is gone, so a crash leaves nothing running.
  - A stream that ends by itself is restarted after 10 s. The delay doubles, up to 5 minutes, while the stream keeps dying soon after start.
  - Each launch has a generation number, so output from an old stream is never mixed in.
- **Deciding.** `TouchWait` (PetCore) starts a wait after two signals within 1.2 s and ends it after 1.2 s of silence. Signals dated in the future (clock set back) count as stale.
- **Showing.** `PetController` puts `touchKey` (desk) or `touchKeyHome` (out of the hole) above every other resting state, even do-not-disturb, and interrupts any one-shot. When the wait ends it plays `touchDone`, unless the wait lasted 13 s or more: then gpg most likely timed out and there is nothing to celebrate. Under Reduce Motion the key is a still frame.

## What the user does

`ActivitySensor` (app target, only while `activityReactions` is on) asks for no permission and reads no content. Its decisions live in PetCore (`Activity.swift`).

- **The app in front.** `didActivateApplication` gives the frontmost app. Only regular apps count: Spotlight, Raycast and menu-bar apps coming forward change nothing.
  - `AppKind.of` checks the bundle id first, for well-known terminals, editors and players whose category is missing or different. Otherwise it reads `LSApplicationCategoryType` (games, video or entertainment, developer tools).
  - `AppFocus` counts a kind after `settle` (90 s) in front. Switching between apps of the same kind keeps the clock. A timer checks again when the kind is due.
- **Typing.** Once a second, while the pet is on the desk (not hidden or at home), the sensor reads `CGEventSource.secondsSinceLastEventType(.combinedSessionState, .keyDown)`. This is only the time since the last key press, never a key, and needs no Input Monitoring permission. `TypingDetector` starts after 6 s of keys at most 1.5 s apart and stops after 4 s without a key. A wake resets it.
- **Resting states.** `ActivityState.rest(insteadOf:skipping:)` replaces only `idle`. It runs after `MacState.rest`, so a call, heat, the network, low power and music come first. Order: `gamepad`, `popcorn`, `typingAlong`, `coding`.
  - A click adds the shown state to `ActivityDismissals` until `isActive` says its condition ended (the kind of app changed).
  - Typing stops at every pause, so a dismissed `typingAlong` stays dismissed until the keys rest for `typingGrace` (60 s).
- **One-offs** go through `PetController.activityMoment`. It needs `mood == .idle` and no do-not-disturb, then applies `moment`'s usual gates (on the desk, nothing else playing, not on a call).
  - Throttles are checked with `ReactionThrottle.allows` and used up (`mark`) only when the one-off played.
  - A quiet minute (`settleAfterStart`) follows start, `didWake`, `screensDidWake` and `sessionDidBecomeActive`, because login items open and displays and Spaces come back in a burst. It blocks Space switches, app launches and new displays.
  - Spaces: `SpaceSwitches` plays `dizzy` for 4 switches within 12 s, at most every 2 minutes. A single switch shows nothing: macOS hides windows that join all Spaces while it slides, so anything played would come late.
  - Apps: a regular app launching plays `appLaunched` (at most every 2 minutes). A regular app quitting after 30 minutes or more of use (`NSRunningApplication.launchDate`) plays `appQuit` (at most every 2 minutes).
  - USB: a mounted volume that is removable or ejectable, local, not internal and not a disk image (DiskArbitration's device protocol "Virtual Interface", `RemovableVolume`) plays `usbIn`. Its path is remembered (as are those mounted at start), because an unmounted volume cannot be queried. Its unmount then plays `usbOut`. `usbIn` and `usbOut` share one 30 s throttle.
  - Displays: more screens than before (`didChangeScreenParameters`), still more 2 s later and outside the quiet minute, play `newDisplay`.
- **Keyboard layout.** The sensor listens to the distributed `TISNotifySelectedKeyboardInputSourceChanged` notification. The selected input source's first language becomes a two-letter code (`InputSourceCode`).
  - A change of code (two English layouts do not count) sets `WorkProps.layout(from:to:)` (four letters, five bits each, from bit 20) and plays `layoutSwitch`, at most every 3 s.
  - `SpriteLibrary` passes only those bits to the `layoutSwitch` frames, and none to desk frames.
  - The badge draws any code with a 3×5 font: English blue, Russian red, other languages colored by their first letter.
- **Art.** `SpriteFactory+Activity.swift`. Keys, the gamepad, the bucket, the stick, the screen and the waving mitten stay out of the agent columns below row 8 (a test checks every figure). The tool bubble's bottom edge sits on row 8 on the left, as at the keyboard. Under Reduce Motion the ongoing states hold a frame, `appLaunched` and `appQuit` are skipped, and the USB, display and layout one-offs show a held cue.

## Calls

- **Reading.** `MeetingMonitor` (app target, only while `meetingAlerts` is on) asks for full calendar access the first time. Then it reads the next day of events from EventKit: again on `EKEventStoreChanged`, every 15 minutes, and at each phase boundary (wall-clock timer). All-day, cancelled and declined events are skipped. `MeetingLink` keeps only events with a call link in the URL, location or notes. Titles stay in memory only.
- **Deciding.** `MeetingPlan` (PetCore):
  - `soon`: from 5 minutes to 1 minute before a call;
  - `now`: from 1 minute before to 1 minute after;
  - `nextChange` says when to wake up;
  - `upcoming` is the next call within the hour, for the status card.
- **Showing.** `PetController` puts `meetingSoon` / `meetingNow` above working and resting. It stays below talking (the translation card), an agent that needs you, an error, the YubiKey, a file being caught and listening. At home, the last minute brings the pet out of the hole (not under do-not-disturb). The headset replaces a head accessory while it is on. A click on the pet in either state dismisses that call (`MeetingMonitor.dismissCurrent`, by start time; `MeetingPlan` skips dismissed calls) instead of opening the card.
- **Calendars macOS knows.** EventKit only sees calendars added to macOS. Apps with their own sync (Notion Calendar) need the account added in Internet Accounts too.

## Translation and selection

- **Reading the selection.** `SelectionReader` asks the focused element for `AXSelectedText`. If the app does not provide it, the reader sends ⌘C and then restores the clipboard exactly. Restored items carry the nspasteboard.org marker types, so clipboard managers ignore them.
- **Privacy rules.** These are pure and tested in `SelectionDecision`:
  - password fields are never read;
  - an empty selection never falls back to ⌘C, because IDEs then copy the whole line;
  - ⌘C is never sent to the pet itself;
  - ⌘C is never used when the clipboard holds something that cannot be restored exactly, such as promised files.
- **Direction.** `TranslationPlan` translates your language into the foreign one, and everything else into yours. Only the language part of BCP-47 codes is compared.
- **Engines.** Apple Translation runs offline through SwiftUI's `translationTask` (en↔ru in about 120–200 ms). Missing language packs are downloaded through the system sheet from the card. "Via Claude" streams a sonnet translation instead.

## Listening

- **Starting.**
  - `PetPanel` turns a press held still for 0.35 s (`holdDelay`) into `onHoldBegan`. Moving first makes it a drag. While held, the pet does not move. Releasing sends `onHoldEnded` instead of a click.
  - ⌃⌥L and the menu's "Listen" start a hands-free take, or finish the one in progress.
  - Nothing starts unless `PetConfig.listening` is on (off by default; the menu item is hidden and a hold stays a click). Turning it off stops a take in progress.
  - At home the pet does not listen.
- **Recognition.** `SpeechListener` (app target) taps `AVAudioEngine`'s input on the audio thread (`MicTap`, off the main actor). It converts each buffer to `SpeechAnalyzer.bestAvailableAudioFormat` and passes it to a `SpeechAnalyzer` running a `DictationTranscriber` with volatile results.
  - `SpeechTranscriber` has no Russian; the dictation model does, offline.
  - A missing language model is downloaded once through `AssetInventory`.
  - A result counts as final once its range ends before `resultsFinalizationTime`. `Transcript` joins final pieces and replaces the guess in progress.
  - The tap also reports the RMS level in dBFS.
- **Timing.** `ListenClock` (PetCore) calls it quiet after 1.5 s under -45 dBFS. Hands-free, a 4 s pause after sound ends the take, or 10 s with no sound at all. Any take ends after 2 minutes.
- **The pet.** `PetController.setListening` puts `.listening` (waves fly into the mic) or `.listenQuiet` (dots) above every rest except a key touch and a file being caught. Starting plays `.listenIn`. A take with text ends with `.listenOut` (a nod); a take without text ends with `.shakeHead`.
- **The card.** `Listener` drives `ListenView`: getting ready, downloading, the live text, then an editable field with Ask Claude (`Asker.ask`), Translate (`Translator.translate`) and Copy.
  - Each take has a number and its own `SpeechListener`. So a take closed while its mic is still starting cannot reach the next take.
  - `Listener.stop` (closing the card, another card opening, a drag) cancels the take and the mic.
  - Finishing waits up to 5 s for the last words, then uses the text so far.
  - Nothing is written to disk.
  - While the question card is open, the take runs without its own card. (A keyboard card would take the key window, and the question card closes when it loses it, which would stop an answer.) The text streams into `AskModel.draft` after anything already typed there. Closing the question card ends the take. The text goes out through `Asker.ask`, which leaves it in the field if an answer is still streaming.
  - A failure still shows the listen card, because the reason needs a place to show.

## Updates

Only the downloaded app updates (`UpdateCenter`, Sparkle 2). `bundle.sh` writes `SUFeedURL` and `SUPublicEDKey` into a release build's Info.plist. Without them, `UpdateCenter.isConfigured` is false: Sparkle never starts, and Settings and the menu show nothing about updates.

Sparkle's own windows are replaced. `UpdateCenter` is its `SPUUserDriver`. It turns each step into the update card (`UpdateModel.Phase`: checking, available, downloading, preparing, ready, up to date, failed, updated) and the box by the pet (`PetController.Parcel`).

- **A scheduled check** that finds a version sets the parcel to `.waiting`. While the pet rests idle, the box floats down on a balloon (`updateArrive`) and waits (`updateWait`), like the Monday newspaper.
  - A click on the box opens the card. The first click after it arrived also opens the card, even if the pet is busy (and no box is visible). After that, a busy pet's click does its usual action, and the menu's "Update to …" item at the top opens the card.
  - "Check for Updates…" opens the card at once, even with "Check for updates" off (the user asked, so it is not a background request). It shows nothing new while a background check is still running.
- **Every way the card closes** (its buttons, a click elsewhere, Esc, another card opening) goes through `CardPanel.onClose` to `UpdateCenter.cardClosed()`:
  - a check in progress is cancelled;
  - a result is acknowledged;
  - an offer stays as the box.

  Each of Sparkle's reply, cancel and acknowledgement closures is called once and then dropped. The card opens by the pet even while the pet is hidden, because Sparkle waits for its buttons. A version in the feed that is not a valid version (`AppVersion.isValid`) is dismissed, not shown.
- **The card** offers Update, Later (the box goes away; Sparkle asks again at the next check) and Skip this version, plus "update automatically from now on" (Sparkle's `automaticallyDownloadsUpdates`). While downloading and installing, it shows a pixel progress bar and the pet unpacking the box (`updateUnpack`). When ready, it offers Restart or On quit.
- **After the restart**, the config's `lastVersion` (the version that ran last) is older than the running one, however the update was installed (Restart, on quit, automatically). Right after `pet.start()`, the pet pops out of a big box (`updateDone`; if started earlier, the first resting state would replace it). Then the card says "Updated to …" and links to the release page. The first run with updates only records the version.
- **Settings.** "Check for updates" is Sparkle's `automaticallyChecksForUpdates` (off means no requests at all; `checkUpdates` in the config). "Install updates automatically" is its `automaticallyDownloadsUpdates`. Sparkle keeps its own state (last check, skipped version) in the app's defaults.

## Cards, menus and settings

- **Cards.** The status, translation and quick-question cards are borderless panels, not `NSPopover`: glass popovers tint with the wallpaper and lose contrast.
  - Placement (`CardPlacement`): above the pet when there is room, otherwise below, otherwise beside it on the side with more room. A card that grows is placed again, keeping its side while it fits, so it never covers the pet.
  - Only one card is open at a time.
  - A click in another app closes the card.
  - Cards opened from a hotkey appear without animation.
  - The quick-question card accepts typing without activating the app.
- **Edit menu.** A minimal one is installed, so that ⌘C/⌘V/⌘A/⌘Z and ⌘W work in text fields of an accessory app.
- **Hotkeys.** They are global and registered with Carbon `RegisterEventHotKey`, which needs no permissions.
- **Settings and onboarding.** Both are SwiftUI views over an `@Observable` `SettingsModel`. Launch at login uses `SMAppService.mainApp`, including the "requires approval" case.
- **Single instance.** A second copy of the app quits at launch, so two pets never compete for the socket.

## Configuration

`ConfigStore` reads and writes `~/.pixelpet/config.json` as pretty-printed JSON with sorted keys. Every field has a default; `scale` and `sleepAfterMinutes` are clamped on decode. An unreadable file is moved to `config.json.bak`, and defaults are used.

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
| `listening` | false | Listen to the mic (hold the pet, ⌃⌥L) |
| `speechLanguage` | empty | Language to recognize speech in; empty means `nativeLanguage` |
| `askModel` | `haiku` | Model for quick questions |
| `uiLanguage` | `en` | Interface language: `en` or `ru` |
| `macReactions` | true | React to headphones, music, mic/camera, heat, power, network, screenshots, theme |
| `activityReactions` | true | Notice Spaces, typing, the app in front, apps opening and quitting, USB sticks, displays, the keyboard layout |
| `skin` / `accessory` | `lavender` / `none` | Look |
| `figure` | `cube` | `cube`, `lidman` (LM) or `clip` (the paperclip); LM ignores `skin` and `accessory`, the paperclip only `accessory` |
| `watchCodex` | true | Follow Codex sessions and limits |
| `touchHint` | true | Show when a YubiKey waits for a touch |
| `checkUpdates` | true | Look for a new version once a day (downloaded app only) |
| `lastVersion` | none | The version that ran last (downloaded app), to greet a newer one |
| `notifications` | `whenHidden` | System notifications for agents: `off`, `whenHidden` or `always` |
| `touchNotification` | true | With `touchHint`, also a silent system notification while the key waits, whatever `notifications` says and under do-not-disturb |
| `approveFromPet` | true | Answer Claude Code's permission requests from a card by the pet |
| `weeklyRecap` | true | Keep day sums in `~/.pixelpet/stats.json` and bring the newspaper on Mondays |
| `breakMinutes` | 60 | Minutes of work before the break mug (`BreakClock.choices`: 0, 45, 60, 90); 0 is off |
| `recapShownFor` | — | The Monday ("yyyy-MM-dd") the newspaper last came out |
| `hookah` | true | Hookah breaks |
| `meetingAlerts` | false | Get ready for calls from the Mac's calendars |
| `lastCodexLimits` | — | Last known Codex limits |
| `logEvents` | false | Write `~/.pixelpet/events.log` (ids, project and event names only; rotates at 1 MB) |
| `lastLimits` | — | Last known limits |
| `onboarded` | false | Welcome window was seen |
