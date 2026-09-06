# Helm chart documentation

Start with [Getting started](getting-started.md). It covers installation,
login, telemetry collection, and the first production values file.

| Goal | Guide |
|---|---|
| Install Rush and sign in for the first time | [Getting started](getting-started.md) |
| Install core Rush or the complete observability stack | [Choose a chart](stack.md) |
| Choose operator-managed, standalone, or external ClickHouse | [ClickHouse](clickhouse.md) |
| Place workloads on dedicated node groups | [Scheduling](scheduling.md) |
| Run multiple replicas and configure safe rollouts | [Reliability and high availability](reliability.md) |
| Configure signal retention rules and cold storage | [Retention policy examples](../examples/rush-retention.yaml) |
| Configure NetworkPolicies, ingress, and TLS | [Networking](networking.md) |
| Manage ingest keys, secrets, sessions, and image digests | [Security](security.md) |
| Scope Kubernetes, Argo CD, Flux, and GitHub access | [Access and integrations](access-and-integrations.md) |
| Set pod overrides and test an installed release | [Operations](operations.md) |

## Reference

- [Example values](../examples/)
- [Default values](../charts/rush-observability/values.yaml)
- [Stack default values](../charts/rush-observability-stack/values.yaml)
- [Metrics-agent default values](../charts/metrics-agent/values.yaml)
- [Values schema](../charts/rush-observability/values.schema.json)
- [Chart source](../charts/rush-observability/)
