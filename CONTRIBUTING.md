# Contributing

Issues and pull requests are welcome.

- Keep `bin/claude-as` a single self-contained script that runs under bash 3.2
  (macOS's `/bin/bash`): no associative arrays or `mapfile`, and guard array
  expansions under `set -u`.
- Never share account state. `.claude.json` and `.credentials.json` must stay
  per-profile. The script rejects them as share entries, and a test enforces it.
- `setup` must never move or delete user files. Only `doctor --fix` does that,
  and it keeps a copy of anything it displaces.
- Anything that moves or deletes files must first check `overlaps` (the two
  sides must not be the same place) and must report a failed step instead of
  carrying on.
- The permission hook (`hook_allows`) must never approve more than Claude Code
  allows by itself without a symlink, and every case it refuses needs a test.
  The tests are checked against a copy of the script whose hook approves
  everything, and every refusal test must fail against that copy.
- Keep the launch path (`claude-as <profile>`) free of subshells and external
  commands once a profile exists; it runs before every Claude Code start. The
  one exception is the plugin path repair, which runs `jq` only when a plugin
  file has changed since the profile's last launch (a stamp file tells).
- Add a bats test for every behaviour change. Tests run in a throwaway `HOME`
  (whose path contains a space) with a fake `claude`, and must never touch the
  real `~/.claude`.
- bats runs test files with the `bash` on `PATH`, which on macOS is 3.2. There
  a failing `[[ ... ]]` in the middle of a test does not fail it, and in any
  bash neither does the first half of `[ a ] && [ b ]`. End such lines with
  `|| false`.

## Claude Code behaviour to re-check

claude-as depends on details of how Claude Code uses its config directory.
These were last checked against Claude Code 2.1.332; re-check them when a new
release changes anything nearby.

- A symlinked `projects/` or `plans/` makes the session's own auto-memory
  writes, its reads of its saved tool output, and plan-mode plan files prompt,
  or fail headless ([anthropics/claude-code#98044], [#112052]). Allow rules and
  PreToolUse hooks can't approve them; a PermissionRequest hook can, which is
  what `claude-as hook permission-request` does. If upstream fixes this, the
  hook can go and `projects` and `plans` can join the default share list.
- Plugins record their install path under `$CLAUDE_CONFIG_DIR`, so under the
  profile that installed or updated them. Launch and `doctor --fix` rewrite
  those paths to the base. Setting `CLAUDE_CODE_PLUGIN_CACHE_DIR` to the base
  would avoid this, but Claude Code changes several other plugin behaviours
  when that variable is set, so claude-as doesn't set it.
- `settings.json` is written through its symlink, not replaced by a file.
- A few paths ignore `CLAUDE_CONFIG_DIR` and always use `~/.claude`:
  `~/.claude/ssh` ([#111548], on Linux) and scheduled-task definitions
  ([#100138]). That is harmless while the base is `~/.claude`.
- Updating a marketplace from a profile other than the one that added it
  ([#82272]) used to fail; it works in 2.1.332.

[anthropics/claude-code#98044]: https://github.com/anthropics/claude-code/issues/98044
[#112052]: https://github.com/anthropics/claude-code/issues/112052
[#111548]: https://github.com/anthropics/claude-code/issues/111548
[#100138]: https://github.com/anthropics/claude-code/issues/100138
[#82272]: https://github.com/anthropics/claude-code/issues/82272

## Before opening a PR


```bash
shellcheck -x bin/claude-as install.sh tests/helpers.bash
bats tests/
TEST_BASH=/bin/bash bats tests/   # on macOS
```
