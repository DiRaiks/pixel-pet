# Pixel Pet

A small pixel-art cube that lives on your macOS desktop, or in the MacBook notch. It keeps an eye on your Claude Code agents and shows how much of your subscription limit is left. It can answer a quick question and translate selected text.

- **Agents at a glance.** Each running Claude Code session appears as a small block next to the cube. The block is teal while the session works, amber while it waits for you, and red if it fails. The cube itself reacts too: it types on a keyboard while agents work, bounces with a "!" when one needs input, and jumps (or does a somersault after a long task) when a turn finishes.
- **Limits.** The 5-hour and weekly usage show in the status panel and the menu bar. As the 5-hour window drains, the cube fades from the top down.
- **Quick question (⌃⌥K).** Ask Claude in a card next to the cube. The answer streams in, and follow-ups continue the same conversation.
- **Translate the selection (⌃⌥T).** Apple Translation works offline and is instant. A "via Claude" button sends the text to Claude instead.
- **Home in the notch.** Drop the cube near the top of the screen and it slips into the notch, or into a small "burrow" on displays without one. From there it peeks out when something needs you.
- **Desktop life.** Its eyes follow the cursor. It dozes off when you are away, yawns and rolls now and then, gets shy when you hover over it, and gets cross if you click it too much.

The app runs entirely on your Mac. It never talks to the network itself; the only network access is through the Claude Code CLI you already use.

> The app's UI is in Russian. Where this document names a menu item, the English meaning comes first, followed by the Russian label in quotes.

## Requirements

