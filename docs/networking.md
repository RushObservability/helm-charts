# Networking

[← Documentation](README.md)

## Network isolation

The core chart enables NetworkPolicies for Query API, frontend, anomaly engine,
drain worker, and standalone ClickHouse. The stack adds policies for SRE agent,
OpenTelemetry Collector, and Vector.

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

External ClickHouse needs
`allowExternalClickHouseEgress` or an explicit rule. The chart fails rendering
when a required external service would be unreachable.

## Ingress and TLS

The optional Ingress exposes the frontend, which proxies `/api`, `/auth`, and
`/prom`. You can also expose a direct API host for integrations that should not
use the frontend proxy. The direct API host serves every Query API path,
including the unauthenticated `/metrics`.

```yaml
rush:
  queryApi:
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
frontend TLS host. `queryApi.ingress.trustedProxyCidrs` is merged into Query API's
trusted proxy list.

If the ingress controller runs outside the release namespace, add an
`extraIngress` rule matching its namespace and pod labels.

## Prometheus metrics

Query API serves its Prometheus metrics at `/metrics` without authentication.
Scrape the Service inside the cluster at
`http://<release>-query-api.<namespace>.svc:8080/metrics`, and admit the scraper
through the Query API NetworkPolicy:

```yaml
rush:
  queryApi:
    networkPolicy:
      extraIngress:
        - from:
            - namespaceSelector:
                matchLabels:
                  kubernetes.io/metadata.name: monitoring
              podSelector:
                matchLabels:
                  app.kubernetes.io/name: prometheus
          ports:
            - protocol: TCP
              port: 8080
```

The frontend no longer proxies `/metrics` by default, because that published
the endpoint to anyone who could reach the UI. The admin Capacity page reads
`/metrics` through the frontend and shows an error while the proxy is off. Set
`frontend.proxyQueryApiMetrics: true` to restore it only when the UI is reachable
by trusted users alone.
