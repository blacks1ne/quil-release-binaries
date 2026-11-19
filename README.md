# Quilibrium node and qclient builds

Unofficial `node` and `qclient` binaries for each new Quilibrium release, published until the official release listings catch up. Latest: https://github.com/blacks1ne/quil-release-binaries/releases/latest

## How they are built

A GitHub Actions workflow checks the default branch of [QuilibriumNetwork/monorepo](https://github.com/QuilibriumNetwork/monorepo) every 15 minutes (GitHub runs scheduled workflows on a best-effort basis, so a build may start later) and also runs when a new bump lands. When a commit changes the version (`subpatch` or `VERSION_STRING`), it builds `node` and `qclient` for linux-amd64 and darwin-arm64 from that exact commit with the project's own `node/build.sh`, checks each binary's `--version`, and publishes a release. Nothing is added to the source. Each release names its bump commit and links its workflow run; `released.txt` lists every published version.

The workflow also reads the official release listing and keeps each listed file's SHA3-256 digest in `public.txt`. When the digests change without a new version (the official binaries were rebuilt in place), it builds the default branch's newest commit if that commit is at the listed version and not yet released, and publishes it as `v<version>-<commit>` with the official digests in its notes. Upstream does not name the commit behind the official binaries, so these builds are not rebuilds of them. If the newest commit is at another version, nothing is built and the run fails once, as a notice.

## Verify before use

Each asset has a `.sha256` file:

- Linux: `sha256sum -c <asset>.sha256`
- macOS: `shasum -a 256 -c <asset>.sha256`

The macOS binaries are not signed or notarized. After verifying one, clear its quarantine flag with `xattr -d com.apple.quarantine <asset>`.

## Support

These builds are not affiliated with or endorsed by Quilibrium. Report build problems in this repository's issues; node and protocol issues belong in the monorepo.
