# Dev overlay (home-lab)

CI/dev target for the private home-lab cluster on Proxmox `app-node`.

Day-to-day access is Tailscale Serve from encom (see Project
`docs/roomies-parity-plan.md`), not the Cloudflare Ingress host.

## Prerequisites (one-time)

1. Namespace `app-217-dev` (also created by this overlay).
2. Secret `app-217-secrets` with at least `DATABASE_URL`.
3. In-cluster Postgres matching that URL (see `deploy/kustomize/overlays/dev/postgres.yaml`).
4. Images `ghcr.io/jobucaldas/app-217-{backend,frontend}:dev` (or `:nightly`) present
   on the node. On every `main` push, CI publishes both tags to GHCR plus an immutable
   `YYYYMMDDHHMMSS_<shortsha>` tag. Local `podman build` + `k3s ctr images import` is
   still fine for one-off tryouts.

## Render / apply

```bash
kubectl kustomize deploy/kustomize/overlays/dev
kubectl --context home-lab apply -k deploy/kustomize/overlays/dev
```
