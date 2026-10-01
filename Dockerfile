# syntax=docker/dockerfile:1.7

# Railway-compatible OpenClaw build. This intentionally avoids BuildKit mount
# directives that Railway's Dockerfile validator rejects.

FROM oven/bun:1.4.2 AS bun

FROM node:24-bookworm AS build
WORKDIR /app

RUN corepack enable \
  && apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    python3 make g++ git ca-certificates openssh-client \
  && rm -rf /var/lib/apt/lists/*

COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
COPY . .

RUN pnpm install --frozen-lockfile

ARG OPENCLAW_DOCKER_BUILD_NODE_OPTIONS="--max-old-space-size=4096"
ARG OPENCLAW_DOCKER_BUILD_TSDOWN_MAX_OLD_SPACE_MB=""
ARG OPENCLAW_DOCKER_BUILD_SKIP_DTS=1
ARG OPENCLAW_BUILD_TIMESTAMP=""
ARG OPENCLAW_DOCKER_BUILD_VERSION=""
ARG GIT_COMMIT=""

ENV OPENCLAW_PREFER_PNPM=1 \
    OPENCLAW_RUN_NODE_SKIP_DTS_BUILD=${OPENCLAW_DOCKER_BUILD_SKIP_DTS} \
    OPENCLAW_TSDOWN_MAX_OLD_SPACE_MB=${OPENCLAW_DOCKER_BUILD_TSDOWN_MAX_OLD_SPACE_MB} \
    GIT_COMMIT=${GIT_COMMIT} \
    OPENCLAW_BUILD_TIMESTAMP=${OPENCLAW_BUILD_TIMESTAMP}

RUN set -eu; \
    if [ -n "$OPENCLAW_DOCKER_BUILD_VERSION" ]; then pnpm pkg set "version=$OPENCLAW_DOCKER_BUILD_VERSION"; fi; \
    if [ -z "$OPENCLAW_BUILD_TIMESTAMP" ]; then export OPENCLAW_BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi; \
    NODE_OPTIONS="$OPENCLAW_DOCKER_BUILD_NODE_OPTIONS" pnpm_config_verify_deps_before_run=false pnpm build:docker; \
    pnpm_config_verify_deps_before_run=false pnpm ui:build

FROM node:24-bookworm-slim AS runtime
WORKDIR /app

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl git hostname libgomp1 lsof openssh-client openssl procps python3 tini \
  && update-ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /app /app

RUN chown -R node:node /app \
  && install -d -m 0755 -o node -g node /home/node/.config \
  && install -d -m 0700 -o node -g node \
    /home/node/.openclaw \
    /home/node/.openclaw/workspace \
    /home/node/.config/openclaw

ENV NODE_ENV=production
USER node

ENTRYPOINT ["tini", "-s", "--"]
CMD ["sh", "-lc", "node openclaw.mjs gateway --bind lan --port ${PORT:-18789}"]
