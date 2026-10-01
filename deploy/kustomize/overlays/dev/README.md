# Dev overlay (home-lab / Serve)

CI/dev target for the private home-lab cluster on Proxmox `app-node`.
Day-to-day access is Tailscale Serve from encom (see Project
`docs/roomies-parity-plan.md`).

## Images

Serve tracks the rolling GHCR tags published by main CI:

- `ghcr.io/jobucaldas/app-217-backend:nightly`
- `ghcr.io/jobucaldas/app-217-frontend:nightly`

CI also publishes `:dev` and immutable `YYYYMMDDHHMMSS_<shortsha>` tags; Serve
uses `:nightly` with `imagePullPolicy: Always`.

A CronJob (`app-217-nightly-updater`, every 15 minutes) compares the GHCR
manifest digest for `:nightly` against the running pods and runs
`kubectl rollout restart` only when the digest moved.

## Prerequisites (one-time)

1. Namespace `app-217-dev` (also created by this overlay).
2. Secret `app-217-secrets` with at least `DATABASE_URL`.
3. In-cluster Postgres matching that URL (see `postgres.yaml`).
4. GHCR pull secret (packages are private):

```bash
kubectl -n app-217-dev create secret docker-registry app-217-ghcr \
  --docker-server=ghcr.io \
  --docker-username=jobucaldas \
  --docker-password="$(gh auth token)" \
  --docker-email=jobucaldas@users.noreply.github.com
```

Token needs at least `read:packages`. Re-create when the token rotates.

## Render / apply

```bash
kubectl kustomize deploy/kustomize/overlays/dev
kubectl --context home-lab apply -k deploy/kustomize/overlays/dev
```

Force an immediate digest check:

```bash
kubectl -n app-217-dev create job --from=cronjob/app-217-nightly-updater \
  "app-217-nightly-updater-manual-$(date +%s)"
```
