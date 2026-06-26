# Throwaway image to verify Kata Flight installs as documented, via the real
# Claude Code and Codex CLIs, in a clean environment. No host state is touched.
#
# Build/run from the repo root:
#   docker build -t kata-flight-installtest test/install
#   docker run --rm kata-flight-installtest
#
# See test/install/README.md for what it does and does not cover.
FROM node:22-slim

# git: needed for `claude plugin marketplace add <github-repo>` and for cloning.
# ca-certificates: TLS for the GitHub fetch.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# The two agent CLIs from npm. Pin to a known-good pair; fall back to latest.
ARG CLAUDE_VERSION=2.1.193
ARG CODEX_VERSION=0.142.2
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_VERSION}" "@openai/codex@${CODEX_VERSION}" \
 || npm install -g @anthropic-ai/claude-code @openai/codex

# Non-root home so CLI config writes somewhere sane and isolated.
ENV HOME=/root
WORKDIR /work

COPY run.sh /usr/local/bin/run-install-test.sh
RUN chmod +x /usr/local/bin/run-install-test.sh

ENTRYPOINT ["/usr/local/bin/run-install-test.sh"]
