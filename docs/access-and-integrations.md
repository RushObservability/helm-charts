# Access and integrations

[← Documentation](README.md)

## Query API infrastructure access

Kubernetes, Argo CD, and Flux pages require the separate
`infrastructure:read` group permission. Telemetry viewers do not receive it.

The active Rush tenant comes from group tenant bindings.
`queryApi.integrations.infrastructure.tenantNamespaces` maps that
tenant to the Kubernetes namespaces it may inspect:

```yaml
queryApi:
  integrations:
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

Cluster-wide Kubernetes browsing requires both
`queryApi.integrations.kubernetes.clusterWide: true` and a `"*"` namespace
grant. This adds nodes and namespaces but never Secrets. Kubernetes API access
also needs `queryApi.networkPolicy.allowExternalHttpsEgress: true` or a narrower
egress rule.

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
rush:
  queryApi:
    integrations:
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
rush:
  queryApi:
    integrations:
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

## Kubernetes access recording

The licensed Kubernetes access recorder is off by default. Enable the query
API endpoints and bounded storage limits with:

```yaml
queryApi:
  integrations:
    kubernetesAccess:
      enabled: true
      maxResultBytes: 262144
      maxSessionBytes: 67108864
      retentionDays: 30
      retainRawIp: false
      collectPrivateIp: false
      credentialTtlSeconds: 3600

enterprise:
  license:
    enabled: true

kubernetesAccessGateway:
  enabled: true
  gatewayId: primary
  clusterId: prod-us-east-1
  tenantIds: [default]
  # Use a platform-managed service account with a reviewed impersonation role.
  serviceAccount:
    create: false
    name: rush-kube-proxy
  tls:
    existingSecret: rush-kube-gateway-tls
```

The chart creates a random internal recorder token in the bootstrap Secret and
preserves it across upgrades. If `queryApi.config.secrets.existingSecret` is
set, add a `kubernetes-access-internal-token` key to that Secret instead.

Keep `retainRawIp` and `collectPrivateIp` disabled unless the tenant has an
approved retention and privacy policy. The Rush exec-credential helper reports
its operating system, architecture, CLI version, hostname label, and a
best-effort copy of the parent `kubectl` command. These unverified fields are
shown for investigation context and are never used for access decisions.
Common credential arguments are redacted on the device and again by query-api.
Private addresses are discarded unless `collectPrivateIp` is enabled. The
internal recorder token belongs only on the gateway or another trusted
in-cluster recorder. GeoIP enrichment is not part of this release.

Generate a kubeconfig with `rush kubernetes kubeconfig`. Standard `kubectl`
then connects to the gateway without a wrapper. The generated kubeconfig uses
the Rush CLI only as a Kubernetes exec credential provider, so it does not
store a credential in the file. The first `kubectl` request opens the Rush login
page. The user signs in with local auth or SSO, reviews the cluster, and approves
a temporary credential. API keys are not accepted for Kubernetes access.

The gateway service account needs permission to impersonate the approved
Kubernetes users and groups. The chart does not grant that permission by
default. Set `rbac.createImpersonationRole: true` only if the broad generated
ClusterRole has been reviewed for that cluster.

`credentialTtlSeconds` is the initial credential lifetime, from 5 minutes to 12
hours. After deployment, an administrator can change it under **Settings →
Integrations → Kubernetes logging**. The saved setting applies to new approvals
and takes precedence over the chart value.

That page also lists live kubectl clients. De-auth one client or all clients to
block new requests immediately; the next normal `kubectl` command opens Rush
login again. An exec, logs, or port-forward stream that is already open can run
until it ends. Login requests, credentials, and revocations live in ClickHouse,
so the same policy works across query-api replicas. The one-time approval claim
uses the configured shared replay store when query-api has several pods.

Rush maps the signed-in user's current role to a tenant-bound group such as
`rush:tenant:default:role:write`. Kubernetes RBAC decides whether that group can
read, mutate, or open `pods/exec`.

Rush decides who the caller is; Kubernetes RBAC still decides what that caller
may do. For namespace-scoped exec access, bind the generated write group:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: rush-kubectl-write
  namespace: payments
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec", "pods/attach"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: rush-kubectl-write
  namespace: payments
subjects:
  - kind: Group
    name: rush:tenant:default:role:write
    apiGroup: rbac.authorization.k8s.io
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: rush-kubectl-write
```

Create a separate binding in each approved namespace. Do not bind these groups
to `cluster-admin`. Every recorded request carries the Rush user who approved
the temporary credential.

The gateway NetworkPolicy allows same-namespace ingress and HTTPS egress by
default. If clients arrive through an ingress controller in another namespace,
add that namespace and pod selector under `networkPolicy.extraIngress`. Use
`allowExternalIngress: true` only when the gateway Service is intentionally
public. Configure `trustedProxyCidrs` for the ingress proxy; forwarded client
addresses from every other peer are ignored. The default upstream egress CIDR
is `0.0.0.0/0` because Kubernetes control-plane addresses vary by platform;
replace `upstream.egressCidrs` with the narrow API endpoint CIDRs available in
your environment.
