# Contributing

Thanks for taking a look. DevSweep is a small project with one maintainer,
so a few notes first save us both time.

## Issues

- **A bug:** what you did, what you expected and what happened, with your
  macOS version and DevSweep's, from its About window. The output of
  `devsweep` on its own, which only reports, shows what DevSweep found.
- **DevSweep deleted, or would delete, something it shouldn't:** please
  don't open a public issue. [SECURITY.md](SECURITY.md) says how to report
  it privately.
- **An idea:** open an issue and describe the problem it solves.

## Pull requests

- For anything bigger than a small fix, open an issue first, so we agree on
  the change before you build it.
- [AGENTS.md](AGENTS.md) has the project's rules: the layout, the app's
  architecture, the safety rule, commits and tests. They apply to everyone,
  people and coding agents alike. [docs/development.md](docs/development.md)
  has the setup and the three test layers.
- Before you open it, run `make lint test`, and
  `make acceptance DOTFILES=<dotfiles checkout>` if the command line tool
  changed.
- Say what changed and why, and which commands you ran. For a change to the
  window, add screenshots from `WIDTH=1280 Scripts/snapshot.sh`.
- Add a line under Unreleased in [CHANGELOG.md](CHANGELOG.md) for anything a
  user would notice.

## Safety while you work

Never run `devsweep --run` or `--yes`, or clean from a development build of
the app, against your real home folder while you try a change. The tests
run on a fake home in a temp folder, and `Scripts/snapshot.sh` shows the
window on one too.

## License

By contributing, you agree that your contributions are licensed under the
[MIT license](LICENSE).
