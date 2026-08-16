# icloudpd - iCloud Photos Downloader

icloudpd downloads photos and videos from iCloud to your media NFS share at `/home/user/iCloud`. It runs as an hourly `CronJob` (`cronjob.yaml`) that performs a single pass and exits, rather than a long-lived process managing its own internal schedule.

## Prerequisites

- See [official documentation](https://github.com/boredazfcuk/docker-icloudpd/blob/master/CONFIGURATION.md)

## Important Notes

- **User/Group ID**: The `boredazfcuk/icloudpd` container creates its own internal user (via `useradd` in its `launcher.sh` entrypoint) with `user_id=1001` and `group_id=1001` from `/config/icloudpd.conf`. It starts as root, creates the user, then uses `su` to switch to that user for downloads. The `set_owner_and_permissions_downloads` function chowns all downloaded files to `1001:1001` to match the NFS share. This means no `securityContext` is needed in the pod spec.
- **Existing Files**: If you have previously downloaded files with `1000:1000` ownership, fix them: `chown -R 1001:1001 /mnt/etank/media/icloud`
- **Interactive Setup**: You must run the interactive initialization process to set up authentication and generate the MFA cookie
- **Configuration File**: icloudpd.conf is created during initialization using `sync-icloud.sh --Initialise`
- **Scheduled Sync**: A Kubernetes `CronJob` triggers a single pass every hour (`schedule: '0 * * * *'`); `single_pass` must be `true` in `icloudpd.conf` so each run exits after one pass instead of looping. `download_interval` is ignored once `single_pass=true`.
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

Or manually: `kubectl exec -it <pod> -- touch /home/user/iCloud/.mounted`

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
kubectl exec -it -n icloudpd <icloudpd-init-pod-name> -- /bin/sh
```

Inside the pod, run the initialization script:

```bash
sync-icloud.sh --Initialise
```

This interactive process will:
1. Prompt for your iCloud password (stored in system keyring)
2. Send an approval request to your trusted device
3. Ask you to choose how to receive the MFA code (SMS recommended)
4. Ask you to enter the 6-digit MFA code
5. Create `/config/icloudpd.conf` with default settings
6. Generate and store the MFA cookie in `/config/your-email@icloud.com`

Once complete, edit `/config/icloudpd.conf` and set `single_pass=true` so each hourly run exits after one pass instead of looping.

## Updating the Container Image

The icloudpd CronJob uses a specific version mirrored from Docker Hub's `boredazfcuk/icloudpd`.

To update to a newer version:

```bash
# Check available versions
IMAGE=boredazfcuk/icloudpd
skopeo --override-os linux list-tags "docker://${IMAGE}" | jq -r '.Tags[]' | sort -V | tail -n10

# Update the image tag in cronjob.yaml
# Then reapply:
kubectl apply -f cronjob.yaml
```

## Configuration

### Configuration File

The icloudpd configuration file `/config/icloudpd.conf` is created during the initialization process (`sync-icloud.sh --Initialise`). It contains all your settings including:

**To modify configuration after initialization:**

```bash
# Trigger a one-off Job so you have a pod to connect to (or wait for the next hourly run)
kubectl create job -n icloudpd --from=cronjob/icloudpd icloudpd-manual
kubectl exec -it -n icloudpd <pod-name> -- sh

# Edit the configuration
vi /config/icloudpd.conf
```

Changes to `/config/icloudpd.conf` take effect on the next Job run automatically — there's no long-lived pod to restart.

### Key Configuration Items

- **apple_id**: Your iCloud email (set during initialization)
- **user**: Container user name (default: user)
- **download_path**: Where to save photos (default: `/home/user/iCloud`)
- **download_interval**: Ignored — the CronJob schedule (`cronjob.yaml`, hourly by default) controls sync frequency instead
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

The MFA cookie expires every **30 days**. Re-authenticate when needed:

```bash
kubectl create job -n icloudpd --from=cronjob/icloudpd icloudpd-reauth
kubectl exec -it -n icloudpd <icloudpd-reauth-pod-name> -- reauth.sh
```

This prompts for a new MFA code on your device and generates a fresh cookie.

### Password Changes

If you change your iCloud password, remove the keyring:

```bash
kubectl create job -n icloudpd --from=cronjob/icloudpd icloudpd-remove-keyring
kubectl exec -it -n icloudpd <icloudpd-remove-keyring-pod-name> -- sync-icloud.sh --Remove-Keyring
```

Then re-run initialization: `sync-icloud.sh --Initialise`

## Troubleshooting

### `.mounted` Failsafe

icloudpd requires a `.mounted` file in the download destination (`/home/user/iCloud/.mounted`). Without it, no downloads will occur. This prevents syncing if the NFS mount fails.

### Two-Factor Authentication Issues

- **Won't authenticate**: Ensure you used an [iCloud app-specific password](https://support.apple.com/en-us/102654), not your main password
- **Cookie expired**: Run `reauth.sh` or re-initialize with --Initialise
- **Advanced Data Protection**: Disable Apple's Advanced Data Protection in iOS 16.2+ as it blocks icloud.com access

### Large Libraries

For libraries with thousands of photos, disable the check in config:

```
skip_check=true
```

### DNS/Network Issues

Ensure your cluster can reach iCloud servers (icloud.com, api-edge.icloud.com, etc.). If you change network or image settings, reapply the CronJob manifest (`kubectl apply -f cronjob.yaml`).

### RWO `config` PVC Contention

The `config` PVC is `ReadWriteOnce` (iSCSI), so only one pod can mount it at a time. If you manually trigger a Job (`kubectl create job --from=cronjob/...`) while another icloudpd pod is still running or terminating, the new pod may sit `Pending` briefly until the volume is released — this is expected, not a failure.
