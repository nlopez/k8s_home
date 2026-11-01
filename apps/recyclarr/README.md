# recyclarr

[Recyclarr](https://recyclarr.dev) syncs [TRaSH Guides](https://trash-guides.info) quality
profiles, custom formats, and quality sizes into Sonarr and Radarr. It runs as a daily CronJob
(`recyclarr sync`) rather than the image's built-in cron mode.

## How it works

`configmap.yaml` holds one config file per service, mounted at `/config/configs/`. API keys are read
from the environment via `!env_var` (sourced from 1Password through the `sonarr-api-key` and
`radarr-api-key` Secrets). The `/config` PVC persists Recyclarr state and the cloned guide resources.

Profiles synced:

| Service | Profile |
|---|---|
| Sonarr | WEB-1080p, [Anime] Remux-1080p |
| Radarr | HD Bluray + WEB, Remux + WEB 1080p |

`reset_unmatched_scores` is enabled, so Recyclarr owns the custom format scores of these profiles.

Radarr movie naming is synced from the TRaSH `plex-tmdb` formats. Plex and Jellyfin both read the
`{tmdb-123}` tag in curly braces, so one format serves both servers. Existing files are only renamed
when you run Rename in Radarr; the setting alone affects new imports.

## Running a one-off sync

```bash
kubectl create job recyclarr-manual --from=cronjob/recyclarr -n recyclarr
kubectl logs -n recyclarr -l job-name=recyclarr-manual -f --prefix
kubectl delete job recyclarr-manual -n recyclarr
```

## Updating the image

```bash
IMAGE=ghcr.io/recyclarr/recyclarr
skopeo --override-os linux list-tags "docker://${IMAGE}" | jq -r '.Tags[]' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n5
```
