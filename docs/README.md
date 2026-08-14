# Helm chart documentation

Use these guides after the [quick install](../README.md#quick-install).

| Goal | Guide |
|---|---|
| Choose operator-managed, standalone, or external ClickHouse | [ClickHouse](clickhouse.md) |
| Place workloads on dedicated node groups | [Scheduling](scheduling.md) |
| Run multiple replicas and configure safe rollouts | [Reliability and high availability](reliability.md) |
| Configure NetworkPolicies, ingress, and TLS | [Networking](networking.md) |
| Manage ingest keys, secrets, sessions, and image digests | [Security](security.md) |
| Scope Kubernetes, Argo CD, Flux, and GitHub access | [Access and integrations](access-and-integrations.md) |
| Set pod overrides and test an installed release | [Operations](operations.md) |

## Reference

- [Example values](../examples/)
- [Default values](../charts/rushobservability/values.yaml)
- [Values schema](../charts/rushobservability/values.schema.json)
- [Chart source](../charts/rushobservability/)

