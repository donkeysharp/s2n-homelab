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

Manifests live in `cluster/cert-manager/draft/`.

### Prerequisites

1. `s2n.donkeysharp.xyz` served by DigitalOcean DNS. If the parent zone lives
   elsewhere, delegate the subdomain with `NS` records pointing at
   `ns1.digitalocean.com` / `ns2` / `ns3`, then create the zone in DigitalOcean.
2. A DigitalOcean personal access token with write scope
   (<https://cloud.digitalocean.com/account/api/tokens/new>).

### Install

```bash
# cert-manager itself, through the k3s built-in helm-controller
kubectl apply -f cluster/cert-manager/draft/helmchart.yaml
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=5m

# DigitalOcean token, created by hand -- never committed
kubectl -n cert-manager create secret generic digitalocean-dns \
  --from-literal=access-token='<DO_API_TOKEN>'

kubectl apply -f cluster/cert-manager/draft/clusterissuer-staging.yaml
kubectl apply -f cluster/cert-manager/draft/clusterissuer-prod.yaml
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

## Notes

- `hello-world` is an http-echo deployment used to validate Traefik ingress.
  Reach it at `hello-world.local` (point the host at any node IP via OpenWrt DNS,
  a client `/etc/hosts`, or a `Host:` header).
- `cluster/argocd-ingress.yaml` is a Traefik `IngressRoute` for an Argo CD server
  running outside this repo; see the comments in that file for prerequisites.
