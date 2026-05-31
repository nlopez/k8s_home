# icloudpd - iCloud Photos Downloader

icloudpd downloads photos and videos from iCloud to your media NFS share at `/home/user/iCloud`.

## Prerequisites

- See [official documentation](https://github.com/boredazfcuk/docker-icloudpd/blob/master/CONFIGURATION.md)

## Important Notes

- **User/Group ID**: The container runs as UID/GID 1001 to match the NFS share ownership (`1001:1001`). This is consistent with other media apps in the cluster.
- **Existing Files**: If you have previously downloaded files with `1000:1000` ownership, fix them: `chown -R 1001:1001 /mnt/etank/media/icloud`
- **Interactive Setup**: You must run the interactive initialization process to set up authentication and generate the MFA cookie
- **Configuration File**: icloudpd.conf is created during initialization using `sync-icloud.sh --Initialise`
- **Continuous Sync**: The singleton deployment runs continuously; keep `single_pass` unset or false and use `download_interval` to control frequency
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

### 2. Deploy the Singleton Pod

Deploy the icloudpd deployment:

```bash
kubectl apply -f deployment.yaml
```

### 3. Run Initial Authentication & Configuration (MFA Setup)

Watch the pod startup:

```bash
kubectl get pods -w
```

Once the pod is running, attach to it interactively:

```bash
kubectl exec -it <icloudpd-pod-name> -- /bin/sh
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

Once complete, optionally edit `/config/icloudpd.conf` if you need to customize settings.

## Updating the Container Image

The icloudpd deployment uses a specific version from Docker Hub: `boredazfcuk/icloudpd:v2024.02.16`

To update to a newer version:

```bash
# Check available versions
IMAGE=boredazfcuk/icloudpd
skopeo --override-os linux list-tags "docker://${IMAGE}" | jq -r '.Tags[]' | sort -V | tail -n10

# Update the image tag in deployment.yaml
# Then reapply:
kubectl apply -f deployment.yaml
```

## Configuration

### Configuration File

The icloudpd configuration file `/config/icloudpd.conf` is created during the initialization process (`sync-icloud.sh --Initialise`). It contains all your settings including:

**To modify configuration after initialization:**

```bash
# Connect to a running icloudpd pod
kubectl exec -it <pod-name> -- sh

# Edit the configuration
vi /config/icloudpd.conf

# Restart the pod to apply changes
kubectl rollout restart deployment/icloudpd
```

### Key Configuration Items

- **apple_id**: Your iCloud email (set during initialization)
- **user**: Container user name (default: user)
- **download_path**: Where to save photos (default: `/home/user/iCloud`)
- **download_interval**: Seconds between syncs - 21600 (6hrs), 43200 (12hrs), 86400 (24hrs) etc.
- **single_pass**: Keep `false` for the deployment (default)
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
kubectl exec -it <icloudpd-pod-name> -- reauth.sh
```

This prompts for a new MFA code on your device and generates a fresh cookie.

### Password Changes

If you change your iCloud password, remove the keyring:

```bash
kubectl exec -it <icloudpd-pod-name> -- sync-icloud.sh --Remove-Keyring
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

Ensure your cluster can reach iCloud servers (icloud.com, api-edge.icloud.com, etc.). If you change network or image settings, reapply the deployment manifest.
