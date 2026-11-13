# Security

Pixel Pet runs on your Mac with the permissions you give it. It reads:

- Claude Code hook events from a local socket (`~/.pixelpet/pet.sock`)
- Codex session files
- your calendars (if you allow it)
- the selection (with Accessibility)
- the microphone, only while it listens (if you allow it)
- one system log message, for the YubiKey hint
- on/off signals from the Mac (audio devices, mic and camera in use, heat, power, network, theme, new screenshots), if "React to the Mac" is on
- what you do while no agent works (the app in front, apps opening and quitting, Spaces, removable volumes, screens, keyboard layout, and the time since the last key press, never the keys), if "Notice what I'm doing" is on

The app never sends any of this anywhere by itself. Network traffic comes only from:

- the `claude` CLI, which the app runs for some features (questions, translation "via Claude")
- the `codex` CLI (`codex app-server`), which the app asks for your Codex usage limits
- the update check in release builds: once a day it reads the update feed on GitHub and downloads updates from
  there. You can turn it off in Settings.
- macOS, which may download a speech or translation model once per language

If you find a vulnerability, report it privately through
[GitHub Security Advisories](https://github.com/DiRaiks/pixel-pet/security/advisories/new), not in a public
issue. Examples: a way for another local process or a web page to control the pet's socket, to read what the
pet reads, or to run commands through it.
