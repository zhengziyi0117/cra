# Maintaining the Cra fork

Keep personal changes on `fork-release` in `zhengziyi0117/cra`. The fork’s `main` branch mirrors `VictorKildahl/cra:main`. **Sync upstream main** fast-forwards that mirror every Monday at 04:17 Asia/Shanghai and can also run on demand. If the histories diverge, inspect the commits before updating the mirror.

## Before each update

Check the latest published upstream application release. Run these commands from the fork branch in a clean worktree. Exit status 0 on the last command means the release is already included. Status 1 means it needs merging.

```bash
tag=$(gh api repos/VictorKildahl/cra/releases/latest --jq '.tag_name')
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
git fetch --no-tags upstream "refs/tags/$tag" &&
  git merge-base --is-ancestor 'FETCH_HEAD^{commit}' HEAD
```

When updating the fork, manually merge the chosen upstream release into `fork-release` if it is missing. Preserve the fork’s GitHub Actions workflows, Apple silicon packaging, Sparkle update URLs and signing configuration. Resolve source conflicts with the fork’s features in mind.

For an explicitly requested release, run **Publish fork release** on `fork-release`. It tags the selected fork commit using the latest upstream application release in its history, then queues the signed Sparkle update for both channels.

## Validation

For code, dependency or packaging changes, build and package once on Apple silicon:

```bash
scripts/build.sh debug && scripts/package.sh
```

This produces `build/dist/Cra.zip`, `Cra.dmg` and `SHA256SUMS.txt`. A successful package is the routine acceptance check locally and in CI. For documentation-only edits, review the diff. Run additional tests only when the user requests them. Release builds retain their signing and Sparkle archive verification.
