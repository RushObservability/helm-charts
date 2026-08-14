# Access and integrations

[← Documentation](README.md)

## Query API infrastructure access

Kubernetes, Argo CD, and Flux pages require the separate
`infrastructure:read` group permission. Telemetry viewers do not receive it.

The active Rush tenant comes from group tenant bindings.
`infrastructure.tenantNamespaces` maps that tenant to the Kubernetes namespaces
it may inspect:

```yaml
infrastructure:
  tenantNamespaces:
    acme: [acme-prod, acme-staging]
    "*": [shared-observability]

kubernetes:
  enabled: true
  namespaces: [acme-prod, acme-staging, shared-observability]
  clusterWide: false

argocd:
  enabled: true
  namespace: argocd

fluxcd:
  enabled: true
  namespace: flux-system
```

Add `argocd` or `flux-system` only to tenants that should see those
integrations. The namespace map is deny-by-default: a missing tenant entry gets
`403`.

The chart creates namespace Roles for each enabled integration. Argo CD and
Flux roles contain only their CRD API groups. Query API roles never grant
Secret access.

Cluster-wide Kubernetes browsing requires both `kubernetes.clusterWide: true`
and a `"*"` namespace grant. This adds nodes and namespaces but never Secrets.
Kubernetes API access also needs
`queryApi.networkPolicy.allowExternalHttpsEgress: true` or a narrower egress
rule.

## Read-only GitHub App access

The SRE agent does not need webhooks. Create a GitHub App with only
**Repository permissions → Contents: Read-only**, install it on selected
repositories, and store its PEM key in a Kubernetes Secret:

```bash
kubectl -n <namespace> create secret generic rush-github-app \
  --from-file=private-key.pem=/path/to/github-app.private-key.pem
```

Configure an operator-owned tenant repository policy. Find a repository's
stable ID with `gh api repos/OWNER/REPO --jq .id`. The installation ID is at the
end of the installed-app settings URL.

The SRE agent is installed by `rush-observability-stack`:

```yaml
global:
  sreAgent:
    enabled: true
    networkPolicy:
      allowExternalHttpsEgress: true
    githubApp:
      enabled: true
      appId: "123456"
      tenantRepositories:
        acme:
          - repository: acme/api
            installationId: 654321
            repositoryId: 123456789
      privateKeySecret:
        name: rush-github-app
        key: private-key.pem
```

Query API and SRE agent receive the same deny-by-default policy. Only tenant
admins can create links, and callers cannot choose an installation or repository
ID.

The private key is mounted read-only. Source archives use a size-limited
`emptyDir`. The agent requests short-lived tokens scoped to `contents: read`
and the stable repository ID. Configure service-to-repository links in
Settings. Repository scripts and Git hooks are never executed.

## SRE-agent Kubernetes access

Kubernetes access is deny-by-default. Map Rush tenants to namespaces, and the
chart creates a dedicated service account with read-only RoleBindings in only
those namespaces:

```yaml
global:
  sreAgent:
    enabled: true
    kube:
      tenantNamespaces:
        acme: [acme-prod, acme-staging]
        "*": [shared-observability]
      allowClusterScopedForAdmins: false
```

By default, the agent cannot read Secrets, pod logs, nodes, or the namespace
list. Set `allowClusterScopedForAdmins: true` only for node-level diagnostics.
This adds read-only nodes and namespaces RBAC, but Query API grants the required
`kube_cluster` scope only to administrators.