- macOS 26 or later, on Apple silicon or Intel.
- Swift 6.2 or later. The Command Line Tools are enough; Xcode is not required.
- [Claude Code](https://docs.claude.com/en/docs/claude-code), either as the `claude` CLI on your `PATH` or bundled with the Claude desktop app. Questions, Claude translation and limit checks use your Claude subscription.

## Install

```bash
git clone <this repo> pixel-pet
```

```bash
cd pixel-pet && ./scripts/install.sh
```

`install.sh` builds a release app bundle, copies it to `~/Applications/PixelPet.app` and launches it. Running it again updates the app in place. A failed build leaves the running copy alone.

On first launch, a welcome window walks you through two steps and lists the hotkeys:

1. **Connect to Claude Code** (menu: "Подключить к Claude Code…"). This adds the pet's hooks to `~/.claude/settings.json`; the file is backed up first. See [What it changes on your Mac](#what-it-changes-on-your-mac).
2. **Allow Accessibility.** This is needed only for ⌃⌥T, to read the selected text.

The first time a translation language pack is missing, the translation card offers a button to download it.

Agent sessions that are already open get picked up as soon as they send their next event. You do not need to restart them.

## Using it

### Mouse

| Action | What happens |
|---|---|
| Click the cube | It hops and opens the status panel (sessions, limits, model, context) |
| Right-click | The context menu, which matches the menu-bar menu |
| Drag | Moves the cube. A quick flick throws it across the screen |
| Drop near the top center of a screen | It dives home into the notch or burrow |
| Drag it down from home | It comes back out onto the desk |
| Hover over it for 2 s | It gets shy, at most once a minute. This happens only while it is idle on the desk with desktop reactions on and no card open |
| Click it 5 times in 3 s | It gets cross |

### Hotkeys

| Keys | Action |
|---|---|
| ⌃⌥K | Ask Claude a quick question. Esc closes the card |
| ⌃⌥T | Translate the selected text |
| ⌃⌥P | Do not disturb: the cube goes home and only comes out for errors |

### Menu bar

The menu-bar icon is a tiny cube with the number of active agents next to it. Its menu has:

- the current limits;
- the status panel;
- ask, translate and do not disturb;
- send home or let out on the desk;
- show or hide the cube;
- size (×2 to ×6);
- a state picker for previewing animations;
- connect or disconnect Claude Code, and add a statusline for the terminal;
- the event log;
- settings and the welcome window;
- quit.

### What the cube is telling you

States are listed in priority order; a higher one wins.

| State | Meaning |
|---|---|
| Error (shakes, then dizzy) | An agent's turn failed within the last 3 seconds |
| Alert (bounces with "!") | An agent is waiting for you: a permission prompt, a question, or a plan to approve |
| Low limit (pale, sweating) | 5-hour usage is at 85% or more, or weekly usage at 90% or more |
| Working (typing) | At least one agent is working |
| Idle (breathing, blinking, looking around) | Nothing is going on |
| Sleep (nightcap, Z bubble) | Idle, and you have been away longer than the sleep setting |

On top of these, the cube plays one-off animations:

- a jump when a turn with at least 20 s of work finishes;
- a somersault with confetti after a turn of 10 minutes or more;
- a hop when you click it or come back;
- a landing when you drop it;
- occasional idle fidgets: a yawn, or a roll.

At home only the eyes show. The cube peeks out for alerts and errors, and briefly for one-off events.

Agent blocks stack beside the cube, one per session:

| Block | Meaning |
|---|---|
| Teal, spinning | Working |
| Amber, bouncing | Waiting for you |
| Red | Failed |
| Grey | Idle |
| Green flash | Just finished |
| Dot on a block | Subagents are running |
| Ellipsis on top | More than 4 sessions |

### Settings

Open settings from the menu (menu: "Настройки…", ⌘,):

| Setting | Notes |
|---|---|
| Size | ×2 to ×6 |
| Color | Lavender, mint, peach or graphite |
| Accessory | None, glasses, headphones or a cap |
| Do not disturb | Same as ⌃⌥P |
| Desktop reactions | Eyes follow the cursor, glances at the app you switch to, the cube fades over fullscreen apps, fidgets |
| Fall asleep after | Never, or 5, 10, 15, 30 or 60 minutes without input |
| Launch at login | Uses a macOS login item |
| Claude Code hooks and statusline | Connect or disconnect them |
| Model for questions | haiku, sonnet or opus |
| Event log | Writes to `~/.pixelpet/events.log` |
| Translation | Your language and the language to translate it into. Text in any other language is translated into yours |
| Accessibility | Shows the permission status, with a button to request it |

With **Reduce Motion** turned on in macOS (Accessibility → Display), the cube stops jumping, throwing and shaking. Cards open without animation. Looping alarm states hold a single expressive frame instead of animating.

## What it changes on your Mac

| Path | What |
|---|---|
| `~/.pixelpet/config.json` | Settings, position and the last known limits |
| `~/.pixelpet/pet.sock` | Unix socket the hooks talk to. It is readable only by you |
| `~/.pixelpet/bin/pixelpet-hook` | Hook script: `sh` and `nc` forward the hook JSON to the socket. It always exits 0 and never blocks Claude |
| `~/.pixelpet/bin/pixelpet-statusline` | Optional statusline for terminal sessions. It prints `Model · ctx N% · 5h N% · 7d N%` |
| `~/.pixelpet/events.log` | Only written when the event log is on. It rotates at 1 MB and keeps one old file, `events.log.1` |
| `~/.claude/settings.json` | One hook entry for each of 12 events, plus a `statusLine` entry only if you had none. A timestamped backup `settings.json.pixelpet-backup-<ms>` is written before every change. Other hooks are never touched |
| `~/.claude/projects/*-pixelpet-claude` | Quick-question sessions. Deleted when you start a new conversation, on quit and on launch |
| `$TMPDIR/pixelpet-claude` | Empty working folder for the pet's own `claude -p` runs |

Disconnecting (menu: "Отключить от Claude Code") removes the pet's hook entries, its statusline and both scripts.

**Privacy.** Hook payloads are reduced to event names, session ids, the project folder name, the tool name and the model as soon as they arrive. Prompt text and tool input are never stored. Selected text is read only when you press ⌃⌥T. Password fields are never read. The clipboard fallback restores your clipboard exactly, or is skipped if it cannot.

## Uninstall

1. Disconnect Claude Code from the menu.
2. If it is on, turn off "Launch at login" in Settings, so no stale entry is left under Login Items.
3. Quit the app.
4. Remove the app and its data:

```bash
rm -rf ~/Applications/PixelPet.app ~/.pixelpet
```

Two things stay behind until you remove them yourself:

- the settings backups, `~/.claude/settings.json.pixelpet-backup-*`;
- the app's entry in System Settings → Privacy & Security → Accessibility.

## Troubleshooting

- **⌃⌥T stopped reading the selection after an update.** The app is signed ad-hoc, so macOS treats every build as a new app. In System Settings → Privacy & Security → Accessibility, remove Pixel Pet with the "−" button and allow it again. A stable signing certificate fixes this for good; see [DEVELOPMENT.md](docs/DEVELOPMENT.md#code-signing).
- **No agent blocks appear.** Check that the menu says "Отключить от Claude Code", which means hooks are connected. Then turn on the event log and watch `~/.pixelpet/events.log` while an agent runs.
- **Limits show "unknown".** The app finds limits by running a tiny `claude -p` request. Check that Claude Code is installed and signed in.
- **A hotkey does nothing.** Hotkeys are global. If another app already owns the combination, Pixel Pet cannot register it; it only writes `hotkey N not registered` to the unified log.
- **Translation says the language is not installed.** Use the download button in the card. Alternatively, open System Settings → General → Language & Region → Translation Languages.

## Documentation

- [Architecture](docs/ARCHITECTURE.md): modules, data flow and the rules behind the states.
- [Development](docs/DEVELOPMENT.md): building, testing, debug flags and conventions.
- [Changelog](CHANGELOG.md).
- Background notes in Russian: the original [spec and plan](docs/SPEC.md), the [spike findings](docs/spike-notes.md), and the [animation prototype](docs/prototype/sprites.html), which opens in a browser.
