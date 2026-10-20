# Security

Pixel Pet runs on your Mac with the permissions you grant it: it reads Claude Code hook events from a local
socket (`~/.pixelpet/pet.sock`), Codex session files, your calendars (if allowed), the selection (with
Accessibility) and one system log message for the YubiKey hint. It never sends any of that anywhere; the
only network traffic is the `claude` / `codex` CLIs you already use.

If you find a vulnerability (for example a way for another local process or a web page to drive the pet's
socket, read what it reads, or run commands through it), please report it privately through
[GitHub Security Advisories](https://github.com/DiRaiks/pixel-pet/security/advisories/new) rather than a
public issue.
