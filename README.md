# claude-as

**Run Claude Code as any number of accounts at the same time, with one shared setup.**

[![CI](https://github.com/SteveVitali/claude-as/actions/workflows/ci.yml/badge.svg)](https://github.com/SteveVitali/claude-as/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

```bash
brew install SteveVitali/tap/claude-as
claude-as alt auth login   # sign in to another account; your normal `claude` is untouched
claude-as alt              # run Claude Code as that account, in any terminal, alongside the others
```

![claude-as demo: list profiles, log in to a second profile, link claude-alt, and check that skills are shared](docs/demo.gif)

<sub>The demo runs in a sandbox with a stand-in `claude`; see [`docs/demo.tape`](docs/demo.tape).</sub>

## Why

Anthropic's [documented way](https://code.claude.com/docs/en/authentication) to stay signed in to more than one account is to give each one its own config directory:

```bash
alias claude-alt='CLAUDE_CONFIG_DIR=~/.claude-alt claude'
```

That gives you a separate login, but nothing else from your normal setup. The new directory starts empty: no `settings.json`, no `CLAUDE.md`, skills, agents, slash commands or plugins, no MCP servers, no prompt history. You redo onboarding, re-trust every folder, and from then on keep every setup in sync by hand.

`claude-as` keeps the separate login and links your setup back to `~/.claude`. Change a setting or add a skill in one account and every account has it. Carry a session from one account to another with `claude-as import`. Your default `claude` keeps working exactly as before.

It is one bash script. It needs no configuration, and it never reads, copies or moves your credentials: each profile signs in with Claude Code's own `/login`.

## Install

**Homebrew** (macOS and Linux):

```bash
brew install SteveVitali/tap/claude-as
```

**curl:**

```bash
curl -fsSL https://raw.githubusercontent.com/SteveVitali/claude-as/main/install.sh | bash
```

**Manual:** copy [`bin/claude-as`](bin/claude-as) anywhere on your `PATH`. It runs on macOS's built-in bash 3.2 as well as current bash. `jq` is recommended: it is used to carry your onboarding, project trust and MCP servers into new profiles, and for `sync` and `list`.

## Quick start

```bash
claude-as alt auth login     # creates the "alt" profile and signs in (or: claude-as alt, then /login)
claude-as link alt           # optional: adds a `claude-alt` command to ~/.local/bin
claude-as list
```

```
  PROFILE        ACCOUNT                      CONFIG DIR
* default        me@example.com               ~/.claude
  alt            me@example.org               ~/.claude-alt
  alt2           me@example.net               ~/.claude-alt2
```

Add as many profiles as you have accounts: each name gets its own `~/.claude-<name>` and its own login, and all of them share the same setup. Every argument after the profile name is passed to `claude` unchanged: `claude-as alt -p "..."`, `claude-as alt --resume`, `claude-as alt mcp list`.

## How it works

Claude Code keeps its configuration in `~/.claude`, or in `$CLAUDE_CONFIG_DIR` when that is set. The login is stored per config directory: in the macOS Keychain under an entry keyed to the directory, or in `<dir>/.credentials.json` on Linux.

`claude-as alt` runs `claude` with `CLAUDE_CONFIG_DIR=~/.claude-alt`. The first time, it creates that directory and fills it with symlinks into `~/.claude`:

| Shared (symlinked to `~/.claude`) | Separate for each profile |
|---|---|
| `settings.json`: model, permissions, hooks, status line, enabled plugins | The login |
| `CLAUDE.md`, `keybindings.json` | `.claude.json`: account, onboarding, caches, user-scope MCP servers* |
| `skills/`, `agents/`, `commands/`, `output-styles/`, `hooks/` | `projects/`: transcripts and auto-memory† |
| `plugins/`: installed plugins and marketplaces | `plans/`† |
| `history.jsonl` (prompt history), `file-history/`, `todos/` | Running-session state, telemetry, stats and caches |

† These can be shared with `share_add = projects plans`, but sharing them currently costs you permission prompts; see [why they aren't shared](#why-arent-transcripts-and-memory-shared). Use `claude-as import` to move a session between accounts.

\* A new profile's `.claude.json` starts as a copy of yours with the account, IDs and caches removed. You skip onboarding, keep your project trust and keep your MCP servers. After that the two are separate; `claude-as sync alt` copies over servers and project settings you add later.

The `default` profile is plain `~/.claude`. `claude-as` runs it with `CLAUDE_CONFIG_DIR` **unset**, which also stops a value inherited from another profile's shell leaking in. Pointing `CLAUDE_CONFIG_DIR` at `~/.claude` explicitly does not work: Claude Code then looks for `~/.claude/.claude.json` and a different Keychain entry, and your normal account appears logged out.

`claude-as` exports `CLAUDE_AS_PROFILE=<name>` so status lines, hooks and scripts can tell which account they are running under.

## Commands

| Command | What it does |
|---|---|
| `claude-as <profile> [args...]` | Run `claude` as `<profile>`, creating the profile on first use |
| `claude-as list` | Profiles, the account each is signed in to, and the active one (`*`) |
| `claude-as setup <profile>` | Create or refresh a profile without starting `claude` |
| `claude-as link <profile> [dir]` | Add a `claude-<profile>` command (default dir `~/.local/bin`) |
| `claude-as env <profile>` | Print shell exports: `eval "$(claude-as env alt)"` |
| `claude-as import <profile> <session-id>` | Copy a session (and its subagent transcripts) from whichever profile has it, so `<profile>` can `--resume` it |
| `claude-as sync <profile>` | Copy MCP servers and project settings the profile lacks from the default profile. The profile's own values win |
| `claude-as doctor [profile] [--fix]` | Check that every shared item is still linked, and warn about variables or settings that override every profile's login; `--fix` repairs the links |

Profile names use lowercase letters, digits, `-` and `_`. Command names (`list`, `setup`, ...) and `as` are reserved.

## Already using `CLAUDE_CONFIG_DIR=~/.claude-alt`?

`claude-as` adopts the directory as it is, and your existing login keeps working:

```bash
claude-as setup alt          # links whatever is missing and lists what is still separate
claude-as doctor alt --fix   # merges the profile's own copies into the shared ones
```

`--fix` never overwrites anything:
- Files and folders that exist only in the profile are moved into `~/.claude`.
- Exact duplicates are dropped.
- Folders that exist on both sides, such as `skills/` and `plugins/`, are merged.
- A file that differs on the two sides keeps the `~/.claude` version. The profile's version is set aside in `<name>.claude-as-stray.<timestamp>` for you to diff.

## Configuration

This is optional. The file lives at `${XDG_CONFIG_HOME:-~/.config}/claude-as/config`, or wherever `CLAUDE_AS_CONFIG` points. Each line is `key = value`, and lines starting with `#` are comments.

```ini
# More names for the ~/.claude profile. The first one is shown in `list`.
default_aliases = main

# Share more or less than the defaults (names inside ~/.claude).
share_add  = statusline.sh
share_skip = history.jsonl
# share_add = projects plans    # see "Why aren't transcripts and memory shared?"

# Use a specific claude binary instead of the `claude` on PATH.
claude_bin = ~/.local/bin/claude

# The shared base directory, if it is not ~/.claude.
# base_dir = ~/.claude
```

Environment variables override the file: `CLAUDE_AS_BIN`, `CLAUDE_AS_BASE`, `CLAUDE_AS_CONFIG`.

## Alternatives

Many tools tackle this. Pick the one that fits:

- **The plain alias above** is official and needs no install. Each account gets its own empty setup.
- **Keychain switchers** such as [cc-account-switcher](https://github.com/ming86/cc-account-switcher) and [CCSwitcher](https://github.com/XueshiQiao/CCSwitcher) swap the stored login, so only one account is active at a time.
- **[claude-swap](https://github.com/realiti4/claude-swap)** (Python) is a full-featured switcher with a usage dashboard, automatic switching, and a session mode that runs accounts concurrently.
- **[cpm](https://github.com/JakubKontra/claude-profile-manager)** (Go) is a featureful profile manager. It has per-project auto-switching, per-profile setting overrides, cloud sync, and login adoption. It gives each profile its own copy of `settings.json`, so profiles can be tuned separately.
- **claude-as** is the small one: a single script on top of the official mechanism, with nothing to configure. Settings, `CLAUDE.md`, skills, plugins and prompt history are the *same files* for every account, not copies, and it never handles credentials.

## Responsible use

`claude-as` is for running accounts that are **yours to use** side by side. It does not share, pool or proxy accounts. Each profile signs in on its own and keeps its own credentials. Follow your organization's policies and Anthropic's [terms](https://www.anthropic.com/legal/consumer-terms) for each account.

## FAQ

**Can I resume a session started under another account?**
Yes. Run `claude-as import alt <session-id>`, then `claude-as alt --resume <session-id>` from the same folder. The session ID is the name of the session's `.jsonl` file under `~/.claude/projects/`. The import is a copy, so the original stays where it was. Prompt caching is per account, so the first turn after switching sends the whole conversation again.

<a id="why-arent-transcripts-and-memory-shared"></a>
**Why aren't transcripts and memory shared?**
Sharing them needs `projects/` to be a symlink. Since Claude Code 2.1.280 that triggers an upstream permission bug ([#98044](https://github.com/anthropics/claude-code/issues/98044), [#112052](https://github.com/anthropics/claude-code/issues/112052)). Claude Code then treats the following as sensitive writes outside the config directory:
- every auto-memory write
- every read-back of a large saved tool output
- every plan-mode plan file (in `plans/`)

Each one prompts with no "always allow", and headless `claude -p` runs get them denied. If you mostly work interactively and want shared memory anyway, set `share_add = projects plans` and run `claude-as doctor --fix`. If the bug is fixed upstream, sharing them by default will be reconsidered.

**Is it safe to run several accounts at the same time?**
Yes, that is the point. Running-session state is per profile. The shared files are the same ones Claude Code already shares between concurrent sessions of a single account.

**What if Claude Code replaces a shared link with a real file?**
Claude Code writes `settings.json` through the link (checked with Claude Code 2.1.x). If any shared item ever turns into a real file, each launch warns about it and `claude-as doctor --fix` merges it back.

**I don't want to share X.**
Add it to `share_skip`. Or replace the link inside the profile with a real file: `setup` never overwrites real files, it only warns.

**How do I remove a profile?**
Run `claude-as alt auth logout`, then `rm -rf ~/.claude-alt`. The shared data lives in `~/.claude` and is not affected.

**API keys, Bedrock or Vertex?**
`claude-as` only chooses the config directory. Whatever authentication that profile is set up with is what it uses.

**IDE extensions or the desktop app?**
Those start Claude Code themselves, so `claude-as` is not in the loop. Claude Code honours `CLAUDE_CONFIG_DIR` wherever it starts, so launching your editor from a shell after `eval "$(claude-as env alt)"` should point it at that profile. This is untested; reports are welcome.

**Windows?**
Not natively. It should work inside WSL, but that is untested.

## Known upstream issues

These are Claude Code bugs that affect setups with more than one config directory, including this one:

- Writes through a symlinked `projects/` or `plans/` prompt ([#98044](https://github.com/anthropics/claude-code/issues/98044), [#112052](https://github.com/anthropics/claude-code/issues/112052)). This is why they aren't shared by default.
- A few files are still written to `~/.claude` whatever the config directory is, for example `~/.claude/ssh` ([#111548](https://github.com/anthropics/claude-code/issues/111548)) and scheduled tasks ([#100138](https://github.com/anthropics/claude-code/issues/100138)).
- Plugins record their install path under the profile that installed them. If you delete that profile, reinstall the plugin from another one. Updating a git marketplace may only work from the profile that added it ([#82272](https://github.com/anthropics/claude-code/issues/82272)).
- `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY` and `apiKeyHelper` take precedence over a profile's own login ([docs](https://code.claude.com/docs/en/authentication#authentication-precedence)). If they are set globally, or in the shared `settings.json`, every profile uses them. `claude-as doctor` warns about this.

## Development

```bash
shellcheck -x bin/claude-as install.sh tests/helpers.bash
bats tests/                        # each test uses a throwaway HOME and a fake claude
TEST_BASH=/bin/bash bats tests/    # again under macOS's bash 3.2
vhs docs/demo.tape                 # re-render the demo GIF (sandboxed)
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [RELEASING.md](RELEASING.md).

## License

[MIT](LICENSE). Unofficial; not affiliated with or endorsed by Anthropic.
