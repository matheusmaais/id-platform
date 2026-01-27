# ============================================================================
# Backstage Custom Image with OIDC Support
# Multi-stage build for minimal runtime image
# ============================================================================

# Stage 1: Builder
FROM node:20-bookworm-slim AS builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 \
    g++ \
    build-essential \
    git \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy package files
COPY package.json yarn.lock* ./
COPY packages/backend/package.json ./packages/backend/

# Install dependencies
RUN yarn install --network-timeout 600000

# Copy source code
COPY packages/backend/src ./packages/backend/src
COPY packages/backend/tsconfig.json ./packages/backend/

# Build backend
RUN yarn workspace backend build

# ============================================================================
# Stage 2: Runtime
FROM node:20-bookworm-slim

# Install runtime dependencies only
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user (use existing node user from base image)
RUN mkdir -p /app && \
    chown -R node:node /app

# Set working directory
WORKDIR /app

# Copy built artifacts from builder
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/packages/backend/dist ./packages/backend/dist
COPY --from=builder --chown=node:node /app/packages/backend/package.json ./packages/backend/

# Switch to non-root user
USER node

# Expose backend port
EXPOSE 7007

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:7007/healthcheck || exit 1

# Extract bundle and start backend
CMD ["sh", "-c", "tar -xzf packages/backend/dist/bundle.tar.gz && node packages/backend/dist/index.cjs.js"]
