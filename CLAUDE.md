# Working on ConvertAll

Only Claude works on this repo. For every change:

1. Develop on the session's feature branch.
2. Bump the version: `scripts/bump-version.sh` (patch by default; `minor`/`major` for bigger changes).
   CI fails a PR whose version is already released.
3. Open a PR to `main`, wait for CI (macOS build + tests, Linux core tests) to pass, then merge it (squash).
4. The merge to `main` automatically publishes a GitHub Release `v<version>` with `ConvertAll-<version>.zip`
   (`.github/workflows/build.yml`, `release` job). Confirm it was published.

Useful commands: `swift test`, `scripts/build-app.sh [--install]`, `python3 scripts/make-icon.py`.
