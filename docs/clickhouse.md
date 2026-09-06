# ClickHouse

[← Documentation](README.md)

Rush supports three ClickHouse deployment modes.

The examples below use `rush-observability-stack`, where core settings are
nested under `rush`. If you install the core `rush-observability` chart, remove
the `rush` wrapper.

## Operator-managed

Operator mode uses the bundled Altinity ClickHouse Operator. Use it in
production when you want the operator to manage configuration, storage,
scaling, upgrades, and cluster reconciliation.

```yaml
rush:
  clickhouse:
    mode: operator
    enabled: true
    replicasCount: 1
    persistence:
      size: 500Gi
```

## Standalone

The stack defaults to an operator-free ClickHouse pod with a 20 GiB volume.
Increase its storage with:

```yaml
rush:
  clickhouse:
    mode: standalone
    enabled: false
  clickhouseStandalone:
    persistence:
      storageClass: fast-ssd
      size: 100Gi
```

This creates one StatefulSet, Service, PVC, and configuration Secret. It does
not provide replicated ClickHouse or Keeper-based high availability.

See [the standalone example](../examples/rush-clickhouse-standalone.yaml).

## External

To connect Rush to an existing ClickHouse deployment:

```yaml
rush:
  queryApi:
    networkPolicy:
      # Prefer a CIDR-specific extraEgress rule when possible.
      allowExternalClickHouseEgress: true
  clickhouse:
    enabled: false
    mode: external
    external:
      url: https://clickhouse.example:8443
      credentialsSecret: rush-clickhouse-credentials
      userKey: user
      passwordKey: password
      readCredentialsSecret: rush-clickhouse-read-credentials
      readUserKey: user
      readPasswordKey: password
```

Create both credential Secrets in the release namespace before installation.
The first identity owns migrations and writes. The second must be a different,
SELECT-only user limited to the telemetry tables listed under
`clickhouse.clickhouse.users` in the chart values.

External ClickHouse must set `custom_settings_prefixes` to `rush_`. Query API
refuses to start when it cannot verify that setting, strict row policies, read
grants, or separate read and write identities.

See [the external ClickHouse example](../examples/rush-clickhouse-external.yaml).
