# claude-as

**Multiple Claude Code accounts on one machine: separate logins, one shared setup.**

[![CI](https://github.com/SteveVitali/claude-as/actions/workflows/ci.yml/badge.svg)](https://github.com/SteveVitali/claude-as/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

```bash
brew install SteveVitali/tap/claude-as
claude-as setup acme        # a profile for another account
claude-as acme auth login   # sign in to that account
claude-as acme              # Claude Code as that account, alongside your usual `claude`
```

![claude-as demo: create two profiles, sign in, list them with their accounts, and check that skills are shared](docs/demo.gif)

## Why

Anthropic's [documented way](https://code.claude.com/docs/en/authentication) to stay signed in to more than one account is to give each account its own config directory:

```bash
alias claude-acme='CLAUDE_CONFIG_DIR=~/.claude-acme claude'
```

That gives you a second login, and an empty setup to go with it: none of your settings, `CLAUDE.md`, skills, agents, slash commands, plugins, MCP servers or prompt history. You redo onboarding, re-trust every folder, and keep the copies in sync by hand from then on.

`claude-as` keeps the separate login and links the rest back to `~/.claude`. Change a setting or add a skill under one account and every account has it. Profiles are cheap: add one per account you use. Your plain `claude` keeps working exactly as before.

It is one bash script and needs no configuration. It never reads, copies or stores your Claude login: each profile signs in with Claude Code's own `/login`.

## Install

**Homebrew** (macOS and Linux):

```bash
brew install SteveVitali/tap/claude-as
```

**curl** (installs the latest release into `~/.local/bin`):

```bash
curl -fsSL https://raw.githubusercontent.com/SteveVitali/claude-as/main/install.sh | bash
```

**Manual:** download [`bin/claude-as`](bin/claude-as), read it, and put it anywhere on your `PATH`. It runs on macOS's built-in bash 3.2 and on current bash. Install `jq` too: without it, new profiles start without your onboarding, project trust and MCP servers, and `sync` won't run.

## Quick start

```bash
claude-as setup acme          # create a profile: ~/.claude-acme
claude-as acme auth login     # sign in (or run `claude-as acme` and type /login)
claude-as link acme           # optional: adds a `claude-acme` command to ~/.local/bin
claude-as list
```

When the browser opens to sign in, make sure it is signed in to the account you want for this profile. A private window helps.

```
  PROFILE   ACCOUNT           CONFIG DIR
  default   me@example.com    ~/.claude
  acme      me@acme.example   ~/.claude-acme
  lab       me@lab.example    ~/.claude-lab
```

Every argument after the profile name goes to `claude` unchanged: `claude-as acme -p "..."`, `claude-as acme --resume`, `claude-as acme mcp list`.

## How it works

Claude Code keeps its configuration in `~/.claude`, or in `$CLAUDE_CONFIG_DIR` when that is set. The login is stored per config directory: in the macOS Keychain under an entry keyed to the directory's path, or in `<dir>/.credentials.json` on Linux.

`claude-as acme` runs `claude` with `CLAUDE_CONFIG_DIR=~/.claude-acme`. `claude-as setup acme` creates that directory and fills it with symlinks into `~/.claude`:

| Shared (symlinked to `~/.claude`) | Separate for each profile |
|---|---|
| `settings.json`: model, permissions, hooks, status line, enabled plugins | The login |
| `CLAUDE.md`, `keybindings.json` | `.claude.json`: account, onboarding, project trust, MCP servers\* |
| `skills/`, `agents/`, `commands/`, `output-styles/`, `hooks/` | `projects/`: transcripts and auto-memory† |
| `plugins/`: installed plugins and marketplaces | `plans/`† |
| `history.jsonl` (prompt history), `file-history/`, `todos/` | Running-session state, telemetry, stats and caches |

\* A new profile's `.claude.json` starts as a copy of yours with the account, IDs and caches removed, so you skip onboarding and keep your project trust and MCP servers. MCP server definitions are copied as they are, including any tokens written into them. Servers that sign in with OAuth need signing in once per profile. After that the files are separate; `claude-as sync acme` copies over servers and project settings you add later.

† Not shared by default because of a Claude Code bug; see [why](#why-arent-transcripts-and-memory-shared). Use `claude-as import` to carry a session between accounts.

The `default` profile is plain `~/.claude`. `claude-as` runs it with `CLAUDE_CONFIG_DIR` **unset**, exactly like plain `claude`, so a value inherited from another profile's shell can't leak in. (Pointing `CLAUDE_CONFIG_DIR` at `~/.claude` explicitly does not work: Claude Code then looks for `~/.claude/.claude.json` and a different Keychain entry, and your normal account appears logged out.)

Some credentials take precedence over any profile's login ([docs](https://code.claude.com/docs/en/authentication#authentication-precedence)): `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY` and `apiKeyHelper` among them. If one is set in your shell, or in the shared `settings.json`, every profile uses it. `claude-as doctor` warns about these.

`claude-as` exports `CLAUDE_AS_PROFILE=<name>` so status lines, hooks and scripts can tell which account they are running under.

## Commands

| Command | What it does |
|---|---|
| `claude-as <profile> [args...]` | Run `claude` as `<profile>`. In a terminal it offers to create a profile that doesn't exist yet; otherwise it asks you to run `setup` |
| `claude-as setup <profile>` | Create a profile, or re-create any shared links that are missing |
| `claude-as list` | Each profile, the account it is signed in to, and its config dir. `*` marks the profile the current shell runs under |
| `claude-as link <profile> [dir]` | Add a `claude-<profile>` command (default dir `~/.local/bin`) |
| `claude-as env <profile>` | Print shell exports: `eval "$(claude-as env acme)"` |
| `claude-as import <profile> <session-id>` | Copy a session, with its subagent transcripts, from whichever profile has it, so `<profile>` can `--resume` it |
| `claude-as sync <profile>` | Copy MCP servers and project settings the profile lacks from the default profile. The profile's own values win |
| `claude-as doctor [profile] [--fix]` | Check every shared link, and warn about credentials that override profile logins. `--fix` re-creates links, and merges a profile's own copies of shared items into `~/.claude` (see below) |

Profile names use lowercase letters, digits, `-` and `_`. The names of `claude-as` and `claude` subcommands (`list`, `auth`, `mcp`, ...) are reserved, so `claude-as auth login` points out the missing profile name instead of creating a profile called `auth`.

## Already using `CLAUDE_CONFIG_DIR=~/.claude-<name>`?

`claude-as` adopts a directory named `~/.claude-<name>` as it is. The existing login keeps working because the path is unchanged. (Renaming a config directory loses its Keychain login, so keep the name.)

```bash
claude-as setup acme          # links whatever is missing; warns about the profile's own copies
claude-as doctor acme --fix   # merges those copies into the shared ones in ~/.claude
```

For each shared item that the profile has its own copy of, `--fix` merges without overwriting:
- If `~/.claude` lacks the item, it is moved there.
- Folders on both sides, such as `skills/` and `plugins/`, are merged entry by entry. Entries missing from `~/.claude` are moved over, exact duplicates are dropped, and anything that differs stays in `<name>.claude-as-stray.<timestamp>` next to the new link for you to compare.
- A file that differs keeps the `~/.claude` version. The profile's version is set aside the same way.

`--fix` also re-points shared links that point somewhere else. It refuses to touch anything when a profile's folder and `~/.claude` turn out to be the same place.

## Configuration

This is optional. The file lives at `${XDG_CONFIG_HOME:-~/.config}/claude-as/config`, or wherever `CLAUDE_AS_CONFIG` points. Each line is `key = value`; lines starting with `#` are comments. Unknown keys are reported, so typos don't go unnoticed.

```ini
# More names for the ~/.claude profile; the first is shown in `list`.
default_aliases = me

# Share more or less than the defaults (names inside ~/.claude). These apply
# to every profile and may be repeated.
share_add  = statusline.sh
share_skip = history.jsonl

# A specific claude binary instead of the `claude` on PATH.
claude_bin = ~/.local/bin/claude

# The shared base directory, if not ~/.claude (absolute, or starting with ~/).
# base_dir = ~/.claude
```

Environment variables override the file: `CLAUDE_AS_BIN`, `CLAUDE_AS_BASE`, `CLAUDE_AS_CONFIG`.

## Alternatives

Several tools tackle this; pick the one that fits.

- **The plain alias above** is official and needs nothing installed. Each account gets its own empty setup.
- **Keychain switchers** such as [CCSwitcher](https://github.com/XueshiQiao/CCSwitcher) and [cc-account-switcher](https://github.com/ming86/cc-account-switcher) (archived) swap the stored login, so one account is active at a time.
- **[claude-swap](https://github.com/realiti4/claude-swap)** (Python) is a full-featured switcher with a usage dashboard and automatic switching. Its session mode runs accounts concurrently on your normal `~/.claude` setup.
- **[cpm](https://github.com/JakubKontra/claude-profile-manager)** (Go) is a featureful profile manager: per-project auto-switching, per-profile overrides, cloud sync. It symlinks commands, skills, plugins and projects, and gives each profile its own copy of `settings.json`.
- **claude-as** is the small one. Like cpm and claude-swap's session mode, it shares your setup through symlinks. Unlike them, it is a single script with nothing to configure, links `settings.json` and `CLAUDE.md` instead of copying them, keeps transcripts per profile to avoid the upstream bug below, and never stores login tokens.

## Responsible use

`claude-as` is for accounts that are yours to use, side by side. It does not share, pool or proxy accounts, and it is not a way around any account's usage limits. Each profile signs in on its own, and each account's [terms](https://www.anthropic.com/legal) and your organization's policies still apply.

## FAQ

**Can I resume a session started under another account?**
Yes. Run `claude-as import acme <session-id>`, then `claude-as acme --resume <session-id>` from the same folder. The session ID is the name of the session's `.jsonl` file under `~/.claude/projects/`. The import is a copy, so the original stays where it was. Prompt caching is per account, so the first turn after switching sends the whole conversation again.

<a id="why-arent-transcripts-and-memory-shared"></a>
**Why aren't transcripts and memory shared?**
Sharing them needs `projects/` to be a symlink. Since Claude Code 2.1.280, that triggers an upstream permission bug ([anthropics/claude-code#98044](https://github.com/anthropics/claude-code/issues/98044), [#112052](https://github.com/anthropics/claude-code/issues/112052)). Every auto-memory write, every read-back of a large saved tool output, and every plan file in `plans/` is treated as a sensitive write outside the config directory. Each one prompts with no "always allow", and headless `claude -p` runs get them denied. If you mostly work interactively and want shared memory anyway, add `share_add = projects plans` and run `claude-as doctor --fix`.

**Can several accounts run at once without clobbering each other?**
Yes, that is the point. Running-session state is per profile. The shared files are the same ones Claude Code already shares between concurrent sessions of a single account.

**Can one account use different settings?**
`settings.json` is shared, and `share_skip` applies to every profile. For per-account differences, pass Claude Code's own `--settings` flag, for example `claude-as acme --settings ~/.claude-acme/overrides.json`. Command-line settings take precedence over user settings. A shell alias makes that permanent.

**What if Claude Code replaces a shared link with a real file?**
Claude Code 2.1.332 writes `settings.json` through the link. If a shared item ever does turn into a real file, each launch warns about it, and `claude-as doctor --fix` merges it back as described above.

**How do I remove a profile?**
Run `claude-as acme auth logout`, then `rm -rf ~/.claude-acme`, plus `rm ~/.local/bin/claude-acme` if you linked it. The shared setup lives in `~/.claude` and is not affected.

**API keys, Bedrock or Vertex?**
`claude-as` only chooses the config directory, so each profile uses whatever authentication it is set up with. One exception, per [Anthropic's docs](https://code.claude.com/docs/en/authentication): a Claude Console sign-in without an API key is kept outside the config directory, so profiles can't keep two of those apart.

**IDE extensions or the desktop app?**
Not tested. They start Claude Code themselves, so `claude-as` is not involved.

**Windows?**
Not natively. It may work inside WSL, but that is untested.

## Known upstream issues

These Claude Code bugs affect any setup with more than one config directory:

- Writes through a symlinked `projects/` or `plans/` prompt ([anthropics/claude-code#98044](https://github.com/anthropics/claude-code/issues/98044), [#112052](https://github.com/anthropics/claude-code/issues/112052)). This is why they aren't shared by default.
- A few files are still written to `~/.claude` whatever the config directory is, for example `~/.claude/ssh` ([#111548](https://github.com/anthropics/claude-code/issues/111548)) and scheduled tasks ([#100138](https://github.com/anthropics/claude-code/issues/100138)).
- Plugins record their install path under the profile that installed them. If you delete that profile, reinstall the plugin from another one. Updating a git marketplace may only work from the profile that added it ([#82272](https://github.com/anthropics/claude-code/issues/82272), closed as not planned).

## Development

```bash
shellcheck -x bin/claude-as install.sh tests/helpers.bash
bats tests/                        # each test uses a throwaway HOME (with a space in it) and a fake claude
TEST_BASH=/bin/bash bats tests/    # the script again under macOS's bash 3.2
vhs docs/demo.tape                 # re-render the demo GIF
```

The demo and the [social preview](docs/social-preview.tape) run in a sandbox built by [`docs/demo-env.sh`](docs/demo-env.sh), with a stand-in `claude` that only answers `auth login` and `auth status`. No real account is involved.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [RELEASING.md](RELEASING.md).

## License

[MIT](LICENSE). Unofficial; not affiliated with or endorsed by Anthropic.
