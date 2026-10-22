# Development

## Toolchain

- **macOS 26 or later.** The package targets `.macOS(.v26)`, which requires `swift-tools-version:6.2`.
- **Swift 6.2 or later**, in Swift 6 language mode with strict concurrency. The project is developed with Swift 6.4 from the Command Line Tools. **Xcode is not needed.** Two consequences of building without it:
  - The SwiftUI `@State` macro plugin is not available, so view state lives in `@Observable` models.
  - The Swift Testing macro plugin is flaky with the CLT; see [Tests](#tests).
- **Claude Code**, only for the features that call the CLI. Tests never run it.

## Layout

```
Package.swift
Sources/
  PetCore/           pure logic, fully unit-tested
  PetSprites/        procedural pixel art
  PetIntegrations/   socket server, Claude CLI runs
  PixelPet/          the app (AppKit + SwiftUI)
Tests/
  PetCoreTests/ PetSpritesTests/ PetIntegrationsTests/
scripts/             bundle, run, install, test
docs/                architecture, this file, README pictures, animation prototype
spikes/m0/           throwaway spike code from the first milestone (panel, layer renderer, translation)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the parts fit together.

## Build and run

| Command | What it does |
|---|---|
| `swift build` | Debug build of all targets |
| `./scripts/bundle.sh` | Release build, packaged as `build/PixelPet.app` with `Info.plist` (`LSUIElement`, bundle id `dev.pixelpet.PixelPet`) and the icon `Resources/AppIcon.icns` (drawn from the idle sprite by `scripts/make-icon.swift`), and signed. Set `CONFIG=debug` for a debug bundle |
| `./scripts/run.sh` | Quits a running copy, bundles, and opens `build/PixelPet.app` |
| `./scripts/install.sh` | Bundles first (a failed build leaves the running pet alone), then replaces `~/Applications/PixelPet.app` and launches it. Use this for the copy you live with: login items work best from `~/Applications` |

Only one instance runs at a time: a second launch quits immediately. So `run.sh` and `install.sh` stop the running copy first.

The `CFBundleVersion` comes from `git describe --tags --always --dirty`. `CFBundleShortVersionString` is fixed at `0.1.0` in `bundle.sh`.

## Tests

```bash
./scripts/test.sh
```

The tests use Swift Testing. There are about 440 tests in three targets, covering `PetCore`, `PetSprites` and `PetIntegrations`. The app target has no tests: it is kept thin on purpose.

Always run tests through `scripts/test.sh` rather than plain `swift test`. With only the Command Line Tools installed, `swift test` often fails to load the Swift Testing macro plugin (`TestingMacros`) when it reuses the build description that a plain `swift build` left in `.build`. The script works around it:

1. It deletes `.build/manifest.pif` and runs the tests.
2. If the plugin is still missing, it wipes `.build` and retries, up to twice.
3. It does not retry when the log also contains real compile errors.

Arguments are passed through:

```bash
./scripts/test.sh --filter SessionRegistryTests
```

What gets covered:

- **New logic goes in `PetCore` with tests first.** This includes priorities, timeouts, geometry, privacy rules and settings merging. Bug fixes come with a regression test.
- **Sprites are tested by their pixels.** Tests check that frame counts match `PetState`, that frames are not empty and are deterministic, and that key pixels and geometry are right. Examples are "nothing drawn above the body while dragged" and "the face stays upright while rotating".
- **Integrations are tested with real processes.** The hook and statusline scripts run under `sh` against a real socket. `EventServer` is exercised over a real unix socket. The CLI argument builders and stream parsing are tested without running `claude`.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every push to `main` and on pull requests:

| Job | Runner | What it checks |
|---|---|---|
| Build and test | `macos-26` (Apple Silicon, Xcode 26) | `swift build`, then `scripts/test.sh` |
| Release bundle | `macos-26` | `scripts/bundle.sh` (signed ad-hoc there), then the Info.plist and the signature |
| ShellCheck | `ubuntu-latest` | `scripts/*.sh` |

A version tag runs `.github/workflows/release.yml`; see [Releases](#releases).

Dependabot (`.github/dependabot.yml`) keeps the workflow's actions up to date once a month. Runners are free for this public repository.

## Debugging

### Launch flags

Pass flags with `open build/PixelPet.app --args <flags>`, or run the binary inside the bundle directly.

Quit the running pet first (menu: "Quit", or `pkill -x PixelPet`). The app is single-instance: a second copy quits at launch, and `open` on an already running app only activates it, ignoring the flags. The one exception is `--export-sprites`, which is handled before the instance check.

| Flag | Effect |
|---|---|
| `--export-sprites <dir> [skin] [accessory]` | Writes PNG strips of every state in the given look, then quits. Skins: any of `Skin.all` by name, or `lidman` for LM. Accessories: any `Accessory` raw value, such as `none`, `glasses`, `headphones`, `cap` |
| `--export-readme <dir>` | Writes the README pictures (animated PNGs of the states, the looks lineup and the showreel), then quits |
| `--export-work <dir>` | Writes previews of the keyboard moments (each between stretches of typing, with agent blocks), the desk props and the YubiKey touch, then quits |
| `--show-panel` | Opens the status panel 12 s after launch, once the limits have had time to load |
| `--show-recap` | Opens the weekly recap card 12 s after launch |
| `--appearance light\|dark` | The pet's cards in light or dark, whatever the system uses (for screenshots) |
| `--drop-file <path>` | Drops that file on the pet 1 s after launch, as if dragged there; with `--ask`, the question follows 2 s later |
| `--ask-delay <seconds>` | With `--ask`: send the question this long after launch instead |
| `--translate-text "<text>"` | Translates the text 1 s after launch |
| `--with-claude` | Used with `--translate-text`: also runs "via Claude" |
| `--translate-again "<text>"` | Used with `--translate-text`: translates a second text 5 s later, in the same languages |
| `--ask "<question>"` | Asks a quick question 1 s after launch |
| `--ask-followup "<question>"` | Used with `--ask`: sends a follow-up once the first answer is done |
| `--keep-cards` | Clicks elsewhere do not close the cards (for scripted checks with screenshots) |
| `--show-settings` | Opens the settings window at launch |

Exporting sprites runs without a window, so it works alongside the running pet:

```bash
build/PixelPet.app/Contents/MacOS/PixelPet --export-sprites /tmp/sprites mint headphones
```

### README pictures

The animations in the README are drawn by the app's own sprite code, so regenerate them after changing the art:

```bash
swift build && .build/debug/PixelPet --export-readme docs/images
```

They are animated PNGs on a light rounded tile: APNG keeps the soft shadow's alpha, and GitHub plays them. The card screenshots are taken by hand, in light mode and English: quit the pet, launch it with `--appearance light --keep-cards` and one of the flags below, and capture the card window with `screencapture -o -l <window id>`.

| Image | How |
|---|---|
| `ask-card.png` | `--drop-file <a source file> --ask "<question>"` (add `--ask-delay` if the first `claude -p` after launch is slow) |
| `translate-card.png` | `--translate-text "<text>"` |
| `status-card.png` | `--show-panel`, with a few demo sessions sent through `~/.pixelpet/bin/pixelpet-hook` (prompt, tool starts and finishes, a `permission_prompt` notification) |
| `permission-card.png` | A `PermissionRequest` sent through the hook script with a command, a description and a `permission_suggestions` rule |
| `recap-card.png` | `--show-recap`, with demo day sums in `~/.pixelpet/stats.json` (keep a copy of the real file and put it back) |

### Other aids

- **State picker.** The menu item "State" plays any state, so you can check an animation without staging it. Mood states follow the same home and do-not-disturb rules as real agent activity.
- **Event log.** Turn on "Log events" in the menu or settings. Then watch the log while an agent runs:

  ```bash
  tail -f ~/.pixelpet/events.log
  ```

  Lines contain only session-id prefixes, project names and event names.
- **Hook script by hand.** Send a payload to the socket yourself:

  ```bash
  echo '{"hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"test","cwd":"/tmp/demo"}' | ~/.pixelpet/bin/pixelpet-hook
  ```

- **Animation prototype.** [`prototype/sprites.html`](prototype/sprites.html) is the original browser prototype. Open it locally to compare motion ideas quickly.
- **Logs.** Errors go to the unified log under the `PixelPet:` prefix:

  ```bash
  log stream --predicate 'process == "PixelPet"'
  ```

## Code signing

`bundle.sh` signs with the identity **"Pixel Pet Dev"** when the keychain has it, and ad-hoc otherwise.

With ad-hoc signing, macOS treats every rebuild as a new app. As a result, the Accessibility permission (needed for ⌃⌥T) silently stops working after each build. The toggle in System Settings still shows "on". The fix is to remove the app with "−" and allow it again.

A self-signed code-signing certificate gives every build a stable identity. To create one (this changes your keychain, so do it yourself):

1. Open Keychain Access, then Keychain Access → Certificate Assistant → Create a Certificate…
2. Set the name to `Pixel Pet Dev`, the identity type to *Self-Signed Root*, and the certificate type to *Code Signing*.
3. Rebuild with `./scripts/install.sh`, then grant Accessibility one last time.

## Releases

`scripts/release.sh <version>` builds `build/PixelPet-<version>.dmg`: the app (with `SHORT_VERSION` from the version, numbers only) and a link to Applications. What else happens depends on what's available, so the same script is a dry run anywhere:

| Set | Result |
|---|---|
| nothing | App signed ad-hoc, DMG unsigned (a dry run; Gatekeeper blocks it on other Macs) |
| `SIGN_IDENTITY="Developer ID Application: …"` | App signed with hardened runtime, `scripts/PixelPet.entitlements` and a secure timestamp; DMG signed |
| plus `NOTARY_PROFILE` (from `xcrun notarytool store-credentials`), or `NOTARY_KEY` + `NOTARY_KEY_ID` + `NOTARY_ISSUER` (an App Store Connect API key) | DMG notarized, stapled and checked with `spctl` |

Pushing a tag such as `v0.2.0` (or `v0.3.0-beta.1`, published as a prerelease) runs the Release workflow on `macos-26`: it imports the certificate into a temporary keychain, runs `release.sh` and publishes a GitHub release with the DMG and generated notes. Each secret is passed only to the step that needs it (the certificate to the keychain import, the notary key to its own step), and the actions are pinned to commits (Dependabot keeps the pins current). It reads these repository secrets, set in Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12` | The Developer ID Application certificate with its private key, exported as .p12, base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_P12_PASSWORD` | The .p12 export password |
| `APPLE_API_KEY` | An App Store Connect API key (.p8, "Developer" role), base64-encoded |
| `APPLE_API_KEY_ID` / `APPLE_API_ISSUER_ID` | Its key id and issuer id |

Without the certificate secrets the workflow still runs, as a dry run published as a draft prerelease. The entitlements file grants only calendar access, which the hardened runtime needs for call reminders; reading the selection (Accessibility) needs no entitlement.

## Known gaps and ideas

- **Stable code signing.** Builds are signed ad-hoc until a "Pixel Pet Dev" certificate exists (see [Code signing](#code-signing)), so the Accessibility permission has to be granted again after each rebuild.
- **Aseprite sprites.** Frames are drawn in code (`SpriteFactory`); swapping in an Aseprite sprite sheet would only change what produces the canvases.
- **FIDO2 touches.** The YubiKey hint covers GPG only; `sk-` SSH keys and passkeys show up as kernel HID messages in the system log instead.
- **Subagent animation.** Revisit how the pet shows subagents being created (`spawn` / `recall`).
- **A ball to play with.** Started from the context menu ("Play"), not a double-click, which would delay every single click that opens the status panel. A small ball on the floor where the pet stands: it bounces, the pet chases and kicks it a few times, the user can flick it with the mouse (the throw physics already exist), and it rolls away after about 30 s. Stays near the pet rather than crossing the screen; no score.
- **Codex waiting for approval.** Codex doesn't write approval prompts to its session files, so its blocks never turn amber; its hooks (`PermissionRequest`) could fill that in, if the desktop app runs them.

## Findings worth knowing

Measured or found out while building; they explain choices that look odd otherwise.

- **Rendering cost.** SpriteKit idled at 2–8% CPU and about 125 MB (it keeps ticking even when paused); swapping `CGImage`s in a `CALayer` costs 0.1–0.2% and about 12 MB.
- **Hook latency.** `sh` + `nc -U` to the socket takes about 10 ms per call (12 ms worst); `python3` alone takes about 20 ms to start, so the hook is a shell script.
- **Socket path.** Unix socket paths are limited to about 104 bytes, which is why the socket lives at `~/.pixelpet/pet.sock` and not in a temporary folder.
- **Hooks and desktop sessions.** Hooks fire for Claude desktop (Code tab) sessions too, and already open sessions start sending events as soon as `settings.json` changes, without a `SessionStart`. The statusline, on the other hand, never runs for desktop sessions: that is why limits come from `rate_limit_event` instead.
- **`claude -p`.** `--bare` needs an API key and ignores the subscription, so it can't be used; `--setting-sources project` keeps user hooks out instead. With haiku the first token arrives after about 2.7 s, and `result` follows `message_stop` by about 1.4 s (the post-turn summary), which is why answers count as done at `message_stop`.
- **Post-turn summary.** After each turn Claude Code runs a short internal subagent whose `SubagentStop` arrives without a `SubagentStart`; it is not one of the user's subagents.

## Conventions

- **Branches.** Each piece of work gets a branch such as `feat/<topic>` or `fix/<topic>`, which is fast-forward merged into `main` once checked.
- **Commits.** Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`).
- **Comments.** Comments explain *why*: constraints, platform quirks, measured numbers. Doc comments (`///`) go on types and non-obvious members.
- **Main actor.** UI code is `@MainActor`. `EventServer` runs on its own serial queue and hands payloads to the main actor through one ordered `AsyncStream`.
- **Performance budget.** Aim for under 1% CPU while idle and under 3% while animating, under 60 MB of RAM, and under 20 ms per hook call. Do not add fast polling: schedule a timer for the next known change instead. The only repeating timer is the slow 20 s idle check in `DesktopSensor`.
- **Privacy.** Never store prompt text, tool input or window titles. New uses of the selection or the clipboard go through `SelectionDecision`.
- **Strings.** The UI is English by default with Russian as an option (Settings → Language). Write every UI string as `L("English", "Русский")` (`Sources/PixelPet/Localization.swift`); tables of titles are computed (`static var`) so they follow a language change. SwiftUI views redraw on their own; the menu bar menu retitles itself each time it opens.

### Adding a pet state

1. Add the case to `PetState` (`Sources/PetCore/PetState.swift`), with its per-frame durations in `PetState.millis`. If it plays once, add it to the one-shots in `loops`.
2. Decide its Reduce Motion behavior in `MotionPolicy`: a still frame, skip, or a held cue.
3. Draw it in `SpriteFactory.draw`. Use `BodyStyle` for the body, so skins, accessories and blush come for free.
4. Give it a title in `StatusMenu.stateTitles`.
5. Trigger it from `PetController` or `AgentMonitor`.
6. Add tests. `SpriteFactoryTests.producesOneCanvasPerFrame` already covers every case. Add a test for whatever makes the new state distinctive.
7. Check the result with `--export-sprites` and the State menu.

### Changing what the hooks send

1. Add the event name to `HookSettings.events`. Existing installs pick it up the next time the user reconnects.
2. Map it in `AgentEvent.parse`.
3. Handle it in `SessionRegistry.apply`, with tests. Keep only the metadata you need.
