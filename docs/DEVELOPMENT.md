# Development

## Toolchain

- **macOS 26 or later.** The package targets `.macOS(.v26)`. This requires `swift-tools-version:6.2`.
- **Swift 6.2 or later**, in Swift 6 language mode with strict concurrency. The project is developed with Swift 6.4 from the Command Line Tools. **Xcode is not needed.** Building without Xcode has two effects:
  - The SwiftUI `@State` macro plugin is not available. View state lives in `@Observable` models instead.
  - The Swift Testing macro plugin does not always load with the Command Line Tools. See [Tests](#tests).
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
Resources/           app icon, DMG background picture
scripts/             bundle, run, install, test, release, appcast, update test
docs/                architecture, this file, README pictures, animation prototype
spikes/m0/           throwaway spike code from the first milestone (panel, layer renderer, translation)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the parts fit together.

## Build and run

| Command | What it does |
|---|---|
| `swift build` | Debug build of all targets |
| `./scripts/bundle.sh` | Release build, packaged and signed as `build/PixelPet.app`. Adds `Info.plist` (`LSUIElement`, bundle id `dev.pixelpet.PixelPet`), the icon `Resources/AppIcon.icns` and `Sparkle.framework`. Set `CONFIG=debug` for a debug bundle |
| `./scripts/run.sh` | Quits a running copy, bundles, and opens `build/PixelPet.app` |
| `./scripts/install.sh` | Bundles first, then replaces `~/Applications/PixelPet.app` and launches it. If the build fails, the running pet stays. Use this for your everyday copy: login items work best from `~/Applications` |

`scripts/make-icon.swift` draws the icon from the idle sprite.

Only one instance runs at a time. A second launch quits at once. This is why `run.sh` and `install.sh` stop the running copy first.

Versions in `Info.plist`:

- `CFBundleShortVersionString` is `$SHORT_VERSION`, default `0.1.0`.
- `CFBundleVersion` is `$BUNDLE_VERSION`, default `git describe --tags --always --dirty`.
- `release.sh` sets both to the release version.

## Tests

```bash
./scripts/test.sh
```

The tests use Swift Testing. There are about 600 tests in three targets: `PetCore`, `PetSprites` and `PetIntegrations`. The app target has no tests. It is kept thin on purpose.

Always run tests with `scripts/test.sh`, not plain `swift test`. With only the Command Line Tools, `swift test` often fails to load the Swift Testing macro plugin (`TestingMacros`). This happens when it reuses the build description that a plain `swift build` left in `.build`. The script works around it:

1. It deletes `.build/manifest.pif` and runs the tests.
2. If the plugin is still missing, it deletes `.build` and tries again, up to two times.
3. It does not try again when the log also has real compile errors.

Arguments go through to `swift test`:

```bash
./scripts/test.sh --filter SessionRegistryTests
```

What the tests cover:

- **New logic goes in `PetCore`, with tests first.** This includes priorities, timeouts, geometry, privacy rules and settings merging. Every bug fix comes with a regression test.
- **Sprites are tested by their pixels.** Tests check that frame counts match `PetState`, that frames are not empty and are deterministic, and that key pixels and geometry are right. Examples: "nothing drawn above the body while dragged" and "the face stays upright while rotating".
- **Integrations are tested with real processes.** The hook and statusline scripts run under `sh` against a real socket. `EventServer` is tested over a real unix socket. The CLI argument builders and the stream parsing are tested without running `claude`.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every push to `main` and on every pull request. It can also be started by hand.

| Job | Runner | What it checks |
|---|---|---|
| Build and test | `macos-26` (Apple Silicon, Xcode 26) | `swift build`, then `scripts/test.sh` |
| Release bundle | `macos-26` | `scripts/release.sh 0.0.0-ci` as a dry run (app signed ad-hoc, DMG unsigned). Then it checks the Info.plist, the app signature, the binary and the DMG |
| ShellCheck | `ubuntu-latest` | `scripts/*.sh` |

A version tag runs `.github/workflows/release.yml`. See [Releases](#releases).

Dependabot (`.github/dependabot.yml`) updates the workflow actions once a month. Runners are free for this public repository.

## Debugging

### Launch flags

Pass flags with `open build/PixelPet.app --args <flags>`, or run the binary inside the bundle directly.

Quit the running pet first (menu: "Quit", or `pkill -x PixelPet`). The app runs only one instance. A second copy quits at launch. `open` on an app that is already running only brings it to the front and ignores the flags. The `--export-…` flags are the exception: the app handles them before the instance check.

| Flag | Effect |
|---|---|
| `--export-sprites <dir> [skin] [accessory]` | Writes PNG strips of every state in the given look, then quits. Skins: any of `Skin.all` by name, `lidman` for LM, or `clip` for the paperclip (`clip:mint` for another color). Accessories: any `Accessory` raw value, such as `none`, `glasses`, `headphones`, `cap` |
| `--export-readme <dir>` | Writes the README pictures (animated PNGs of the states, the looks lineup and the showreel), then quits |
| `--export-dmg-background <dir>` | Writes the picture for the release DMG window (`background.png` and `background@2x.png`), then quits |
| `--export-work <dir>` | Writes previews of the keyboard moments (each between periods of typing, with agent blocks), the desk props and the YubiKey touch, then quits |
| `--show-panel` | Opens the status panel 12 s after launch, when the limits have loaded |
| `--show-recap` | Opens the weekly recap card 12 s after launch |
| `--appearance light\|dark` | Shows the pet's cards in light or dark mode, whatever the system uses (for screenshots) |
| `--drop-file <path>` | Drops that file on the pet 1 s after launch, as if dragged there. With `--ask`, the question follows 2 s later |
| `--ask-delay <seconds>` | With `--ask`: sends the question this long after launch instead |
| `--translate-text "<text>"` | Translates the text 1 s after launch |
| `--with-claude` | With `--translate-text`: also translates "via Claude" |
| `--translate-again "<text>"` | With `--translate-text`: translates a second text 5 s later, in the same languages |
| `--ask "<question>"` | Asks a quick question 1 s after launch |
| `--ask-followup "<question>"` | With `--ask`: sends a follow-up when the first answer is done |
| `--keep-cards` | Clicks elsewhere do not close the cards (for scripted checks with screenshots) |
| `--show-settings` | Opens the settings window at launch |
| `--update-check-now` | Runs the daily update check 4 s after launch. Only works in a build that has an update feed (see [Updates](#updates-sparkle)) |

Sprite export runs without a window, so it works while the pet is running:

```bash
build/PixelPet.app/Contents/MacOS/PixelPet --export-sprites /tmp/sprites mint headphones
```

### README pictures

The app's own sprite code draws the README animations. Regenerate them after you change the art:

```bash
swift build && .build/debug/PixelPet --export-readme docs/images
```

They are animated PNGs (APNG) on a light rounded tile. APNG keeps the alpha of the soft shadow, and GitHub plays them.

The card screenshots are made by hand, in light mode and in English:

1. Quit the pet.
2. Launch it with `--appearance light --keep-cards` and one of the flags below.
3. Capture the card window with `screencapture -o -l <window id>`.

| Image | How |
|---|---|
| `ask-card.png` | `--drop-file <a source file> --ask "<question>"` (add `--ask-delay` if the first `claude -p` after launch is slow) |
| `translate-card.png` | `--translate-text "<text>"` |
| `status-card.png` | `--show-panel`, with a few demo sessions sent through `~/.pixelpet/bin/pixelpet-hook` (prompt, tool starts and finishes, a `permission_prompt` notification) |
| `permission-card.png` | A `PermissionRequest` sent through the hook script with a command, a description and a `permission_suggestions` rule |
| `recap-card.png` | `--show-recap`, with demo day sums in `~/.pixelpet/stats.json` (save a copy of the real file and put it back after) |

### Other aids

- **State picker.** The menu item "State" plays any state. Use it to check an animation without setting up the real situation. Mood states follow the same home and do-not-disturb rules as real agent activity.
- **Event log.** Turn on "Log events" in the menu or in settings. Then watch the log while an agent runs:

  ```bash
  tail -f ~/.pixelpet/events.log
  ```

  Lines contain only session-id prefixes, project names and event names.
- **Hook script by hand.** Send a payload to the socket yourself:

  ```bash
  echo '{"hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"test","cwd":"/tmp/demo"}' | ~/.pixelpet/bin/pixelpet-hook
  ```

- **Animation prototype.** [`prototype/sprites.html`](prototype/sprites.html) is the original browser prototype. Open it locally to compare motion ideas quickly.
- **Logs.** Errors go to the unified log with the `PixelPet:` prefix:

  ```bash
  log stream --predicate 'process == "PixelPet"'
  ```

## Code signing

`bundle.sh` chooses the signing identity in this order:

1. `$SIGN_IDENTITY`, when set (a Developer ID, for releases).
2. The **"Pixel Pet Dev"** certificate, when the keychain has it.
3. Ad-hoc signing.

With ad-hoc signing, macOS treats every rebuild as a new app. The Accessibility permission (needed for ⌃⌥T) then stops working after each build, with no message. The toggle in System Settings still shows "on". To fix it, remove the app with "−" and allow it again.

A self-signed code-signing certificate gives every build the same identity. To create one (this changes your keychain, so do it yourself):

1. Open Keychain Access, then choose Keychain Access → Certificate Assistant → Create a Certificate…
2. Set the name to `Pixel Pet Dev`, the identity type to *Self-Signed Root*, and the certificate type to *Code Signing*.
3. Rebuild with `./scripts/install.sh`, then grant Accessibility one last time.

## Releases

`scripts/release.sh <version>` builds `build/PixelPet-<version>.dmg`. The DMG has the app and a link to Applications, in a window with a background picture. The app's `SHORT_VERSION` is the version without a prerelease suffix (numbers only).

What else the script does depends on what you set. So the same script is a dry run on any Mac:

| Set | Result |
|---|---|
| nothing | App signed ad-hoc, DMG unsigned. This is a dry run: Gatekeeper blocks the app on other Macs |
| `SIGN_IDENTITY="Developer ID Application: …"` | App signed with hardened runtime, `scripts/PixelPet.entitlements` and a secure timestamp. DMG signed |
| plus `NOTARY_PROFILE` (from `xcrun notarytool store-credentials`), or `NOTARY_KEY` + `NOTARY_KEY_ID` + `NOTARY_ISSUER` (an App Store Connect API key) | The app is notarized and stapled before it goes into the DMG, so a copied-out app also opens offline. Then the DMG is notarized, stapled and checked with `spctl` |

[dmgbuild](https://github.com/dmgbuild/dmgbuild) lays out the window from `scripts/dmg-settings.py`. It writes the window's `.DS_Store` directly, without Finder scripting, so it works the same on CI. The script installs dmgbuild on first use into `build/.dmgbuild`, from `scripts/dmg-requirements.txt` with pinned hashes.

The app's sprite code draws the picture in `Resources/DMG/`. After you change the cube or the layout, regenerate the picture and update the icon positions in `dmg-settings.py` to match:

```bash
swift build && .build/debug/PixelPet --export-dmg-background Resources/DMG
```

The picture's tone is chosen so that the icon names Finder draws on it (black or white, depending on the system) both have a contrast of 4.6:1.

### Release workflow

Push a tag such as `v0.2.0` to run the Release workflow on `macos-26`. A tag with a suffix, such as `v0.3.0-beta.1`, is published as a prerelease. The workflow:

1. Checks the tag (see the rules below).
2. Imports the certificate into a temporary keychain.
3. Runs `release.sh`.
4. Signs the update for Sparkle (see [Updates](#updates-sparkle)).
5. Publishes a GitHub release with the DMG and generated notes.

Each secret goes only to the step that needs it: the certificate to the keychain import, the notary key to its own step. The actions are pinned to commits, and Dependabot keeps the pins current.

The job runs in the `release` environment (Settings → Environments). Only tags that match `v*` may use it, and admins can't bypass this. So no branch, pull request or other workflow can read its secrets.

Tags are not protected like branches, and a stolen token acts as the admin. So every release needs the maintainer's YubiKey:

- The "Signed release tags" ruleset (Settings → Rules) accepts only `v*` tags with a signature that GitHub verifies, with no bypass. The "Release tags" ruleset lets only admins create, move or delete them. Create the tag with:

  ```bash
  git tag -s v0.3.0 -m v0.3.0
  ```

- Before it builds anything, the job checks the tag's signature through the GitHub API. It rejects lightweight tags. The signature must come from one of the two signing subkeys listed in `release.yml` (one per YubiKey). A key added to the account later does not pass. After you renew or replace a subkey, update that list.
- The next step fails unless the tagged commit is already on `main`. This catches a tag put on a branch by mistake. Tag only after merging.
- The "Signed main" ruleset accepts only signed commits on `main`, with no bypass, no force-push and no deletion. So nobody can remove these checks without a signed commit.

Pull requests from forks:

- Their workflows wait for approval ("Approve and run") for every outside contributor, not only first-time contributors.
- They run with a read-only token and no secrets. The repository has no secrets, the `release` environment only accepts `v*` tags, and no workflow uses `pull_request_target`.
- Their commits are usually unsigned. Merge them with **Squash and merge** or a merge commit, which GitHub signs. Rebase merging is turned off, and "Signed main" refuses a fast-forward of unsigned commits.

Code on `main` ships only with the maintainer's signed tag.

The workflow reads these secrets from the `release` environment. Set them there, or with `gh secret set <NAME> --env release`:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12` | The Developer ID Application certificate with its private key, exported as .p12 and base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_P12_PASSWORD` | The .p12 export password |
| `SPARKLE_PRIVATE_KEY` | Sparkle's private EdDSA key, in the format `generate_keys -x` exports. Set it with the command in [Updates](#updates-sparkle). Without it, releases ship no appcast |
| `APPLE_API_KEY` | An App Store Connect API key (.p8, "Developer" role), base64-encoded |
| `APPLE_API_KEY_ID` / `APPLE_API_ISSUER_ID` | The key's id and issuer id |

Without the certificate secrets, the workflow still runs. It is then a dry run, published as a draft prerelease.

The entitlements file grants only calendar access (for call reminders) and microphone input (for listening). The hardened runtime needs both. Reading the selection (Accessibility) needs no entitlement.

### Updates (Sparkle)

The downloaded app updates itself with [Sparkle](https://sparkle-project.org) 2, from SwiftPM. `Package.swift` pins the version.

What `bundle.sh` does:

- It copies `Sparkle.framework` into `Contents/Frameworks` without its XPC services (those are for sandboxed apps).
- It signs the framework from the inside out.
- Only when it gets `UPDATE_PUBLIC_KEY`, it writes the feed and the key into Info.plist. A build without the key never checks for updates.

`release.sh` passes the key from `scripts/sparkle-public-key`. It also sets the build version to the marketing version, which Sparkle compares with the appcast.

The feed is `appcast.xml` on the latest GitHub release. For a signed, notarized tag without a prerelease suffix, the Release workflow runs `scripts/appcast.sh`. This script:

1. Signs the stapled DMG with the private EdDSA key. The key is the `SPARKLE_PRIVATE_KEY` secret of the `release` environment. It is piped to Sparkle's `sign_update` and never written to disk.
2. Checks that signature against the public key in `scripts/sparkle-public-key`, with OpenSSL 3. A key pair that does not match would ship an update that no installed app accepts.
3. Writes the appcast with `scripts/make-appcast.py`: version, minimum macOS, and the DMG's URL, length and signature.
4. Signs the appcast too.

The `Publish` step attaches the appcast to the release.

The app requires a signed feed and checks the archive before it unpacks it (`SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`).

The EdDSA key is the trust root: anyone with the private key can ship an update. So it lives only in the `release` environment and in the keychain where it was created. Sparkle's code-signing comparison is an extra check, not a second key.

Prereleases do not update themselves, because they carry the numbers of the final version. They get no appcast. The feed has no release notes: the update card links to the release page.

A known limit: Sparkle's feed has no expiry date and no minimum version. Someone who can edit releases (a stolen token with `contents: write`) can't ship code without the private key. But they can delete the newest release, so that apps behind it are offered an older, validly signed one. The release environment, the tag rulesets and signed tags limit this to the maintainer's account.

#### Creating the key pair

Create the key pair once with Sparkle's `generate_keys`. After a build it is in `.build/artifacts/sparkle/Sparkle/bin`. It stores the private key in the login keychain and prints the public key. Put the public key in `scripts/sparkle-public-key`.

Send the private key to the secret straight from the keychain item that `generate_keys` created, without a file. macOS asks you to allow the access:

```bash
security find-generic-password -s "https://sparkle-project.org" -a ed25519 -w | gh secret set SPARKLE_PRIVATE_KEY --env release
```

Do not use `generate_keys -x /dev/stdout`. It refuses a path that already exists and prints the error where the key would go. That error text then becomes the secret.

#### Testing an update locally

To test a full update without a release:

1. Quit the pet.
2. Run `scripts/update-test.sh`. It builds 0.2.1 and 0.2.2 with a throwaway key and a feed on 127.0.0.1 (`OLD_VERSION`, `NEW_VERSION` and `PORT` change this). It serves the newer DMG and a signed appcast, and starts the older build with `--update-check-now`.
3. The box floats down. Click the cube to open the card.
4. Click Update, then Restart. The app relaunches into 0.2.2, which comes out of its box.
5. Press Ctrl-C to stop the server. The script then deletes the test build in `build/PixelPet.app`. Its other files stay in `build/update-test`.
6. Clear what Sparkle wrote into the app's defaults (`defaults read dev.pixelpet.PixelPet` shows them). Otherwise a version you skipped while testing stays skipped.

Only a build with a local feed and no `SIGN_IDENTITY` gets an App Transport Security exception for the plain-http feed. Release builds never get it.

## Known gaps and ideas

- **Stable code signing.** Builds are signed ad-hoc until a "Pixel Pet Dev" certificate exists (see [Code signing](#code-signing)). So the Accessibility permission must be granted again after each rebuild.
- **Aseprite sprites.** Frames are drawn in code (`SpriteFactory`). An Aseprite sprite sheet would only change what produces the canvases.
- **FIDO2 touches.** The YubiKey hint covers GPG only. `sk-` SSH keys and passkeys appear as kernel HID messages in the system log instead.
- **A ball to play with.** Started from the context menu ("Play"), not with a double-click: a double-click would delay every single click that opens the status panel. A small ball sits on the floor where the pet stands. It bounces, and the pet chases and kicks it a few times. The user can flick it with the mouse (the throw physics already exist). It rolls away after about 30 s. It stays near the pet and does not cross the screen. No score.
- **Codex waiting for approval.** Codex does not write approval prompts to its session files, so its blocks never turn amber. Its hooks (`PermissionRequest`) could add this, if the desktop app runs them.

## Findings worth knowing

These were measured or found while building. They explain choices that otherwise look odd.

- **Rendering cost.** SpriteKit used 2–8% CPU and about 125 MB while idle (it keeps running even when paused). Swapping `CGImage`s in a `CALayer` costs 0.1–0.2% and about 12 MB.
- **Hook latency.** `sh` + `nc -U` to the socket takes about 10 ms per call (12 ms at worst). `python3` alone takes about 20 ms to start. So the hook is a shell script.
- **Socket path.** Unix socket paths are limited to about 104 bytes. So the socket is at `~/.pixelpet/pet.sock`, not in a temporary folder.
- **Hooks and desktop sessions.** Hooks fire for Claude desktop (Code tab) sessions too. Sessions that are already open start sending events as soon as `settings.json` changes, without a `SessionStart`. The statusline never runs for desktop sessions, so the limits come from `rate_limit_event` instead.
- **`claude -p`.** `--bare` needs an API key and ignores the subscription, so the app can't use it. `--setting-sources project` keeps user hooks out instead. With haiku, the first token arrives after about 2.7 s. `result` comes about 1.4 s after `message_stop` (the post-turn summary). So an answer counts as done at `message_stop`.
- **Post-turn summary.** After each turn, Claude Code runs a short internal subagent. Its `SubagentStop` arrives without a `SubagentStart`. It is not one of the user's subagents.

## Conventions

- **Branches.** Each piece of work gets a branch such as `feat/<topic>` or `fix/<topic>`. It is fast-forward merged into `main` after it is checked.
- **Commits.** Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`).
- **Comments.** Comments explain *why*: constraints, platform quirks, measured numbers. Doc comments (`///`) go on types and on members that are not obvious.
- **Main actor.** UI code is `@MainActor`. `EventServer` runs on its own serial queue. It passes payloads to the main actor through one ordered `AsyncStream`.
- **Performance budget.** Aim for under 1% CPU while idle, under 3% while animating, under 60 MB of RAM, and under 20 ms per hook call. Do not add fast polling. Schedule a timer for the next known change instead. The only repeating timer is the slow 20 s idle check in `DesktopSensor`.
- **Privacy.** Never store prompt text, tool input or window titles. New uses of the selection or the clipboard go through `SelectionDecision`.
- **Strings.** The UI is in English by default, with Russian as an option (Settings → Language). Write every UI string as `L("English", "Русский")` (`Sources/PixelPet/Localization.swift`). Tables of titles are computed (`static var`), so they follow a language change. SwiftUI views redraw by themselves. The menu bar menu updates its titles each time it opens.

### Adding a pet state

1. Add the case to `PetState` (`Sources/PetCore/PetState.swift`), with its per-frame durations in `PetState.millis`. If it plays once, add it to the one-shots in `loops`.
2. Choose its Reduce Motion behavior in `MotionPolicy`: a still frame, skip, or a held cue.
3. Draw it in `SpriteFactory.draw`. Use `BodyStyle` for the body, so skins, accessories and blush work without extra code.
4. Give it a title in `StatusMenu.stateTitles`.
5. Trigger it from `PetController` or `AgentMonitor`.
6. Add tests. `SpriteFactoryTests.producesOneCanvasPerFrame` already covers every case. Add a test for what makes the new state different.
7. Check the result with `--export-sprites` and the State menu.

### Changing what the hooks send

1. Add the event name to `HookSettings.events`. Existing installs get it the next time the user reconnects.
2. Map it in `AgentEvent.parse`.
3. Handle it in `SessionRegistry.apply`, with tests. Keep only the metadata you need.
