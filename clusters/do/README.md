# clusters/do

Self-managing bootstrap cluster on DigitalOcean (DOKS), joined to the home
cluster over Tailscale. Each cluster runs its own Argo CD; neither depends on
the other to reconcile.

## Bootstrap

1. `infra/do`: `tofu apply`, then `doctl kubernetes cluster kubeconfig save bootstrap-do`.
2. Tailnet: land the policy changes from
   `docs/do-cluster-and-repo-consolidation.md` (new `tag:do`, route
   auto-approval for `10.44.0.0/16`), and create an OAuth client for the DO
   operator.
3. Secrets the operator and Argo need, created by hand once (same pattern as
   the home 1Password bootstrap in the root README):
   ```bash
   kubectl create namespace tailscale
   kubectl create secret generic operator-oauth -n tailscale \
     --from-literal=client_id="$(op read 'op://<vault>/<item>/client_id')" \
     --from-literal=client_secret="$(op read 'op://<vault>/<item>/client_secret')"
   ```
   1Password Connect credentials: repeat the root README steps with a separate
   Connect server/token for this cluster.
4. Argo CD, then the AppSet:
   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm install --create-namespace -n argocd --version 10.11.6 argocd argo/argo-cd \
     --values clusters/do/apps-helm/argocd/values.yaml
   kubectl apply --server-side -f clusters/do/bootstrap/apps-helm.yaml
   ```
   Argo then adopts itself via the `do-argocd` Application.

## Address plan

| Range | Owner |
|---|---|
| `10.43.16.0/20` pods, `10.43.32.0/20` services, `10.43.64.0/24` LB | home |
| `10.44.0.0/20` VPC, `10.44.16.0/20` pods, `10.44.32.0/20` services | DO |

Do not reuse home ranges: Tailscale routes would collide.

## Notes

- DOKS manages Cilium; don't install it from this repo.
- Expose services over the tailnet, not DO LoadBalancers.
- Nothing in the home boot path should require this cluster.
