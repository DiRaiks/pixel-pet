# Contributing

Thanks for your interest! Pixel Pet is a small personal project. Issues and small pull requests are the
easiest to review.

- **Build, run and test:** see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Run `./scripts/test.sh`, not
  plain `swift test`. CI builds and tests every pull request on macOS 26.
- **How it fits together:** see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Conventions:**
  - Use Conventional Commits (`feat:`, `fix:`, `docs:` …).
  - Put logic in `PetCore`, with tests.
  - Write UI strings as `L("English", "Русский")`.
  - Comments explain why.
- **Art:** sprites are drawn in code. If you change them, regenerate the README pictures
  (`swift build && .build/debug/PixelPet --export-readme docs/images`). Add a before/after to the pull request.
- **Privacy:** never store prompt text, tool input or window titles.
