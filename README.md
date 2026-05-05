# frontman-selfhost

Self-hosted Frontman release image and Kubernetes deployment wiring for the
Glimmung test environment.

The image intentionally builds from the latest upstream `frontman-ai/frontman`
default branch on each build. CI applies the local Entra auth patch, builds a
Phoenix release image, publishes it to GHCR, and updates `k8s/server.yaml` to
roll ArgoCD onto the new immutable image tag.

## Rollout

- Pushes to `main` that touch the Dockerfile, patches, or workflow build and
  publish a new image.
- A scheduled workflow refreshes from latest upstream Frontman.
- The workflow writes the produced image tag back into the Kubernetes
  deployment manifest, which ArgoCD then syncs.
