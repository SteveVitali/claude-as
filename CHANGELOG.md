# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-11-25

### Fixed
- `doctor --fix` could delete the shared `~/.claude` contents when a profile's
  folder was the base directory itself: a `~/.claude-<name>` profile whose name
  later became a `default_aliases` entry, or `base_dir` pointing at a profile.
  Profiles that resolve to the base are now skipped and refused, and every
  move or delete first checks that the two sides are not the same place.
- Two first launches of the same new profile at once could fail with
  "File exists" or leave self-referencing links inside `~/.claude`; linking is
  now race-safe, and a new profile's `.claude.json` is never written over one
  that `claude` has already created.
- `doctor --fix` now reports a move or link that fails instead of printing
  "fixed", and no longer prompts for read-only files (such as git objects in
  plugin marketplaces).
- `import` no longer nests a session's folder inside an existing one, and an
  interrupted import is redone on the next run.
- `import` failed when `HOME` contained a space.
- A relative `base_dir` is rejected (it made the config directory, and so the
  Keychain entry, depend on the current folder). Every trailing slash is
  stripped from `HOME` and `base_dir`.
- `share_add = *` no longer expands to files in the current folder.
- `link` replaces a dead `claude-<name>` link left by an earlier install.
- A directory given as the claude binary is rejected.

### Changed
- Running a profile that does not exist asks before creating it in a
  terminal, and fails otherwise (create it with `claude-as setup <name>`), so
  a typo no longer makes a new account profile. `env`, `import` and `sync` need
  an existing profile.
- Claude Code's own subcommand names (`auth`, `mcp`, `plugin`, ...) are
  reserved: `claude-as auth login` points out the missing profile name.
- Launching through `claude-as` costs a few milliseconds instead of ~100 ms:
  the launch path no longer starts subshells or external commands once a
  profile exists, and the config file is read once.
- The config file reports unknown settings and malformed lines; list settings
  may be repeated.
- `list` sizes its columns to their content.
- `doctor` also warns about `ANTHROPIC_PROFILE` and `CLAUDE_CODE_USE_FOUNDRY`,
  and explains a `CLAUDE_CONFIG_DIR` set by your shell.
- The curl installer installs the latest release instead of `main`.
- Docs, help text and demo describe multiple accounts generically.

## [0.1.0] - 2026-11-25

### Added
- `claude-as <profile> [args...]` runs Claude Code with a per-profile
  `CLAUDE_CONFIG_DIR` (`~/.claude-<profile>`), so each profile has its own login.
  The `default` profile (and any `default_aliases`) runs with `CLAUDE_CONFIG_DIR`
  unset, exactly like plain `claude`.
- Shared items (settings, CLAUDE.md, keybindings, skills, agents, commands,
  output styles, hooks, plugins, prompt history, file history, todos) are
  symlinked into each profile from `~/.claude`. Transcripts/auto-memory
  (`projects/`) and `plans/` stay per profile by default because of an upstream
  permission bug with symlinked `projects/` (anthropics/claude-code#98044,
  anthropics/claude-code#112052); they can be opted in with `share_add`.
- `import` copies a session (with its subagent transcripts) from another profile
  so it can be resumed there.
- Links point at the final target when a shared item in `~/.claude` is itself a
  symlink (Claude Code follows one hop when saving).
- `doctor` warns about environment variables and shared settings that override
  every profile's own login.
- A new profile's `.claude.json` is seeded from the default one with the account,
  IDs and caches removed, so onboarding, project trust and MCP servers carry over.
- `list`, `setup`, `link` (a `claude-<profile>` command), `env`, `sync`
  (MCP servers and project settings) and `doctor [--fix]`, which repairs drifted
  links and merges an existing hand-made `CLAUDE_CONFIG_DIR` into the shared setup
  without overwriting anything.
- Optional config file: `default_aliases`, `share_add`, `share_skip`,
  `claude_bin`, `base_dir`.
- Works with macOS's bash 3.2 as well as current bash.

[0.2.0]: https://github.com/SteveVitali/claude-as/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/SteveVitali/claude-as/releases/tag/v0.1.0
