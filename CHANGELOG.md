# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Docs, help text and demo describe any number of accounts generically
  (examples use `alt` / `alt2` instead of work/personal), and a test covers
  four profiles at once plus imports between non-default profiles.

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
  #112052); they can be opted in with `share_add`.
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
