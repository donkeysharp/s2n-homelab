# k8s-manifests

Plain Kubernetes manifests for the S2N homelab k3s cluster. No Kustomize, Helm,
or Argo CD yet — everything is applied directly with `kubectl apply -f`.

## Layout

```
cluster/   Cluster-wide resources not tied to a single app
           (ingress for external services, namespaces, issuers later)
apps/      One directory per service; files named by kind
  hello-world/
    deployment.yaml
    service.yaml
    ingress.yaml
```

Each app directory holds the manifests for exactly one service, one file per
kind. The directory name is the service name, so files are just `deployment.yaml`,
`service.yaml`, etc.

## Applying

```bash
# One service
kubectl apply -f apps/hello-world/

# All services
kubectl apply -f apps/ --recursive

# Cluster-wide resources
kubectl apply -f cluster/ --recursive
```

## cert-manager

TLS certificates from Let's Encrypt using the DNS-01 challenge against
DigitalOcean DNS. DNS-01 is the right fit here: nothing in the homelab is
reachable from the internet, and it is the only challenge type that can issue
wildcards. The DigitalOcean solver is built into cert-manager, no webhook needed.

Manifests live in `cluster/cert-manager/`.

### Prerequisites

1. `s2n.donkeysharp.xyz` served by DigitalOcean DNS. If the parent zone lives
   elsewhere, delegate the subdomain with `NS` records pointing at
   `ns1.digitalocean.com` / `ns2` / `ns3`, then create the zone in DigitalOcean.
