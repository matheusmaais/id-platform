# Multi-stage build for Backstage backend (hardened runtime)
# - Builds the backend bundle + production node_modules in a builder stage
# - Final image runs as non-root `node` and contains only runtime deps + bundle
#
# Build context MUST be repo root (backstage-custom/).

FROM node:24-trixie-slim AS builder

# Set Python interpreter for `node-gyp` to use
ENV PYTHON=/usr/bin/python3

# Build dependencies (native modules: isolated-vm, better-sqlite3, etc.)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends python3 g++ build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy minimal files first for better docker layer caching
COPY package.json yarn.lock backstage.json .yarnrc.yml ./
COPY .yarn ./.yarn
COPY packages/app/package.json ./packages/app/
COPY packages/backend/package.json ./packages/backend/
COPY examples/template/content/package.json ./examples/template/content/

# Install deps deterministically (uses yarnPath from .yarnrc.yml)
RUN --mount=type=cache,target=/root/.cache/yarn,sharing=locked \
    corepack enable && \
    yarn install --immutable

# Copy sources and configs required for build
COPY tsconfig.json ./
COPY playwright.config.ts ./
COPY app-config*.yaml ./
COPY packages ./packages
COPY examples ./examples

# Build TypeScript + backend bundle (also builds the frontend bundle as needed)
RUN yarn tsc && yarn build:backend

# Prepare runtime filesystem (bundle + production deps only)
RUN mkdir -p /app-runtime
RUN tar xzf packages/backend/dist/skeleton.tar.gz -C /app-runtime
RUN cp package.json yarn.lock backstage.json .yarnrc.yml -t /app-runtime
RUN cp -r .yarn /app-runtime/.yarn

RUN --mount=type=cache,target=/root/.cache/yarn,sharing=locked \
    cd /app-runtime && \
    corepack enable && \
    yarn workspaces focus --all --production && \
    rm -rf "$(yarn cache clean)"

RUN cp -r examples /app-runtime/examples
RUN tar xzf packages/backend/dist/bundle.tar.gz -C /app-runtime
RUN cp app-config*.yaml /app-runtime/

FROM node:24-trixie-slim AS runtime

# Runtime deps only (sqlite runtime library + TLS)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates libsqlite3-0 && \
    rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production
ENV NODE_OPTIONS="--no-node-snapshot"

USER node
WORKDIR /app

COPY --from=builder --chown=node:node /app-runtime/ /app/

EXPOSE 7007
CMD ["node", "packages/backend", "--config", "app-config.yaml"]
