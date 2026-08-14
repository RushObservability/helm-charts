# ClickHouse

[← Documentation](README.md)

Rush supports three ClickHouse deployment modes.

## Operator-managed

The default `clickhouse.mode: operator` uses the bundled Altinity ClickHouse
Operator. Use this mode in production when you want the operator to manage
configuration, storage, scaling, upgrades, and cluster reconciliation.

## Standalone

Use the operator-free profile for a single ClickHouse pod:

```bash
helm install rush rush/rushobservability \
  --namespace observability --create-namespace \
  -f examples/rush-clickhouse-standalone.yaml
```

This creates one StatefulSet, Service, PVC, and configuration Secret. It does
not provide replicated ClickHouse or Keeper-based high availability.

See [the standalone example](../examples/rush-clickhouse-standalone.yaml).

## External

To connect Rush to an existing ClickHouse deployment:

```yaml
queryApi:
  networkPolicy:
    allowExternalClickHouseEgress: true # or add a CIDR-specific extraEgress rule

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

