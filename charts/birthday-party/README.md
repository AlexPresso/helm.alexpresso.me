# Birthday Party Helm Chart

This Helm chart deploys [Birthday Party](https://github.com/AlexPresso/birthday-party),
a private party app where guests share photos and videos, follow the schedule,
vote and play. It installs the Next.js frontend, one Go backend and PostgreSQL 18,
with the photos and the database on two separate volumes.

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8+
- A StorageClass that provisions volumes
- For public access, an Ingress controller and a TLS certificate (for example
  from cert-manager); the chart installs neither

## Installation

```bash
helm repo add alexpresso https://helm.alexpresso.me
helm install birthday alexpresso/birthday-party --namespace birthday --create-namespace \
  --set ingress.enable=true --set ingress.host=party.example.com \
  --set postgresql.password=<generated password>
kubectl --namespace birthday logs deployment/birthday-backend
```

The backend log shows a single-use `Administrator invitation:` link: open it to
become the host. Age, invitation texts and upload limits are then set in the app
and kept in the database across upgrades.

The Ingress serves `https://<ingress.host>` with the TLS Secret
`<release>-cert`. Create that Secret, or let cert-manager create it through an
annotation such as `cert-manager.io/cluster-issuer`. Check the controller settings
in [Ingress, uploads and WebSocket](#ingress-uploads-and-websocket) before inviting
guests.

To keep the database password out of the Helm release, create the Secret first
and pass its name instead:

```bash
kubectl --namespace birthday create secret generic birthday-database --from-literal=password=<generated password>
helm install birthday alexpresso/birthday-party --namespace birthday \
  --set ingress.enable=true --set ingress.host=party.example.com \
  --set postgresql.existingSecret=birthday-database
```

To try it without an Ingress, install with only a password, then:

```bash
kubectl --namespace birthday port-forward service/birthday-frontend 3000:3000
```

and open `http://localhost:3000`. The backend may restart while PostgreSQL
initializes; Kubernetes restarts it until the database is ready.

## Configuration

| Parameter                         | Description                                                                 | Default                                      |
|-----------------------------------|-----------------------------------------------------------------------------|----------------------------------------------|
| `publicUrl`                       | Origin guests open, without a path; invitation links are built from it      | Derived from `ingress.host`, else localhost  |
| `image.tag`                       | Image tag of both applications                                              | Chart `appVersion`                           |
| `image.pullPolicy`                | Image pull policy                                                           | `IfNotPresent`                               |
| `image.pullSecrets`               | Registry Secrets, for a private fork's images                               | `[]`                                         |
| `frontend.image`                  | Frontend image, without tag                                                 | `ghcr.io/alexpresso/birthday-party-frontend` |
| `frontend.resources`              | Frontend resources                                                          | 100m / 128Mi, limit 1Gi                      |
| `backend.image`                   | Backend image, without tag                                                  | `ghcr.io/alexpresso/birthday-party-backend`  |
| `backend.printAdminInvitation`    | Print a single-use host link in the log at startup                          | `true`                                       |
| `backend.vapidSubject`            | `mailto:` or `https:` contact given to Web Push services                    | (empty)                                      |
| `backend.resources`               | Backend resources                                                           | 250m / 512Mi, limit 2Gi                      |
| `backend.goMemoryLimit`           | `GOMEMLIMIT`, kept below the memory limit                                   | `1536MiB`                                    |
| `backend.volume.existingClaim`    | Existing PVC for photos and videos                                          | (empty)                                      |
| `backend.volume.storageClass`     | StorageClass; empty for the default, `-` for none                           | (empty)                                      |
| `backend.volume.size`             | Media volume size; its free space bounds the gallery                        | `20Gi`                                       |
| `postgresql.enable`               | Deploy PostgreSQL; disable to use `externalDatabase`                        | `true`                                       |
| `postgresql.image`                | PostgreSQL image                                                            | `postgres:18-alpine`                         |
| `postgresql.database`             | Database name                                                               | `birthday`                                   |
| `postgresql.username`             | Database user                                                               | `birthday`                                   |
| `postgresql.password`             | Database password, stored in `<release>-secrets`                            | (empty, required without `existingSecret`)   |
| `postgresql.existingSecret`       | Existing Secret holding the password                                        | (empty)                                      |
| `postgresql.passwordKey`          | Key of the password in that Secret                                          | `password`                                   |
| `postgresql.volume.*`             | Same as `backend.volume.*`                                                  | `10Gi`                                       |
| `postgresql.resources`            | PostgreSQL resources                                                        | 100m / 128Mi, limit 1Gi                      |
| `externalDatabase.existingSecret` | Secret holding a complete PostgreSQL URL                                    | (empty)                                      |
| `externalDatabase.urlKey`         | Key of the URL in that Secret                                               | `DATABASE_URL`                               |
| `externalDatabase.port`           | Database port opened by the NetworkPolicy                                   | `5432`                                       |
| `ingress.enable`                  | Create the Ingress                                                          | `false`                                      |
| `ingress.host`                    | Host serving the app                                                        | (empty)                                      |
| `ingress.tls`                     | Serve HTTPS with the `<release>-cert` Secret                                | `true`                                       |
| `ingress.className`               | Ingress class                                                               | `traefik`                                    |
| `ingress.annotations`             | Ingress annotations                                                         | (empty)                                      |
| `networkPolicy.enable`            | Restrict traffic with NetworkPolicies                                       | `true`                                       |
| `networkPolicy.ingressFrom`       | Peers allowed on the HTTP ports; empty allows any source                    | `[]`                                         |
| `nodeSelector`, `tolerations`     | Scheduling of all three components                                          | (empty)                                      |

## Images and versions

The images are built for `linux/amd64` and `linux/arm64` by the
[birthday-party workflows](https://github.com/AlexPresso/birthday-party/actions).
Without `image.tag`, the chart uses its `appVersion`, published by the Git tag
`v<appVersion>`. `sha-<full commit SHA>` deploys one exact build of the main
branch. Both tags never move, so `IfNotPresent` is enough; `latest` follows the
main branch and needs `pullPolicy: Always`. For a fork, set `frontend.image` and
`backend.image` to its own images and, if they are private, add an
`image.pullSecrets` entry.

## Ingress, uploads and WebSocket

The Ingress sends `/api` straight to the backend: API, uploads, media and the
`/api/realtime` WebSocket. Every other path goes to the frontend. Both share one
host, so cookies and the `Origin` check against `publicUrl` are unchanged. The
backend reads no `X-Forwarded-*` header; it relies on `publicUrl` alone, which
must be the exact origin guests open.

On `/api`, the controller must:

- accept 1024 MiB + 64 KiB per request (1025 MiB), the app's ceiling; the
  backend applies the limits chosen in its settings;
- allow at least 600 seconds for uploads and downloads;
- stream request bodies without buffering them;
- accept WebSocket upgrades and keep them open for more than 30 seconds without
  traffic.

Traefik already streams bodies without a size limit and upgrades WebSockets; do
not attach a `buffering` middleware. Its timeout belongs to the entry point, in
its static configuration:

```
--entryPoints.websecure.transport.respondingTimeouts.readTimeout=600s
```

With ingress-nginx:

```yaml
ingress:
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: 1025m
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
```

Phone notifications only work over HTTPS. The backend creates its own Web Push
keys and keeps them in PostgreSQL.

## Pod and network security

The frontend and backend run as non-root users, without Linux capabilities and
with a read-only root filesystem. The backend writes only to its `/data` volume.
The frontend writes one file at startup, `.next/routes-manifest.json`, which an
init container copies to an `emptyDir` mounted in its place.

`networkPolicy.enable` allows only: the two HTTP ports, the frontend to the
backend, the backend to PostgreSQL, DNS, and the backend to public addresses on
port 443 for Web Push. PostgreSQL accepts the backend alone. These rules need a
network plugin that enforces NetworkPolicies. To accept only the Ingress
controller (`kubectl port-forward` keeps working):

```yaml
networkPolicy:
  ingressFrom:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: traefik
```

The backend requests 512 MiB and may use 2 GiB: its two workers each decode one
photo of up to 40 megapixels, and FFmpeg reads one frame per video.

## External database and existing volumes

For a separately managed database, create a Secret with a complete PostgreSQL URL,
including credentials and the TLS mode the server requires. The account must be
able to apply the SQL migrations. Use a direct connection or session pooling: the
workers hold a session lock, which rules out transaction pooling.

```bash
kubectl --namespace birthday create secret generic birthday-external-database --from-literal=DATABASE_URL=<postgresql URL>
```

```yaml
postgresql:
  enable: false
externalDatabase:
  existingSecret: birthday-external-database
```

To reuse volumes, set `backend.volume.existingClaim` and, with the bundled
PostgreSQL, `postgresql.volume.existingClaim`. The PVCs must be in the release
namespace. The backend writes as UID/GID `10001`, PostgreSQL Alpine as `70`; new
volumes get the right group through `fsGroup`, restored files must also have the
right owner.

PostgreSQL 18 data lives in `/var/lib/postgresql/18/docker` on its volume. Do not
change the major version, or switch to a non-Alpine image, by editing the tag
alone: the database needs a migration. Changing the password of an initialized
database does not change its SQL password; after rotating it in PostgreSQL,
restart the backend.

## Upgrades and backups

Change `image.tag` (or upgrade the chart), then run `helm upgrade` with the same
values. The backend uses the `Recreate` strategy, so the app is briefly
unavailable while it restarts. SQL migrations run at startup: back up before
upgrading, since a Helm rollback restores neither the schema nor the data.

Back up PostgreSQL and the media volume together, with the backend stopped; see
the [backup procedure](https://github.com/AlexPresso/birthday-party/blob/main/docs/database.md).
Never run two releases on the same database and volume. The PVCs created by the
chart carry `helm.sh/resource-policy: keep` and survive `helm uninstall`; to
reuse them with a new release, set their names in `existingClaim`.

Releases installed from the chart that used to live in the birthday-party
repository named their volumes `<release>-birthday-party-media` and
`<release>-birthday-party-postgresql`. Set both `existingClaim` values to these
names, and `postgresql.existingSecret` to the existing database Secret, to keep
their data.