2. A DigitalOcean personal access token with write scope
   (<https://cloud.digitalocean.com/account/api/tokens/new>).

### Install

```bash
# cert-manager itself, through the k3s built-in helm-controller
kubectl apply -f cluster/cert-manager/helmchart.yaml
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=5m

# DigitalOcean token, created by hand -- never committed
kubectl -n cert-manager create secret generic digitalocean-dns \
  --from-literal=access-token='<DO_API_TOKEN>'

kubectl apply -f cluster/cert-manager/clusterissuer-staging.yaml
kubectl apply -f cluster/cert-manager/clusterissuer-prod.yaml
kubectl get clusterissuer   # both should report READY=True
```

The token secret must live in the `cert-manager` namespace. A `ClusterIssuer`
resolves `tokenSecretRef` against the cluster resource namespace, not against the
namespace of the `Certificate` using it.

### Staging vs prod

`letsencrypt-staging` uses Let's Encrypt's test endpoint: browsers reject the
chain, but rate limits are loose. `letsencrypt-prod` is capped at 50 certificates
per registered domain per week and failed orders count against it. Validate on
staging, then switch the issuer to prod and delete the old secret so the
certificate is re-issued.

### Issuing a certificate

Either apply `wildcard-certificate.yaml` for a shared `*.s2n.donkeysharp.xyz`
cert, or let cert-manager issue per-host from an Ingress:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
spec:
  tls:
    - hosts:
        - pad.s2n.donkeysharp.xyz
      secretName: hedgedoc-tls
```

`Certificate` is namespaced and the resulting secret cannot be shared across
namespaces, so the wildcard has to be duplicated per namespace that needs it.

### Troubleshooting

```bash
kubectl get certificate,certificaterequest,order,challenge -A
kubectl describe challenge -A
kubectl -n cert-manager logs deploy/cert-manager -f
```

Propagation of the `_acme-challenge` TXT record usually takes a couple of
minutes, so a challenge briefly stuck in `pending` is normal. The chart sets
`dns01RecursiveNameserversOnly` so the self-check queries 1.1.1.1 directly rather
than the OpenWrt resolver, which only knows the `.lan` view and would never see
the record.

## Longhorn

Distributed block storage, installed through the k3s helm-controller. Manifests
live in `cluster/longhorn/`.

### Prerequisites

Longhorn's V1 data engine needs packages on the host that no manifest can
install — `open-iscsi` (with `iscsid` running), `cryptsetup` and `dmsetup`. Run
the Ansible role first:

```bash
ansible-playbook playbooks/longhorn.yml
```

### Install

```bash
kubectl apply -f cluster/longhorn/helmchart.yaml
kubectl -n longhorn-system rollout status daemonset/longhorn-manager --timeout=10m

kubectl apply -f cluster/longhorn/certificate.yaml
kubectl apply -f cluster/longhorn/ingress.yaml
```

Add an `lh.s2n.donkeysharp.xyz` host entry on OpenWrt pointing at any node IP.
**Do not** add that record to the DigitalOcean zone: the Longhorn UI has no
authentication and can delete every volume in the cluster, and palantir's
HAProxy would forward it straight to the internet.

### Storage class

`local-path` stays the cluster default. Longhorn volumes are opt-in, so PVCs
have to name it:

```yaml
spec:
  storageClassName: longhorn
```

### Backups

Not configured. Uncomment `backupTarget` / `backupTargetCredentialSecret` in
`helmchart.yaml` and create the credentials in `longhorn-system`:

```bash
kubectl -n longhorn-system create secret generic longhorn-backup-secret \
  --from-literal=AWS_ACCESS_KEY_ID='<KEY>' \
  --from-literal=AWS_SECRET_ACCESS_KEY='<SECRET>' \
  --from-literal=AWS_ENDPOINTS='https://<endpoint>'   # only for S3-compatible
```

`AWS_ENDPOINTS` is what points this at a non-AWS provider (DigitalOcean Spaces,
Backblaze B2, MinIO). Leave it out for real S3.

### Notes

- Deleting the `HelmChart` resource uninstalls Longhorn and takes the volumes
  with it. `spec.failurePolicy: abort` keeps a failed install from doing the
  same thing on its own.
- Node selectors have to be set at install time. Changing them later restarts
  every Longhorn component and only fully applies with all volumes detached.
- `multipath-tools` on a node breaks volume attachment — it claims the block
  devices first. The role fails the run if it finds it.

## Actual Budget

Self-hosted budgeting at `ab.s2n.donkeysharp.xyz`. Manifests live in
`apps/actual-budget/`. Two things make it different from the other apps here.

**It is the first Longhorn consumer.** The PVC names `storageClassName: longhorn`
and is `ReadWriteOnce`. Actual keeps its state in SQLite and only one process may
hold it, so the Deployment is `replicas: 1` with `strategy: Recreate` — a
RollingUpdate would deadlock on every image bump, with the new pod waiting for a
volume the old pod still has attached. Any single-writer app added here needs the
same pair.

**It is the first deliberately public app.** Unlike the Longhorn UI, `ab` gets an
A record in the DigitalOcean zone pointing at palantir, so it resolves from the
internet and reaches Traefik over the tunnel. No HAProxy change is needed —
`roles/l4_proxy` is a host-agnostic TCP forward, so publishing a new hostname is
only ever a DNS decision.

```bash
kubectl apply -f apps/actual-budget/
kubectl rollout status deploy/actual-budget
```

The shared wildcard certificate already covers the host and its secret lives in
`default`, so no per-app `Certificate` is needed.

### Authentication

Google OIDC. The `ACTUAL_OPENID_*` values live in `secret.yaml`, committed fully
commented out — fill it in and apply by hand. The server bootstraps OpenID on
startup whenever it finds a discovery URL, so `enable-openid.js` never has to be
run. Register `https://ab.s2n.donkeysharp.xyz/openid/callback` as the redirect URI
in Google Cloud, and leave the OAuth app's audience on *Testing* with the
household Gmail addresses as test users — Google then refuses anyone unlisted
before Actual is even consulted.

**Never set `ACTUAL_USER_CREATION_MODE=login`.** It defaults to `manual`, and that
default is what makes Actual reject any Google identity that is not already a
user. Every Google account on the internet can authenticate successfully, so
`manual` is the only thing between the public URL and the budget. Add people by
hand in the User Directory, keyed on their Gmail address — Actual derives the
username from the `email` claim.

`ACTUAL_TOKEN_EXPIRATION` accepts `never`, `openid-provider`, or a number of
seconds. Avoid `openid-provider`: it pins the session to Google's short-lived
access token, which Actual never refreshes, so it logs you out roughly hourly. A
plain number (`604800` for a week) bounds the session without the churn. The value
is written into the session row at login, so changing it only affects new logins.

The password set at first bootstrap remains the fallback login method. Keep it —
`kubectl exec -it deploy/actual-budget -- node scripts/disable-openid.js` prompts
for it to turn OIDC back off.

Longhorn backups are still unconfigured, which means this volume is the one place
in the cluster where the "rebuild if it dies" stance costs real data. Actual's
built-in file export covers it without setting up a backup target.

## Notes

- `hello-world` is an http-echo deployment used to validate Traefik ingress.
  Reach it at `hello-world.local` (point the host at any node IP via OpenWrt DNS,
  a client `/etc/hosts`, or a `Host:` header).
- `cluster/argocd-ingress.yaml` is a Traefik `IngressRoute` for an Argo CD server
  running outside this repo; see the comments in that file for prerequisites.
