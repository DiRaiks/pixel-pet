# Contributing

Thanks for looking! Pixel Pet is a small personal project, so issues and small pull requests are the
easiest to take in.

- **Build, run and test:** see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Run `./scripts/test.sh` rather
  than plain `swift test`. CI builds and tests every pull request on macOS 26.
- **How it fits together:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Conventions:** Conventional Commits (`feat:`, `fix:`, `docs:` …); logic goes in `PetCore` with tests;
  UI strings are written as `L("English", "Русский")`; comments explain why.
- **Art:** sprites are drawn in code. If you change them, regenerate the README pictures
  (`.build/debug/PixelPet --export-readme docs/images`) and include a before/after in the pull request.
- **Privacy:** never store prompt text, tool input or window titles.
