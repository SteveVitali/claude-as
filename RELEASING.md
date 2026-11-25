# Releasing claude-as

## Versioning

Semver. The single source of truth is `CLAUDE_AS_VERSION` in `bin/claude-as`.

## Checklist

1. Update `CLAUDE_AS_VERSION` in `bin/claude-as`.
2. Add a dated section to `CHANGELOG.md`.
3. Verify: `shellcheck -x bin/claude-as install.sh tests/helpers.bash && bats tests/ && TEST_BASH=/bin/bash bats tests/`.
4. Commit, tag and push:

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main --tags
   gh release create vX.Y.Z --title vX.Y.Z --notes-file <(sed -n '/## \[X.Y.Z\]/,/## \[/p' CHANGELOG.md | sed '$d')
   ```

5. Compute the tarball digest and update `Formula/claude-as.rb` (`url` and `sha256`):

   ```bash
   curl -fsSL https://github.com/SteveVitali/claude-as/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
   ```

6. Copy `Formula/claude-as.rb` into `SteveVitali/homebrew-tap` (`Formula/`), commit
   and push it, then check:

   ```bash
   brew update && brew upgrade claude-as || brew install SteveVitali/tap/claude-as
   brew test claude-as && claude-as --version
   ```

## Install channels

- **Homebrew:** the formula pins the release tag. Update it as described above.
- **curl installer:** `install.sh` always installs from `main`.
- **Manual:** `bin/claude-as` can be copied anywhere on `PATH`. It has no
  repo-relative dependencies.
