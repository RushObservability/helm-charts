# Networking

[← Documentation](README.md)

## Network isolation

NetworkPolicies are enabled for Query API, frontend, SRE agent, anomaly engine,
OpenTelemetry Collector, Vector, PostgreSQL collector, drain worker, and
standalone ClickHouse.

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

sreAgent:
  enabled: true
  networkPolicy:
    allowExternalHttpsEgress: true     # OpenAI, GitHub, Kubernetes API
```

The PostgreSQL collector needs an explicit `networkPolicy.extraEgress` rule for
the monitored database. External ClickHouse needs
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

