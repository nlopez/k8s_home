# DOKS cluster and repo consolidation

## 1. Tailnet policy changes (nlopez/tailnet, `policy.hujson`)

Not applied; the tailnet repo's `gitops-acl-action` would apply them on merge.
Review, add tests, then PR there.

```jsonc
"tagOwners": {
  // location tag for the DO cluster, mirroring tag:lga1
  "tag:do": ["autogroup:admin", "tag:k8s-operator"],
},
"autoApprovers": {
  "routes": {
    // DO VPC + pod + service ranges (only needed if you run a subnet router there)
    "10.44.0.0/16": ["tag:do", "tag:k8s-operator"],
  },
},
"ipsets": {
  "ipset:do": ["10.44.0.0/16"],
},
"grants": [
  // home <-> DO, any port. Narrow this to specific ports once you know them.
  { "src": ["tag:home"], "dst": ["tag:do", "ipset:do"], "ip": ["*"] },
  { "src": ["tag:do"], "dst": ["tag:home"], "ip": ["*"] },
],
// ssh.dst: add "tag:do"
```

A second operator can reuse `tag:k8s-operator` for its OAuth client. Note
`ipset:lga1` already contains `10.43.0.0/16`, so `10.44.0.0/16` stays disjoint.

## 2. Bootstrap services to move to DO (candidates)

Things home must not depend on itself for: secondary DNS (pairs with the `dns`
repo and Technitium), external alerting/dead-man's switch, OpenBao/Vault,
OIDC, Velero (storage already in DO Spaces), registry cache.

## 3. Repo consolidation

Recommendation: keep `k8s_home` as the cluster repo (now with `clusters/do` and
`infra/do`), keep `dotfiles` separate, and merge `dns`, `tailnet`, and
`ansible_home` into one `infra` repo. This session could not create a new
repository, so the merge is a plan only.

Suggested layout:

```
infra/
  dns/        # dnscontrol, devenv.nix
  tailnet/    # policy.hujson
  ansible/    # ansible_home contents
  do/         # could move here from k8s_home/infra/do
  .github/workflows/{dns,tailnet,ansible,tofu}.yml   # path-filtered
```

Steps, per source repo:

```bash
git clone git@github.com:nlopez/dns.git && cd dns
git filter-repo --to-subdirectory-filter dns
cd ../infra && git remote add dns ../dns && git fetch dns
git merge --allow-unrelated-histories dns/main
```

CI notes:

- Each workflow gets `paths:` filters so a DNS change doesn't run the tailnet job.
- Keep `dns` pushing from a `production` environment with its Cloudflare
  secrets scoped to that environment.
- `tailnet` needs its Tailscale OAuth/API credentials; `tofu` needs a DO token
  and Spaces keys. Scope each to its own environment, not repo-wide.
- Check `dns/creds.json` contains only env-var references, not a token.
- dns uses devenv/nix, ansible uses uv: keep a per-directory env at first.
