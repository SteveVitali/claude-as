# Contributing

Issues and pull requests are welcome.

- Keep `bin/claude-as` a single self-contained script that runs under bash 3.2
  (macOS's `/bin/bash`): no associative arrays or `mapfile`, and guard array
  expansions under `set -u`.
- Never share account state. `.claude.json` and `.credentials.json` must stay
  per-profile. The script rejects them as share entries, and a test enforces it.
- `setup` must never move or delete user files. Only `doctor --fix` does that,
  and it keeps a copy of anything it displaces.
- Add a bats test for every behaviour change. Tests run in a throwaway `HOME`
  with a fake `claude`, and must never touch the real `~/.claude`.

Before opening a PR:

```bash
shellcheck -x bin/claude-as install.sh tests/helpers.bash
bats tests/
TEST_BASH=/bin/bash bats tests/   # on macOS
```
