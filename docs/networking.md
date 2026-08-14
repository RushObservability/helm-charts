# Networking

[← Documentation](README.md)

## Network isolation

The core chart enables NetworkPolicies for Query API, frontend, anomaly engine,
drain worker, and standalone ClickHouse. The stack adds policies for SRE agent,
OpenTelemetry Collector, Vector, and PostgreSQL collector.

Default rules allow required component traffic, DNS, and same-namespace
collector ingestion. Query API does not accept traffic from every pod in the
namespace and has no broad Internet egress by default.

Enable broad destinations only when required. Prefer CIDR-specific
`extraEgress` rules when possible:

```yaml
queryApi:
  networkPolicy:
    allowExternalHttpsEgress: true     # OIDC/SAML, webhooks, S3 buffer
    allowExternalClickHouseEgress: false
    allowSmtpEgress: false
    extraIngress: []                   # ingress controller or external collector
    extraEgress: []

global:
  sreAgent:
    enabled: true
    networkPolicy:
      allowExternalHttpsEgress: true   # OpenAI, GitHub, Kubernetes API
```

The stack's PostgreSQL collector needs an explicit
`postgresCollector.networkPolicy.extraEgress` rule for the monitored database.
External ClickHouse needs
`allowExternalClickHouseEgress` or an explicit rule. The chart fails rendering
when a required external service would be unreachable.

## Ingress and TLS

The optional Ingress exposes the frontend, which proxies `/api`, `/auth`,
`/prom`, and `/metrics`. You can also expose a direct API host for integrations
that should not use the frontend proxy.

```yaml
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

When `queryApi.baseUrl` is empty, the chart derives it from the frontend TLS
host. `ingress.trustedProxyCidrs` is merged into Query API's trusted proxy list.

If the ingress controller runs outside the release namespace, add an
`extraIngress` rule matching its namespace and pod labels.
