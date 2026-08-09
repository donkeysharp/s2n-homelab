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

## Notes

- `hello-world` is an http-echo deployment used to validate Traefik ingress.
  Reach it at `hello-world.local` (point the host at any node IP via OpenWrt DNS,
  a client `/etc/hosts`, or a `Host:` header).
- `cluster/argocd-ingress.yaml` is a Traefik `IngressRoute` for an Argo CD server
  running outside this repo; see the comments in that file for prerequisites.
