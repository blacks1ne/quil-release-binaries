Unofficial node and qclient builds of upstream's default branch at commit <bump-sha>, made because the official release listing changed without a new version. Upstream does not name the commit behind the official binaries, so these are not rebuilds of them: they are the branch's newest commit, at the listed version, when the change was seen. Built with the project's `node/build.sh` on GitHub-hosted runners (<run-url>); nothing is added to the source.

Assets: `node-<version>-linux-amd64`, `node-<version>-darwin-arm64`, `qclient-<version>-linux-amd64` and `qclient-<version>-darwin-arm64`, each with a `.sha256` file. Verify before use: `sha256sum -c <asset>.sha256` on Linux, `shasum -a 256 -c <asset>.sha256` on macOS.

The macOS binaries are not signed or notarized; after verifying one, clear its quarantine flag with `xattr -d com.apple.quarantine <asset>`.
