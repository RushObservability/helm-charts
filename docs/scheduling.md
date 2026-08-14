# Scheduling

[← Documentation](README.md)

In the core chart, `global.scheduling` applies to Query API, frontend, and the
anomaly engine. In `rush-observability-stack`, the same global block also
applies to SRE agent, OpenTelemetry Collector, Vector, and licensed collectors.

ClickHouse does not inherit these defaults, so its storage pods can use a
separate node group:

```yaml
global:
  scheduling:
    nodeSelector:
      nodegroup: rush-apps
    tolerations:
      - key: rush-apps
        operator: Equal
        value: "true"
        effect: NoSchedule

clickhouse:
  clickhouse:
    nodeSelector:
      nodegroup: clickhouse
    tolerations:
      - key: clickhouse
        operator: Equal
        value: "true"
        effect: NoSchedule
  keeper:
    nodeSelector:
      nodegroup: clickhouse
    tolerations:
      - key: clickhouse
        operator: Equal
        value: "true"
        effect: NoSchedule
  # These are control-plane workloads, not ClickHouse data pods.
  operator:
    nodeSelector:
      nodegroup: rush-apps
    tolerations:
      - key: rush-apps
        operator: Equal
        value: "true"
        effect: NoSchedule
    crdHook:
      nodeSelector:
        nodegroup: rush-apps
      tolerations:
        - key: rush-apps
          operator: Equal
          value: "true"
          effect: NoSchedule
```

Every Rush workload has a `scheduling` override. `nodeSelector` and `affinity`
maps merge with global maps. `tolerations` and `topologySpreadConstraints`
replace the global lists when set locally.

For example, this keeps the global affinity and tolerations but moves Query API
to a different node group:

```yaml
queryApi:
  scheduling:
    nodeSelector:
      nodegroup: rush-api
```

Set `inheritGlobalScheduling: false` on a workload to ignore global scheduling.
In the stack, this is useful for `collectors.vector`, whose DaemonSet otherwise
runs only on nodes matching the global selector. Core component overrides live
under `rush-observability` when using the stack.

Standalone ClickHouse uses `clickhouseStandalone.nodeSelector`, `tolerations`,
`affinity`, and `topologySpreadConstraints`. The bundled operator uses the
corresponding `clickhouse.operator` and `clickhouse.operator.crdHook` values.

See [the node-group example](../examples/rush-node-groups.yaml).
