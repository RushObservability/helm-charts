# Reliability and high availability

[← Documentation](README.md)

## High-availability ingest buffering

A pod-local disk queue is the default for one Query API replica. It is unsafe
for multiple replicas because another pod cannot replay telemetry stranded on a
failed node.

When `queryApi.replicas` is greater than one, configure an S3-compatible shared
buffer. The chart then deploys exactly one drain worker.

Create the object-store Secret:

```bash
kubectl -n observability create secret generic rush-ingest-buffer \
  --from-literal=access-key='<access-key>' \
  --from-literal=secret-key='<secret-key>'
```

Configure the buffer and ClickHouse Keeper:

```yaml
queryApi:
  replicas: 3
  buffer:
    backend: object_store
    maxBytes: 2147483648
    objectStore:
      endpoint: "" # blank for AWS; set for MinIO, Ceph, or RustFS
      bucket: rush-ingest-buffer
      prefix: ingest/
      region: us-east-1
      credentialsSecret:
        name: rush-ingest-buffer
        accessKeyKey: access-key
        secretKeyKey: secret-key
    drainWorker:
      enabled: true
  networkPolicy:
    allowExternalHttpsEgress: true # or add a bucket-specific extraEgress rule

clickhouse:
  keeper:
    enabled: true
```

API pods enqueue objects but do not replay them when the worker is enabled. The
worker has one replica and uses a `Recreate` rollout so two drainers cannot run
during an upgrade. Credentials come only from the named Secret.

The chart rejects multi-replica values that omit these requirements. See [the
HA example](../examples/rush-ha.yaml).

## Rollouts and disruption budgets

First-party Deployments expose a `rollout` block. Each workload also exposes an
optional `podDisruptionBudget`.

Stateless serving paths default to zero-unavailable rolling updates. Singleton
consumers such as the anomaly engine, PostgreSQL collector, and ingest drain
worker default to `Recreate` to avoid duplicate work.

```yaml
queryApi:
  rollout:
    strategy: RollingUpdate
    maxUnavailable: 0
    maxSurge: 1
    minReadySeconds: 10
    progressDeadlineSeconds: 600
    revisionHistoryLimit: 10
  podDisruptionBudget:
    enabled: true
    type: minAvailable # or maxUnavailable
    value: 2           # integer or percentage
```

Do not set `minAvailable: 1` on a singleton unless you intend to block
voluntary node drains. OpenTelemetry Collector and Vector DaemonSets also have
configurable update strategies. Standalone ClickHouse exposes its StatefulSet
update strategy and PDB under `clickhouseStandalone`.

## Health probes and validation

Query API, frontend, SRE agent, OpenTelemetry Collector, and standalone
ClickHouse expose startup, readiness, and liveness settings. A startup probe
protects slow initialization from premature liveness restarts.

```yaml
queryApi:
  probes:
    startup:
      enabled: true
      path: /healthz
      initialDelaySeconds: 0
      periodSeconds: 5
      timeoutSeconds: 2
      failureThreshold: 60
      successThreshold: 1
```

The included `values.schema.json` validates core enums, numeric ranges, image
digests, rollout/PDB/probe shapes, and the HA buffer contract during `helm
lint`, `helm template`, install, and upgrade.

