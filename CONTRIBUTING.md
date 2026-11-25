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
- Keep the launch path (`claude-as <profile>`) free of subshells and external
  commands once a profile exists; it runs before every Claude Code start.
- Add a bats test for every behaviour change. Tests run in a throwaway `HOME`
  (whose path contains a space) with a fake `claude`, and must never touch the
  real `~/.claude`.
- bats runs test files with the `bash` on `PATH`, which on macOS is 3.2. There
  a failing `[[ ... ]]` in the middle of a test does not fail it, and in any
  bash neither does the first half of `[ a ] && [ b ]`. End such lines with
  `|| false`.

Before opening a PR:

```bash
shellcheck -x bin/claude-as install.sh tests/helpers.bash
bats tests/
TEST_BASH=/bin/bash bats tests/   # on macOS
```
