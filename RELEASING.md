# Releasing claude-as

## Versioning

Semver. The single source of truth is `CLAUDE_AS_VERSION` in `bin/claude-as`.

## Checklist

1. Update `CLAUDE_AS_VERSION` in `bin/claude-as`.
2. Add a dated section to `CHANGELOG.md`, and its compare link at the bottom.
3. If Claude Code has had releases since the last check, go through
   "Claude Code behaviour to re-check" in `CONTRIBUTING.md` and update the
   version noted there and in the README FAQ.
4. Verify: `shellcheck -x bin/claude-as install.sh tests/helpers.bash && bats tests/ && TEST_BASH=/bin/bash bats tests/`.
5. Commit, tag and push, then create the release with the script attached
   (the curl installer downloads `releases/latest/download/claude-as`):

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main --tags
   awk -v v="X.Y.Z" '$0 ~ "^## \\[" v "\\]" {f=1; next} /^## \[/ {f=0} /^\[[0-9.]+\]: / {f=0} f' CHANGELOG.md > /tmp/notes.md
   gh release create vX.Y.Z bin/claude-as --title vX.Y.Z --notes-file /tmp/notes.md
   ```

6. Compute the tarball digest and update `Formula/claude-as.rb` (`url` and `sha256`):

   ```bash
   curl -fsSL https://github.com/SteveVitali/claude-as/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
   ```

7. Copy `Formula/claude-as.rb` into `SteveVitali/homebrew-tap` (`Formula/`), commit
   and push it, then check:

   ```bash
   brew update && brew upgrade claude-as || brew install SteveVitali/tap/claude-as
   brew test claude-as && claude-as --version
   ```

## Install channels

- **Homebrew:** the formula pins the release tag. Update it as described above.
- **curl installer:** `install.sh` installs the script attached to the latest
  GitHub release, so it matches Homebrew.
- **Manual:** `bin/claude-as` can be copied anywhere on `PATH`. It has no
  repo-relative dependencies.
