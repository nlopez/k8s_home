# obsidian-livesync

CouchDB instance for [Obsidian LiveSync](https://github.com/vrtmrz/obsidian-livesync).

## Connection Details

| Setting | Value |
|---------|-------|
| **Public URL** | `https://sunny-glacier.desertbluffs.com` |
| **Username** | `admin` |
| **Password** | See 1Password: `Automation > obsidian-livesync-couchdb > COUCHDB_PASSWORD` |
| **Database** | `obsidiannotes` (created on first sync) |

## Client Setup

### Prerequisites

- [Obsidian LiveSync plugin](https://publish.obsidian.md/livesync/Getting+Started/Setup+LiveSync) installed in Obsidian
- Back up every vault involved before starting
- Disable Obsidian Sync, iCloud, and any other sync services

### First Device

1. Open Obsidian and go to **Settings → Community plugins → LiveSync**
2. Click **Set up LiveSync**
3. Select **CouchDB** as the synchronization method
4. Enter the connection details:
   - **Server URL**: `https://sunny-glacier.desertbluffs.com`
   - **Username**: `admin`
   - **Password**: (from 1Password)
   - **Database**: `obsidiannotes`
5. Click **Continue** — the database will be created automatically
6. Complete the onboarding wizard
7. Create a test note and verify it syncs

### Additional Devices

1. On the **first device**, go to **LiveSync settings → Generate Setup URI**
2. Copy the encrypted Setup URI
3. On the **new device**, paste the Setup URI when prompted
4. Enter the passphrase when requested
5. Verify synchronization by creating/editing a note on each device

### Mobile (iOS/Android)

- **HTTPS required** — the public URL uses TLS, so mobile clients will work
- Follow the same first-device setup steps
- Use the Setup URI from the desktop for additional mobile devices

## Troubleshooting

### CORS Errors

The server is pre-configured with CORS for:
- `app://obsidian.md` (desktop)
- `capacitor://localhost` (mobile)
- `https://sunny-glacier.desertbluffs.com` (public web)

### Connection Refused

- Verify the pod is running: `kubectl get pods -n obsidian-livesync`
- Check logs: `kubectl logs -n obsidian-livesync -l app=obsidian-livesync`

### Authentication Failed

- Verify credentials in 1Password
- Test manually: `curl -u admin:PASSWORD https://sunny-glacier.desertbluffs.com/_up`

## Administration

### View CouchDB Status

```bash
kubectl exec -n obsidian-livesync -l app=obsidian-livesync -- curl -s http://localhost:5984/_up
```

### Access CouchDB Admin UI

```bash
kubectl port-forward -n obsidian-livesync svc/couchdb 5984:5984
open http://localhost:5984/_utils/
```

### Backup

Daily backups run automatically via Velero at 11:15 UTC (6:15 AM EST).
Backups retain the last 30 days and include CSI/ZFS snapshots of the PVC.

```bash
# Check latest backup
kubectl get backups -n velero --sort-by='.status.completionTimestamp' | tail -5

# List Velero schedules
kubectl get schedules -n velero
```

## Architecture

```
Obsidian Client (multiple devices)
    ↕ HTTPS (TLS at Envoy Gateway)
Envoy Gateway — sunny-glacier.desertbluffs.com:443
    ↕ HTTP
CouchDB Service (ClusterIP:5984)
    ↕
CouchDB Pod (couchdb:3.5.2.1)
    ↕
PVC (nas1-mtank-iscsi) → TrueNAS ZFS
```

Private access within the tailnet via `obsidian-livesync` (Tailscale Ingress).
