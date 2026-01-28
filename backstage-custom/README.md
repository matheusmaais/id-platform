# [Backstage](https://backstage.io)

This is the platform Backstage app, regenerated deterministically and pinned to the latest stable Backstage OSS release.

## Local development / validation (deterministic)

This repo uses Yarn 4 via Corepack.

```sh
cd backstage-custom
corepack enable

# First run may update yarn.lock seed (if regenerated)
YARN_ENABLE_IMMUTABLE_INSTALLS=false corepack yarn install

# Enforce lockfile determinism
corepack yarn install --immutable

# Validate + build
corepack yarn lint:all
corepack yarn tsc
corepack yarn build:backend
```

## Docker (ARM64 hardened image)

The Dockerfile is multi-stage, runs as non-root, and targets ARM64 for Graviton/t4g nodes.

```sh
cd backstage-custom
docker buildx build --platform linux/arm64 \
  -f packages/backend/Dockerfile \
  -t backstage-platform:local --load .

docker run -d --rm -p 7007:7007 --name backstage-local backstage-platform:local
sleep 8
curl -fsS http://localhost:7007/healthcheck
docker rm -f backstage-local
```

## Cluster deploy (GitOps)

The Helm values live in `platform-apps/backstage/values.yaml` (image tag is pinned; no `latest`).

Typical flow:
```sh
make validate-backstage
make build-backstage-image
make push-backstage-image

# Then sync in ArgoCD and watch rollout:
# argocd app sync backstage
# kubectl logs -n backstage deploy/backstage -f
```
