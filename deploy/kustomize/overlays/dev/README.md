# Dev overlay

The maintainer's own deployment: a single-node k3s cluster reached over
Tailscale Serve. It's kept here as a working example of
`deploy/kustomize/base`. Copy it and change the values for your own server
(see [Self-hosting](../../../../readme.md#self-hosting)).

What to change in a copy:

- `kustomization.yaml`: `APP_BASE_URL` (your public address) and the image
  owner if you publish your own images.
- `pod-spec.yaml`, `postgres.yaml`, `nightly-updater.yaml`: the
  `kubernetes.io/hostname` node selector (or remove it).
- Secret `app-217-secrets` with at least `DATABASE_URL`, plus `WORKOS_CLIENT_ID`
  and `WORKOS_API_KEY`.

## Images

The overlay tracks the rolling GHCR tags published by `main` CI:

- `ghcr.io/jobucaldas/app-217-backend:nightly`
- `ghcr.io/jobucaldas/app-217-frontend:nightly`

CI also publishes `:dev` and immutable `YYYYMMDDHHMMSS_<shortsha>` tags; the
overlay uses `:nightly` with `imagePullPolicy: Always`.

A CronJob (`app-217-nightly-updater`, every 15 minutes) compares the GHCR
manifest digest for `:nightly` against the running pods and runs
`kubectl rollout restart` only when the digest moved.

## Prerequisites (one-time)

1. Namespace `app-217-dev` (also created by this overlay).
2. Secret `app-217-secrets` (see above).
3. In-cluster Postgres matching `DATABASE_URL` (see `postgres.yaml`).
4. A GHCR pull secret, only if your packages are private:

```bash
kubectl -n app-217-dev create secret docker-registry app-217-ghcr \
  --docker-server=ghcr.io \
  --docker-username=<github-user> \
  --docker-password="$(gh auth token)"
```

The token needs at least `read:packages`. Re-create it when the token rotates.

## Render / apply

```bash
kubectl kustomize deploy/kustomize/overlays/dev
kubectl apply -k deploy/kustomize/overlays/dev
```

Force an immediate digest check:

```bash
kubectl -n app-217-dev create job --from=cronjob/app-217-nightly-updater \
  "app-217-nightly-updater-manual-$(date +%s)"
```
