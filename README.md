# Quilibrium node and qclient builds

Unofficial `node` and `qclient` binaries for each new Quilibrium release, published until the official release listings catch up. Latest: https://github.com/blacks1ne/quil-release-binaries/releases/latest

## How they are built

A GitHub Actions workflow checks the `v2.1.0.25` release branch of [QuilibriumNetwork/monorepo](https://github.com/QuilibriumNetwork/monorepo) every 15 minutes (GitHub runs scheduled workflows on a best-effort basis, so a build may start later) and also runs when a new bump lands. When a new `bump subpatch` commit appears, it builds `node` and `qclient` for linux-amd64 and darwin-arm64 from that exact commit with the project's own `node/build.sh`, checks each binary's `--version`, and publishes a release. Nothing is added to the source. Each release names its bump commit and links its workflow run; `released.txt` lists every published version.

## Verify before use

Each asset has a `.sha256` file:

- Linux: `sha256sum -c <asset>.sha256`
- macOS: `shasum -a 256 -c <asset>.sha256`

The macOS binaries are not signed or notarized. After verifying one, clear its quarantine flag with `xattr -d com.apple.quarantine <asset>`.

## Support

These builds are not affiliated with or endorsed by Quilibrium. Report build problems in this repository's issues; node and protocol issues belong in the monorepo.
