# Networking

[← Documentation](README.md)

## Network isolation

The core chart enables NetworkPolicies for Query API, frontend, anomaly engine,
drain worker, and standalone ClickHouse. The stack adds policies for SRE agent,
OpenTelemetry Collector, Vector, PostgreSQL collector, and MySQL collector.

Default rules allow required component traffic, DNS, and same-namespace
collector ingestion. Query API does not accept traffic from every pod in the
namespace and has no broad Internet egress by default.

Enable broad destinations only when required. Prefer CIDR-specific
`extraEgress` rules when possible:

```yaml
rush:
  queryApi:
    networkPolicy:
      allowExternalHttpsEgress: true   # OIDC/SAML, webhooks, S3 buffer
      allowExternalClickHouseEgress: false
      allowSmtpEgress: false
      extraIngress: []                 # ingress controller or external collector
      extraEgress: []
    integrations:
      sreAgent:
        enabled: true
        networkPolicy:
          allowExternalHttpsEgress: true # GitHub or an external Kubernetes API
```

LLM provider traffic leaves from query-api, not the SRE agent. Allow query-api
HTTPS egress when a configured provider is outside the cluster.

The stack's PostgreSQL collector needs an explicit
`postgresCollector.networkPolicy.extraEgress` rule for the monitored database.
The MySQL collector has the same requirement under
`mysqlCollector.networkPolicy.extraEgress`; limit it to TCP 3306 on the target.
External ClickHouse needs
`allowExternalClickHouseEgress` or an explicit rule. The chart fails rendering
when a required external service would be unreachable.

## Ingress and TLS

The optional Ingress exposes the frontend, which proxies `/api`, `/auth`,
`/prom`, and `/metrics`. You can also expose a direct API host for integrations
that should not use the frontend proxy.

```yaml
rush:
  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt
    trustedProxyCidrs: [10.42.0.0/16]
    frontend:
      host: rush.example.com
      tls:
        enabled: true
        secretName: rush-tls
    api:
      enabled: true
      host: api.rush.example.com
      tls:
        enabled: true
        secretName: rush-api-tls
```

When `queryApi.config.runtime.baseUrl` is empty, the chart derives it from the
frontend TLS host. `ingress.trustedProxyCidrs` is merged into Query API's
trusted proxy list.

If the ingress controller runs outside the release namespace, add an
`extraIngress` rule matching its namespace and pod labels.
