# Operations

[← Documentation](README.md)

## Workload overrides

Shared pod defaults live under `global`. Every Rush-owned workload can override
them. Annotation and label maps merge; non-empty component lists and scalars
replace the corresponding global value.

```yaml
global:
  podAnnotations: { cluster-autoscaler.kubernetes.io/safe-to-evict: "true" }
  podLabels: { platform.example.com/tier: observability }
  imagePullSecrets: [{ name: registry-credentials }]
  priorityClassName: platform-critical
  runtimeClassName: gvisor
  extraEnvFrom: []
  extraVolumes: []
  extraVolumeMounts: []
  serviceAccount:
    annotations: { eks.amazonaws.com/role-arn: arn:aws:iam::123:role/rush }

queryApi:
  serviceAccount:
    create: true
    name: ""
    annotations: {}
```

Supported fields are `podAnnotations`, `podLabels`, `imagePullSecrets`,
`priorityClassName`, `runtimeClassName`, `extraEnvFrom`, `extraVolumes`,
`extraVolumeMounts`, and `serviceAccount.create/name/annotations`. Reserved
selector labels cannot be overridden.

## Test an installed release

Run the chart's connectivity checks after installation:

```bash
helm test rush -n observability --logs
```

The test checks Query API health and readiness, frontend availability, frontend
proxying, and optional authenticated ClickHouse connectivity. Configure it
under `helmTests`, or set `helmTests.enabled: false` to omit the hook.

## Package tests

Repository render tests remain in Git, but `.helmignore` excludes them from the
published archive. CI requires a chart-version bump for chart changes, runs the
render suite, validates and renders the package, and rejects packages that
contain `tests/`.

Versioned chart changes on `main` are published by the [release
workflow](../.github/workflows/release-charts.yml).

