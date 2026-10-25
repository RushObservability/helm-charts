# Reliability and high availability

[← Documentation](README.md)

## Persistent outboxes

The default single-replica Query API Deployment stores its disk ingest queue on
a retained 4 GiB PVC and its audit outbox on a separate retained 1 GiB PVC.
`Recreate` upgrades stop the old pod before starting its replacement, avoiding
overlapping writers and cross-node attachment conflicts on ReadWriteOnce volumes.
Expect a brief API outage during a singleton upgrade.

Configure storage with `queryApi.ingestSpoolPersistence` and
`queryApi.auditSpoolPersistence`. Both accept `size`, `storageClass`,
`accessModes`, and `existingClaim`. An empty storage class uses the cluster's
default, while `"-"` selects no storage class. Existing claims are operator-owned;
the chart does not create or resize them. Keep ingest and audit on different
claims. Allow space above `queryApi.config.ingest.buffer.maxBytes` and
`queryApi.config.audit.spoolMaxBytes` for filesystem overhead.

The storage driver must support writes by group 999 through Kubernetes `fsGroup`
or pre-provisioned permissions. A non-root init container creates an app-owned
`outbox/` under the audit volume and `queue/` under the disk ingest volume. It
moves legacy top-level `*.json` audit records and `*.spool` ingest segments into
those directories. It fails on duplicate names or invalid entries instead of
overwriting them. This lets each writer set private directory permissions
without owning the volume root. The helper image is digest-pinned and configurable under
`queryApi.spoolInit`; include it in private registry mirrors.

A PVC preserves data across pod replacement, subject to the storage driver's
durability and attachment behavior. A node-local storage class cannot recover
data after permanent loss of that node. Use storage with the recovery guarantees
your deployment needs. Setting persistence `enabled: false` uses `emptyDir` and
is intended only for disposable tests; production disk ingest rejects this.

## High-availability ingest buffering

When `queryApi.replicas` is greater than one, configure an S3-compatible shared
ingest buffer, a singleton drain worker, ClickHouse Keeper, and
`queryApi.workloadKind: StatefulSet`. Each API ordinal gets its own audit claim,
so replicas can run on different nodes without sharing a ReadWriteOnce volume.
HA needs Query API `0.1.8` or later (the chart default): it carries the
independent audit-writer chain fix from
[query-api PR 38](https://github.com/RushObservability/query-api/pull/38) and
creates a single bootstrap admin when replicas start together.

Create the object-store Secret:

```bash
kubectl -n observability create secret generic rush-ingest-buffer \
  --from-literal=access-key='<access-key>' \
  --from-literal=secret-key='<secret-key>'
```

Configure the buffer and ClickHouse Keeper:

```yaml
queryApi:
  workloadKind: StatefulSet
  replicas: 3
  config:
    ingest:
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
during an upgrade. Its audit outbox uses a dedicated retained PVC configured by
`queryApi.drainWorker.auditSpoolPersistence`. Credentials come only from the named
Secret.

StatefulSet audit claims are named `audit-spool-<query-api-name>-<ordinal>`.
Kubernetes retains these claims on scale-down and controller deletion. Pending
events on a removed ordinal remain there until that ordinal returns. Drain its
audit backlog before scaling down, or retain the claim and arrange recovery.
The chart rejects a shared `auditSpoolPersistence.existingClaim` with multiple
replicas. Changing a StatefulSet claim template's size or storage class requires
an operator-managed volume migration; Helm cannot update those immutable fields.

The chart rejects multi-replica values that omit these requirements. See [the
HA example](../examples/rush-ha.yaml).

## Upgrading existing installations

Core chart 0.5.0 and stack chart 0.4.0 introduce these storage defaults. Stack
installations put all `queryApi` settings below `rush:`. Reapply your saved user
overrides with `--reset-values -f <overrides.yaml>` so Helm incorporates the new
defaults. Avoid `--reuse-values` across this upgrade because it retains old chart
defaults and can omit required new fields. An old explicit `RollingUpdate`
setting now needs `queryApi.rollout.strategy: Recreate` for a Deployment.

Before replacing a pod from an older chart, pause incoming writes and let both
ingest and audit queues drain while ClickHouse is healthy. Verify
`rush_ingest_spool_segments` and `rush_audit_outbox_events` reach zero. The old
ingest `emptyDir`, and the old drain worker's audit
`emptyDir`, cannot be recovered after pod deletion. If either queue cannot drain,
preserve it with an operator-controlled backup and recovery procedure before
continuing. Merely allocating the new PVC does not migrate old `emptyDir` data.

A normal singleton upgrade preserves the existing `<release>-query-api-audit`
claim and creates `<release>-query-api-ingest`. The init container migrates pending
audit records within the existing claim before the app starts. Retain a backup
and the original audit signing keys. Rolling back to an older chart requires
stopping the writer and moving remaining `outbox/*.json` and `queue/*.spool` back
to their respective volume roots, without overwriting any files, because the
older chart reads those locations. Keep the ingest PVC mounted on rollback;
returning to the old chart's `emptyDir` discards access to that backlog.

Changing `queryApi.workloadKind` requires a maintenance window:

1. Pause incoming writes, drain or preserve both outboxes, and back up the claims
   and bootstrap Secret. For an old HA Deployment, inspect every pod's local queue.
2. Stop reconciliation, scale the old controller to zero, and wait for all its
   pods to terminate. Delete the old controller, keeping its PVCs and Secret.
3. Upgrade with the new workload kind. For a singleton, `existingClaim` can
   reattach the old ingest and audit claims. For HA, use per-ordinal claim
   templates and recover any retained backlog before abandoning the old claim.
4. Verify readiness, delivery, and audit verification before resuming writes.

A live Helm upgrade refuses a controller-kind change while the old controller
exists. Offline `helm template` and GitOps rendering cannot perform that cluster
lookup, so operators must enforce the same migration order themselves. Do not
force-delete a pod or reattach its outbox while its old process may still write.

## Rollouts and disruption budgets

First-party Deployments expose a `rollout` block. Each workload also exposes an
optional `podDisruptionBudget`.

The frontend defaults to zero-unavailable rolling updates. The default Query API
Deployment and singleton consumers use `Recreate`. Query API StatefulSets replace
one ordinal at a time, reusing that ordinal's claims. They use `Parallel` pod
management for startup and scaling so one unready audit outbox does not block
other replicas from starting. StatefulSets honor `rollout.minReadySeconds` and
`revisionHistoryLimit`; Deployment-only strategy, surge, and deadline settings
do not apply.

```yaml
queryApi:
  workloadKind: StatefulSet # with the HA buffer settings above
  rollout:
    minReadySeconds: 10
    revisionHistoryLimit: 10
  podDisruptionBudget:
    enabled: true
    type: minAvailable # or maxUnavailable
    value: 2           # integer or percentage
```

Do not set `minAvailable: 1` on a singleton unless you intend to block
voluntary node drains. The stack's OpenTelemetry Collector and Vector
DaemonSets also have configurable update strategies. Standalone ClickHouse
exposes its StatefulSet update strategy and PDB under `clickhouseStandalone`.

## Health probes and validation

Query API, frontend, and standalone ClickHouse expose startup, readiness, and
liveness settings. The stack adds the same controls for SRE agent and
OpenTelemetry Collector. A startup probe protects slow initialization from
premature liveness restarts.

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
