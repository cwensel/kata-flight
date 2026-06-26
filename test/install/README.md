# Install smoke test

Verifies that Kata Flight installs **as documented in the root README**, using
the real Claude Code and Codex CLIs, inside a throwaway Docker container. It
touches no host state — your `~/.claude`, `~/.codex`, and local skill links are
untouched.

## Run

From the repo root:

```sh
docker build -t kata-flight-installtest test/install
docker run --rm kata-flight-installtest
```

Needs network (it fetches the GitHub marketplace and clones the repo). Exit code
is `0` when every check passes, non-zero otherwise.

Test a fork or branch's published repo with `KF_REPO`:

```sh
docker run --rm -e KF_REPO=youruser/kata-flight kata-flight-installtest
```

Pin different CLI versions at build time:

```sh
docker build -t kata-flight-installtest \
  --build-arg CLAUDE_VERSION=2.1.193 --build-arg CODEX_VERSION=0.142.2 \
  test/install
```

## What it checks

- **Claude** — `plugin marketplace add <repo>`, `plugin install
  kata-flight@kata-flight`, `plugin list` shows it enabled at the expected
  version, and `plugin validate` accepts the manifest.
- **Codex** — `plugin marketplace add <path>` resolves the `.agents` marketplace
  and the `plugins/kata-flight` symlink, `plugin list` shows it, and `plugin
  add` installs it.
- **Symlink contract** — in a fresh `git clone`,
  `plugins/kata-flight/.codex-plugin/plugin.json` resolves (i.e. git stored the
  `plugins/kata-flight -> ..` symlink and it rehydrates on clone).

## What it does NOT check

This confirms **installability and the marketplace/manifest/symlink wiring** —
not the runtime behavior of the skills. Exercising the skills needs model auth
plus the `kata` and `roborev` binaries, which are out of scope for a credential-
free container smoke test.
