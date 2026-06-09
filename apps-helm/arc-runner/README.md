# GitHub Actions Runner — ARC (Actions Runner Controller)

Self-hosted GitHub Actions runners managed via Argo CD, using the
[Actions Runner Controller (ARC)](https://github.com/actions/actions-runner-controller).

## Architecture

| Component | Namespace | Argo App | Sync Wave |
|---|---|---|---|
| ARC controller | `actions-runner-controller` | `arc-controller` | 0 |
| Runner secrets | `arc-runners` | `arc-runner` | 1 |
| Runner pods | `arc-runners` | `arc-runner` | 1 |

## Prerequisites

### 1. GitHub App

1. Create a GitHub App at https://github.com/settings/apps/new
2. **Name**: `k8s-home-arc-runner`
3. **Homepage URL**: `https://github.com/actions/actions-runner-controller`
4. **Permissions**:
   - Administration: **Read and write**
   - Metadata: **Read only**
5. Install on your account
6. Generate a private key → download the `.pem` file
7. Record the **App ID** and **Installation ID**

### 2. 1Password Item

Create an API Credential item in the `k8s_home` vault with these fields:

| Label | Type | Description |
|---|---|---|
| `username` | STRING | `k8s-home-arc-runner` |
| `github_app_id` | STRING | The GitHub App ID (e.g. `4008464`) |
| `github_app_installation_id` | STRING | The GitHub App Installation ID (e.g. `139118321`) |
| `github_app_private_key` | CONCEALED | The PEM private key (from step 6 above) |

Command:
```bash
PEM_KEY=$(cat /path/to/k8s-home-arc-runner.private-key.pem)

op item create \
  --category="API Credential" \
  --title="arc-github-app" \
  --vault=k8s_home \
  username="k8s-home-arc-runner" \
  github_app_id[STRING]="APP_ID" \
  github_app_installation_id[STRING]="INSTALLATION_ID" \
  "github_app_private_key[CONCEALED]=${PEM_KEY}"
```

### 3. Update the OnePasswordItem Manifest

Set the `itemPath` in `unstable/apps-helm/arc-runner/manifests/arc-github-app-secret.yaml`
to the actual 1Password item ID (from the `op item create` output).

```yaml
spec:
  itemPath: vaults/copxopw5gkuo2m3cv7acvkrfxy/items/<ITEM_ID>
```

## File Layout

```
default/                          # Values branch (staging)
└── apps-helm/
    ├── arc-controller/
    │   └── values.yaml           # Controller Helm values
    └── arc-runner/
        └── values.yaml           # Runner scale set Helm values

unstable/                         # Active branch
├── apps-helm/
│   ├── arc-controller/
│   │   ├── values.yaml           # Controller Helm values
│   │   └── manifests/            # Placeholder for Argo multi-source
│   └── arc-runner/
│       ├── values.yaml           # Runner scale set Helm values
│       └── manifests/
│           └── arc-github-app-secret.yaml  # OnePasswordItem → K8s Secret
└── bootstrap/
    └── apps-helm.yaml            # ApplicationSet with arc-controller + arc-runner entries
```

## Helm Values

### Controller (`arc-controller/values.yaml`)

```yaml
replicaCount: 1
flags:
  logLevel: "info"
leaderElection:
  enabled: true
metrics:
  controllerManagerAddr: ":8080"
  listenerAddr: ":8080"
  listenerEndpoint: "/metrics"
```

### Runner (`arc-runner/values.yaml`)

```yaml
# Explicit controller service account to bypass Helm chart's label-based
# discovery (which fails during Argo CD comparison before the controller deploys)
controllerServiceAccount:
  namespace: actions-runner-controller
  name: arc-gha-rs-controller

githubConfigUrl: "https://github.com/nlopez/k8s_home"
githubConfigSecret: arc-github-app-secret
runnerGroup: "default"
minRunners: 0
maxRunners: 4
ephemeral: true

resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "2000m"
    memory: "2Gi"
```

## Key Details

- **Secret name** expected by ARC Helm: `arc-github-app-secret`
- **Secret namespace**: `arc-runners`
- **Secret keys**: `github_app_id`, `github_app_installation_id`, `github_app_private_key`
- **Secret source**: 1Password via `OnePasswordItem` CRD (synced by `onepassword-connect-operator`)
- **Runner mode**: Ephemeral (pods auto-destruct after use)
- **Scale**: `minRunners: 0` → runners only spawn when a workflow job needs them

## Usage in Workflows

Add a runner label to your workflow job:

```yaml
jobs:
  example:
    runs-on: arc-runner
    steps:
      - uses: actions/checkout@v4
      - run: echo "Hello from self-hosted runner"
```

## Verification

```bash
# Controller pod should be running
kubectl get pods -n actions-runner-controller

# Secret synced from 1Password
kubectl get secret -n arc-runners arc-github-app-secret

# Runner pods appear on-demand
kubectl get pods -n arc-runners

# Delete an idle runner
kubectl delete pod -n arc-runners <runner-pod-name>
```

## Troubleshooting

### Controller can't find the secret

Check that the `OnePasswordItem` is Ready:
```bash
kubectl get OnePasswordItem -n arc-runners arc-github-app-secret
```

If the sync fails, verify the `itemPath` in the manifest matches the actual
1Password item ID:
```bash
# Check current 1Password item ID
op item get fv5qv4dqbrgaqn254dewtzwyvq  # replace with your item ID

# Or list all items in the vault
op item list copxopw5gkuo2m3cv7acvkrfxy  # replace with vault ID
```

### Runner scale set reconciliation errors

The Helm chart requires the controller to be deployed first. The sync wave
annotation (wave `0` for controller, wave `1` for runner) ensures correct
ordering. If the runner still fails:

```bash
# Check controller logs
kubectl logs -n actions-runner-controller -l app.kubernetes.io/component=controller --tail=50

# Check runner scale set status
kubectl get autoscalingrunnerset -n arc-runners
```

### Argo CD can't render runner manifests

If you see `No gha-rs-controller deployment found` during Argo comparison,
ensure `controllerServiceAccount.name` is set in the runner values:

```yaml
controllerServiceAccount:
  namespace: actions-runner-controller
  name: arc-gha-rs-controller
```

This bypasses the Helm chart's label-based service account discovery.
