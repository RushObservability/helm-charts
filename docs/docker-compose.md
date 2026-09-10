# Run Rush with Docker Compose

[← Helm charts](../README.md)

This is the fastest way to see Rush working. Compose pulls released images and
starts the whole stack on one machine, so nothing is built and no source
checkout is needed. Use it to evaluate Rush or to develop against a local
ingest endpoint; use the [Helm charts](getting-started.md) for anything real.

The stack lives in [`compose/`](../compose/).

## Before you start

Docker with Compose v2, about 4 GiB of available memory, and 2 GiB of disk.

```bash
docker compose version
```

## Start it

```bash
git clone https://github.com/RushObservability/helm-charts.git
cd helm-charts/compose
docker compose --profile demo up -d
```

The first start pulls roughly 1 GiB of images. When it finishes, open
<http://localhost:5173> and sign in:

```text
Username: admin
Password: rush-admin123
```

`INITIAL_ADMIN_PASSWORD` seeds the administrator only while ClickHouse has no
users. Changing it later does not reset an existing password.

The `demo` profile also starts six instrumented services and a traffic
generator running at about five requests per second, so the UI has data
immediately. Services, traces, and logs appear within a minute:

| Page | Shows |
|---|---|
| `/services` | The demo services with request and error rates |
| `/traces` | Traces through the gateway and its downstream calls |
| `/logs` | Container logs collected by Vector |

Confirm readiness without the UI:

```bash
docker compose --profile demo ps
curl -fsS http://localhost:8080/readyz
curl -fsS http://localhost:8123/ping
```

## Profiles

Each profile adds to the core stack of ClickHouse, query-api, and the frontend.

| Command | Adds |
|---|---|
| `docker compose up -d` | Nothing; core stack only |
| `docker compose --profile telemetry up -d` | OpenTelemetry Collector and Vector |
| `docker compose --profile demo up -d` | The telemetry profile, six demo services, and a traffic generator |
| `docker compose --profile sre up -d` | The SRE agent |
| `docker compose --profile all up -d` | Every profile above |

Profiles combine, so `--profile telemetry --profile sre` works without `all`.

## Send your own telemetry

The `telemetry` profile exposes OTLP on `localhost:4317` (gRPC) and
`localhost:4318` (HTTP), and forwards traces, metrics, and OTLP logs to
query-api. Point an instrumented application at it:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_SERVICE_NAME=my-service
```

Vector reads `/var/run/docker.sock` to collect container stdout and stderr.
Docker Desktop and OrbStack expose that socket by default; on Linux the daemon
must permit the container to read it.

## Ports

Every published port binds to `127.0.0.1`.

| Port | Service | Override |
|---|---|---|
| 5173 | Frontend | `RUSH_FRONTEND_PORT` |
| 8080 | Query API | `RUSH_API_PORT` |
| 8123 | ClickHouse HTTP | `CLICKHOUSE_HTTP_PORT` |
| 4317 | OTLP gRPC | `OTLP_GRPC_PORT` |
| 4318 | OTLP HTTP | `OTLP_HTTP_PORT` |
| 3000 | Demo gateway | `DEMO_GATEWAY_PORT` |
| 8081 | SRE agent | `SRE_AGENT_PORT` |

Set overrides inline or in a `.env` file beside the compose file. Copy
[`.env.example`](../compose/.env.example) and keep only the values you change.

```bash
RUSH_FRONTEND_PORT=8090 docker compose --profile demo up -d
```

## Image versions

Every service pins a released tag, so a given checkout always starts the same
versions. Bump the tags in the compose file to move, then:

```bash
docker compose --profile all pull
docker compose --profile all up -d
```

## Everyday commands

```bash
# Service health
docker compose --profile demo ps

# Follow one service
docker compose --profile demo logs -f query-api

# Replace a container that is stuck restarting; a plain up will not
docker compose --profile demo up -d --force-recreate query-api

# Stop and keep data
docker compose --profile demo down

# Stop and delete all local Rush data
docker compose --profile demo down -v
```

The last command deletes the ClickHouse database and both query-api spool
volumes. ClickHouse data otherwise survives `down` in a named volume.

## What this configuration is not

The stack is built for local evaluation:

- Ingest accepts unauthenticated writes so the bundled collectors need no API
  key. query-api logs `INSECURE DEVELOPMENT OVERRIDE` at startup. To exercise
  real ingest auth, set `RUSH_ALLOW_ANONYMOUS_DEFAULT=false`, issue an
  ingest-only key, and add it to the collector and Vector configuration.
- Passwords, session secrets, and signing keys are fixed local defaults.
- Cookies are not marked secure, because nothing terminates TLS.

Telemetry never leaves the machine.

## If startup fails

Read the logs first:

```bash
docker compose --profile demo ps
docker compose --profile demo logs clickhouse query-api frontend
```

| Symptom | Cause |
|---|---|
| `Name or service not known` reaching ClickHouse | A surviving container lost its network attachment. `docker compose --profile demo down` then `up -d` reattaches everything. |
| Port already in use | Another process holds it. Override the port as shown above. |
| `403` in the collector logs | Ingest auth is required but the collectors send no key. See the section above. |
| ClickHouse rejects the password | An older volume kept different credentials. Restore them, or `down -v` if the data is disposable. |
| Traces appear but logs do not | Vector cannot read the Docker socket. Check `docker compose --profile demo logs vector`. |
| A container restarts forever | `up` will not replace it. Add `--force-recreate <service>`. |
