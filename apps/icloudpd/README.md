# icloudpd - iCloud Photos Downloader

icloudpd downloads photos and videos from iCloud to your media NFS share at `/home/user/iCloud`. It runs as a `CronJob` (`cronjob.yaml`) that performs a single pass and exits, rather than a long-lived process managing its own internal schedule.

## Prerequisites

- See [official documentation](https://github.com/boredazfcuk/docker-icloudpd/blob/master/CONFIGURATION.md)

## Important Notes

- **User/Group ID**: The `boredazfcuk/icloudpd` container creates its own internal user (via `useradd` in its `launcher.sh` entrypoint) with `user_id=1001` and `group_id=1001` from `/config/icloudpd.conf`. It starts as root, creates the user, then uses `su` to switch to that user for downloads. The `set_owner_and_permissions_downloads` function chowns all downloaded files to `1001:1001` to match the NFS share. This means no `securityContext` is needed in the pod spec.
- **Existing Files**: If you have previously downloaded files with `1000:1000` ownership, fix them: `chown -R 1001:1001 /mnt/etank/media/icloud`
- **Interactive Setup**: You must run the interactive initialization process to set up authentication and generate the MFA cookie
- **Configuration File**: icloudpd.conf is created during initialization using `sync-icloud.sh --Initialise`
- **Scheduled Sync**: A Kubernetes `CronJob` triggers a single pass every 6 hours (`schedule: '0 */6 * * *'`); `single_pass` must be `true` in `icloudpd.conf` so each run exits after one pass instead of looping. `download_interval` is ignored once `single_pass=true`.
- **Immich Tag Sync**: icloudpd runs as an init container. When a pass exits successfully, the `sync-trigger` container starts an `immich-sidecar-sync` Job in the `immich` namespace (`kubectl create job --from=cronjob/immich-sidecar-sync`), so XMP tags and metadata reach Immich right after each pass. Because of that, `kubectl exec` into a running pass needs `-c icloudpd`. The `icloudpd` ServiceAccount is bound to the `immich-sidecar-sync-trigger` Role (`apps-helm/immich/manifests/sidecar-sync-trigger-rbac.yaml`), and only the trigger container mounts its token.
- **Telegram Re-auth**: The `icloudpd-auth` Deployment (`auth-deployment.yaml`) is an always-on pod that never downloads; it only polls the Telegram bot. When a CronJob pass finds the cookie expired, it sends a Telegram message; reply `<user> auth`, then `<user> <6-digit code>` (or the device letter it asks for first, where `<user>` is the `user=` value in the config). The new cookie is written to the shared `config` volume and the next CronJob run uses it. The Deployment uses its own config file, `/config/icloudpd-auth.conf` (seeded from `icloudpd.conf` on first start), selected with the `config_file` env var; the CronJob keeps `icloudpd.conf`. Settings that differ between the two (`single_pass`, `skip_download`, ...) are set as env vars in each manifest, which the fork image applies over the config file on every start. Because `config` is `ReadWriteOnce`, the CronJob pod has a `podAffinity` to `icloudpd-auth` and stays `Pending` while that Deployment has no running pod.
- **Failsafe Mount Check**: A `.mounted` file is required in `/home/user/iCloud/.mounted` to prevent accidental syncs

## Setup Instructions

### 1. Create Storage

Deploy the persistent volumes and claims:

```bash
kubectl apply -f pvc-config.yaml
kubectl apply -f pvc-media.yaml
```

Create the mandatory `.mounted` failsafe file in the download path:

```bash
kubectl run icloudpd-init \
  --image=busybox:latest \
  --stdin --tty --rm \
  --overrides='{"spec":{"volumes":[{"name":"media","persistentVolumeClaim":{"claimName":"media"}}],"containers":[{"name":"init","image":"busybox:latest","volumeMounts":[{"name":"media","mountPath":"/home/user/iCloud"}],"command":["touch","/home/user/iCloud/.mounted"]}]}}' \
  -- touch /home/user/iCloud/.mounted
```

Or manually: `kubectl exec -it -c icloudpd <pod> -- touch /home/user/iCloud/.mounted`

### 2. Deploy the CronJob

Deploy the icloudpd CronJob:

```bash
kubectl apply -f cronjob.yaml
```

### 3. Run Initial Authentication & Configuration (MFA Setup)

Trigger a one-off Job from the CronJob so you have a pod to attach to (don't wait for the top of the hour):

```bash
kubectl create job -n icloudpd --from=cronjob/icloudpd icloudpd-init
kubectl get pods -n icloudpd -l job-name=icloudpd-init -w
```

Once the pod is running, attach to it interactively:

```bash
kubectl exec -it -n icloudpd -c icloudpd <icloudpd-init-pod-name> -- /bin/sh
```

Inside the pod, run the initialization script:

```bash
sync-icloud.sh --Initialise
```

This interactive process will:
1. Prompt for your Apple ID account password (not an app-specific password; stored in system keyring)
2. Send an approval request to your trusted device
3. Ask you to choose how to receive the MFA code (SMS recommended)
4. Ask you to enter the 6-digit MFA code
5. Create `/config/icloudpd.conf` with default settings
6. Generate and store the MFA cookie in `/config/your-email@icloud.com`

Once complete, edit `/config/icloudpd.conf` and set `single_pass=true` so each run exits after one pass instead of looping.

## Updating the Container Image

The CronJob runs `ghcr.io/nlopez/docker-icloudpd`, a fork of `boredazfcuk/docker-icloudpd` (branch `icloudpd-1.33.0`) that bundles icloudpd 1.33.0. The upstream image still bundles 1.32.3, where `--xmp-sidecar` aborts the whole run on assets with malformed adjustment data. The image is pinned by digest in `cronjob.yaml`.

Switch back to `docker.io/boredazfcuk/icloudpd` once its Dockerfile has `icloudpd_version` >= 1.33.0:

```bash
# Check the bundled icloudpd version on upstream master
gh api repos/boredazfcuk/docker-icloudpd/contents/icloudpd.dockerfile --jq .content | base64 -d | grep icloudpd_version

# Latest upstream image tag
skopeo --override-os linux list-tags docker://boredazfcuk/icloudpd | jq -r '.Tags[]' | grep '^[0-9]' | sort -V | tail -n1
```

To rebuild the fork image, run the `Build and push to GHCR` workflow in `nlopez/docker-icloudpd` (`workflow_dispatch`), then pin the new digest:

```bash
skopeo inspect --override-os linux --override-arch amd64 --format '{{.Digest}}' docker://ghcr.io/nlopez/docker-icloudpd:<tag>
```

## Configuration

### Configuration File

The icloudpd configuration file `/config/icloudpd.conf` is created during the initialization process (`sync-icloud.sh --Initialise`). It contains all your settings including:

**To modify configuration after initialization:**

```bash
# Trigger a one-off Job so you have a pod to connect to (or wait for the next scheduled run)
kubectl create job -n icloudpd --from=cronjob/icloudpd icloudpd-manual
kubectl exec -it -n icloudpd -c icloudpd <pod-name> -- sh

# Edit the configuration
vi /config/icloudpd.conf
```

Changes to `/config/icloudpd.conf` take effect on the next Job run automatically — there's no long-lived pod to restart.

### Key Configuration Items

- **apple_id**: Your iCloud email (set during initialization)
- **user**: Container user name (default: user)
- **download_path**: Where to save photos (default: `/home/user/iCloud`)
- **download_interval**: Ignored — the CronJob schedule (`cronjob.yaml`, every 6 hours by default) controls sync frequency instead
- **single_pass**: Must be `true` so each CronJob run exits after one pass
- **folder_structure**: Date-based organization `{:%Y/%m/%d}` (default) or `none` for flat structure
- **photo_size**: Image sizes to download - `original`, `medium`, `thumb`, `adjusted`, `alternative` or any combination
- **skip_videos**: Set to `true` to skip video downloads
- **convert_heic_to_jpeg**: Set to `true` to create JPEG copies of HEIC files
- **skip_check**: Set to `true` for large libraries (thousands of photos)

See [CONFIGURATION.md](https://github.com/boredazfcuk/docker-icloudpd/blob/master/CONFIGURATION.md) for all available options.

### Storage Paths

- **Config**: `/config` - Stores icloudpd.conf, MFA cookie, and keyring
- **Home**: `/home/user/iCloud` - Maps to `/mnt/etank/media/iCloud` on your NFS share (requires `.mounted` file)

## Managing Authentication

### MFA Cookie Expiration

The MFA cookie expires every **30 days**. The usual way to re-authenticate is to reply to the Telegram bot (see **Telegram Re-auth** above). To do it by hand instead, run `reauth.sh` in the auth pod (or in a one-off Job as below):

```bash
kubectl exec -it -n icloudpd deploy/icloudpd-auth -- reauth.sh
```

Or from a one-off Job:

```bash
kubectl create job -n icloudpd --from=cronjob/icloudpd icloudpd-reauth
kubectl exec -it -n icloudpd -c icloudpd <icloudpd-reauth-pod-name> -- reauth.sh
```

This prompts for a new MFA code on your device and generates a fresh cookie.

### Password Changes

If you change your iCloud password, remove the keyring:

```bash
kubectl create job -n icloudpd --from=cronjob/icloudpd icloudpd-remove-keyring
kubectl exec -it -n icloudpd -c icloudpd <icloudpd-remove-keyring-pod-name> -- sync-icloud.sh --Remove-Keyring
```

Then re-run initialization: `sync-icloud.sh --Initialise`

## Troubleshooting

### `.mounted` Failsafe

icloudpd requires a `.mounted` file in the download destination (`/home/user/iCloud/.mounted`). Without it, no downloads will occur. This prevents syncing if the NFS mount fails.

### Two-Factor Authentication Issues

- **Won't authenticate / "invalid password"**: Use the real Apple ID account password. App-specific passwords are rejected with a 401. If the password changed, run `sync-icloud.sh --Remove-Keyring` then `--Initialise`
- **Cookie expired**: Run `reauth.sh` or re-initialize with --Initialise
- **Security keys**: Accounts with registered security keys can't authenticate (the bundled icloudpd can't do the key touch headlessly); remove all security keys from the Apple ID first
- **"Allow" prompt but no 6-digit code**: On an iPhone or iPad, turn on Airplane Mode and turn Wi-Fi off, then Settings → your name → Sign-In & Security → Get Verification Code
- **Advanced Data Protection**: Disable Apple's Advanced Data Protection in iOS 16.2+ as it blocks icloud.com access

### XMP Sidecars

`xmp_sidecar=true` writes a `<file>.xmp` next to each asset (dates, GPS, keywords, title, rating). Every run regenerates sidecars it wrote itself and leaves ones from other tools alone, so existing photos are backfilled by a normal pass. Successful writes are not logged; only `Not overwriting XMP file` and `Could not write XMP sidecar` messages appear. Album membership is not included.

### DNS

Do not apply Cilium egress policies with `rules.dns` or `toFQDNs` to this namespace: the Cilium DNS proxy does not answer on this cluster's netkit datapath, so all lookups time out.

### Large Libraries

For libraries with thousands of photos, disable the check in config:

```
skip_check=true
```

### DNS/Network Issues

Ensure your cluster can reach iCloud servers (icloud.com, api-edge.icloud.com, etc.). If you change network or image settings, reapply the CronJob manifest (`kubectl apply -f cronjob.yaml`).

### RWO `config` PVC Contention

The `config` PVC is `ReadWriteOnce` (iSCSI), so only one pod can mount it at a time. If you manually trigger a Job (`kubectl create job --from=cronjob/...`) while another icloudpd pod is still running or terminating, the new pod may sit `Pending` briefly until the volume is released — this is expected, not a failure.
