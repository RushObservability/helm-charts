# Security Policy

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
pull requests, or discussions.**

Report privately through GitHub Security Advisories:

1. Go to the [Security tab](https://github.com/RushObservability/helm-charts/security)
2. Click **Report a vulnerability**

This opens a private channel visible only to the maintainers.

### What to include

- The affected chart and version, and the commit you tested
- The rendered manifest or values that demonstrate the issue
- Impact: what an operator or attacker can achieve on a cluster

### What to expect

- **Acknowledgement** within 5 business days.
- **Initial assessment**, including severity, within 10 business days.
- **Progress updates** at least every 10 business days until resolution.
- **Credit** in the advisory and release notes, unless you prefer anonymity.

We ask for a reasonable opportunity to ship a fix before public disclosure, and
aim to release fixes for confirmed high and critical issues within 90 days.

## Supported Versions

Charts are versioned independently. Security fixes land on `main` and in the
next chart release; there are no backports to earlier chart versions.

## Scope

These charts deploy the Rush Observability platform into Kubernetes clusters,
so they shape the security posture of every install. Reports touching the
following are especially valuable:

- Rendered manifests that grant more privilege than required — cluster-wide
  RBAC, `privileged`, `hostNetwork`, `hostPath`, or running as root
- Secrets rendered into ConfigMaps, annotations, environment variables, or
  anywhere else they would be readable
- Default values that expose a service outside the cluster unintentionally
- Chart or subchart dependencies pulled from a source that is not pinned

**Out of scope:** issues in your own values overrides, vulnerabilities in
upstream container images themselves (report those upstream), and findings from
automated scanners with no demonstrated impact on a rendered manifest.

## Our Automated Security Practices

- `helm lint --strict`, render tests, and packaged-archive validation on every
  pull request and push to `main`
- A chart version bump is required whenever a chart changes
- Dependabot version updates for Helm chart dependencies and GitHub Actions,
  plus Dependabot alerts against the GitHub Advisory Database
- Dependency review blocks pull requests introducing vulnerable dependencies
- OpenSSF Scorecard tracks supply-chain posture
- All GitHub Actions are pinned to full commit SHAs
- Workflow tokens are least-privilege; registry write is scoped to the single
  job that publishes
