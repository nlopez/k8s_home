# seadexarr

[seadexarr](https://github.com/bbtufty/seadexarr) scans Sonarr for anime series, matches them against the
[SeaDex](https://releases.moe) database of best-known releases, and can automatically add missing or
upgraded torrents to a torrent client. It runs as a CronJob every 6 hours.

## How it works

On each run, an init container renders `/config/config.yml` by injecting the Sonarr API key (sourced
from 1Password via the `sonarr-api-key` Secret) into the ConfigMap template, then the main container
runs `seadexarr run single --sonarr`. The `/config` PVC persists `cache.json` between runs so seadexarr
doesn't re-evaluate releases it has already seen.

## Running a one-off job

To trigger a run immediately without waiting for the next scheduled time:

```bash
kubectl create job seadexarr-manual --from=cronjob/seadexarr -n seadexarr
```

Watch it run:

```bash
kubectl logs -n seadexarr -l job-name=seadexarr-manual -f --prefix
```

Clean up when done:

```bash
kubectl delete job seadexarr-manual -n seadexarr
```

## Configuration

Non-secret config is in `configmap.yaml`. The full set of available options is documented in the
[seadexarr config docs](https://github.com/bbtufty/seadexarr?tab=readme-ov-file#config).

Notable defaults:

| Setting | Value | Notes |
|---|---|---|
| `sonarr_url` | `http://sonarr.sonarr.svc.cluster.local` | In-cluster service |
| `public_only` | `true` | Nyaa/AnimeTosho only |
| `prefer_dual_audio` | `true` | Prefer dual-audio releases |
| `want_best` | `true` | Prefer SeaDex "best" tagged releases |
| `interactive` | `false` | Required for unattended CronJob use |

To add Radarr, qBittorrent, or Discord support, extend `configmap.yaml` with the relevant fields and
add any additional secrets to 1Password.

## Updating the image

```bash
IMAGE=ghcr.io/bbtufty/seadexarr
skopeo --override-os linux list-tags "docker://${IMAGE}" | jq -r '.Tags[]' | sort -V | tail -n5
```

Then update the `image:` tag in `cronjob.yaml` for both the `config-init` and `seadexarr` containers.
