# Example values files

Pick the one that matches what you are doing, then set only what it asks for.
None of these are meant to be copied wholesale — they show the handful of
values each scenario needs, out of the ~613 the chart defines.

## Start here

| You want to | Use | Chart |
|---|---|---|
| Try Rush on a laptop or dev cluster | [rush-single.yaml](rush-single.yaml) | `rush-observability` |
| Install the full stack with collectors | [rush-stack.yaml](rush-stack.yaml) | `rush-observability-stack` |
| Run production with high availability | [rush-ha.yaml](rush-ha.yaml) | `rush-observability` |

## Choosing how ClickHouse runs

This is the first real decision, set by `clickhouse.mode`:

| Mode | Use | Example |
|---|---|---|
| `operator` | Default. The Altinity operator manages ClickHouse for you. | [rush-single.yaml](rush-single.yaml), [rush-ha.yaml](rush-ha.yaml) |
| `standalone` | No operator; a single plain StatefulSet. | [rush-clickhouse-standalone.yaml](rush-clickhouse-standalone.yaml) |
| `external` | You already run ClickHouse elsewhere. | [rush-clickhouse-external.yaml](rush-clickhouse-external.yaml) |

See [ClickHouse](../docs/clickhouse.md) for the trade-offs.

## Tuning a running install

| Goal | Example | Guide |
|---|---|---|
| Keep signals for longer or shorter | [rush-retention.yaml](rush-retention.yaml) | [Operations](../docs/operations.md) |
| Move old data to S3 | [rush-s3-tiering.yaml](rush-s3-tiering.yaml) | [ClickHouse](../docs/clickhouse.md) |
| Pin workloads to dedicated nodes | [rush-node-groups.yaml](rush-node-groups.yaml) | [Scheduling](../docs/scheduling.md) |

## Applying one

```bash
helm upgrade --install rush \
  oci://ghcr.io/rushobservability/helm-charts/rush-observability \
  --namespace observability --create-namespace \
  -f examples/rush-single.yaml
```

Values files compose, so a scenario file and a tuning file can be combined:

```bash
  -f examples/rush-ha.yaml -f examples/rush-retention.yaml
```

Later files win, so put the more specific one last.

## Where else to look

- [Chart README](../charts/rush-observability/README.md) — every value, with type and default
- [docs/](../docs/) — task-based guides
- [values.yaml](../charts/rush-observability/values.yaml) — defaults, grouped by how often you change them
