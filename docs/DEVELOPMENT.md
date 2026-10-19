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
docs/                architecture, this file, spec and spike notes (Russian), animation prototype
spikes/m0/           throwaway spike code from the first milestone (panel, layer renderer, translation)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the parts fit together.

## Build and run

| Command | What it does |
|---|---|
| `swift build` | Debug build of all targets |
| `./scripts/bundle.sh` | Release build, packaged as `build/PixelPet.app` with `Info.plist` (`LSUIElement`, bundle id `dev.pixelpet.PixelPet`) and signed. Set `CONFIG=debug` for a debug bundle |
| `./scripts/run.sh` | Quits a running copy, bundles, and opens `build/PixelPet.app` |
| `./scripts/install.sh` | Bundles first (a failed build leaves the running pet alone), then replaces `~/Applications/PixelPet.app` and launches it. Use this for the copy you live with: login items work best from `~/Applications` |

Only one instance runs at a time: a second launch quits immediately. So `run.sh` and `install.sh` stop the running copy first.

The `CFBundleVersion` comes from `git describe --tags --always --dirty`. `CFBundleShortVersionString` is fixed at `0.1.0` in `bundle.sh`.

## Tests

```bash
./scripts/test.sh
```

The tests use Swift Testing. There are about 260 tests in three targets, covering `PetCore`, `PetSprites` and `PetIntegrations`. The app target has no tests: it is kept thin on purpose.

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

## Debugging

### Launch flags

Pass flags with `open build/PixelPet.app --args <flags>`, or run the binary inside the bundle directly.

Quit the running pet first (menu: "Выйти", or `pkill -x PixelPet`). The app is single-instance: a second copy quits at launch, and `open` on an already running app only activates it, ignoring the flags. The one exception is `--export-sprites`, which is handled before the instance check.

| Flag | Effect |
|---|---|
| `--export-sprites <dir> [skin] [accessory]` | Writes PNG strips of every state in the given look, then quits. Skins: `lavender`, `mint`, `peach`, `mono`. Accessories: `none`, `glasses`, `headphones`, `cap` |
| `--show-panel` | Opens the status panel 12 s after launch, once the limits have had time to load |
| `--translate-text "<text>"` | Translates the text 1 s after launch |
| `--with-claude` | Used with `--translate-text`: also runs "via Claude" |
| `--ask "<question>"` | Asks a quick question 1 s after launch |
| `--ask-followup "<question>"` | Used with `--ask`: sends a follow-up once the first answer is done |
| `--keep-cards` | Clicks elsewhere do not close the cards (for scripted checks with screenshots) |
| `--show-settings` | Opens the settings window at launch |

Exporting sprites runs without a window, so it works alongside the running pet:

```bash
build/PixelPet.app/Contents/MacOS/PixelPet --export-sprites /tmp/sprites mint headphones
```

### Other aids

- **State picker.** The menu item "Состояние" (State) plays any state, so you can check an animation without staging it. Mood states follow the same home and do-not-disturb rules as real agent activity.
- **Event log.** Turn on "Записывать события" (Record events) in the menu or settings. Then watch the log while an agent runs:

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

Notarization and distribution are out of scope. The app is meant to be built from source on your own Mac.

## Conventions

- **Branches.** Each piece of work gets a branch such as `feat/<topic>` or `fix/<topic>`, which is fast-forward merged into `main` once checked.
- **Commits.** Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`).
- **Comments.** Comments explain *why*: constraints, platform quirks, measured numbers. Doc comments (`///`) go on types and non-obvious members.
- **Main actor.** UI code is `@MainActor`. `EventServer` runs on its own serial queue and hands payloads to the main actor through one ordered `AsyncStream`.
- **Performance budget.** Aim for under 1% CPU while idle and under 3% while animating, under 60 MB of RAM, and under 20 ms per hook call. Do not add fast polling: schedule a timer for the next known change instead. The only repeating timer is the slow 20 s idle check in `DesktopSensor`.
- **Privacy.** Never store prompt text, tool input or window titles. New uses of the selection or the clipboard go through `SelectionDecision`.
- **Strings.** The UI is in Russian. Keep new UI strings consistent with the existing wording.

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
