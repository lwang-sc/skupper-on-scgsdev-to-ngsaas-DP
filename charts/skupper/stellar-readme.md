# Stellar Skupper Helm Subchart

This directory contains a local copy of the Skupper Helm chart, used as a **subchart** by both the cloud-side and DP-side parent charts.

## About This Chart

This Skupper Helm chart was downloaded from the official source and is maintained locally for:
- Offline/air-gapped installations
- Custom modifications (grant server toggle, configurable controller namespace)
- Version control and reproducibility

**Current Version:** 2.1.3

**Source:** `oci://quay.io/skupper/helm/skupper`

## How This Subchart Is Used

This subchart is embedded in parent charts via `Chart.yaml` dependencies:

| Parent Chart | Repository | Role | Subchart Config |
|-------------|------------|------|-----------------|
| `skupper-on-scgsdev-to-ngsaas-DP` | Cloud hub (scgs-dev) | Hub site — cluster scope, grant server enabled | `skupper.enabled`, `skupper.scope: cluster` |
| `skupper-on-ngsaas-DP-to-scgsdev` | DP clusters | Spoke site — cluster scope, grant server disabled | `skupper.scope: cluster`, `skupper.grantServer.enabled: false` |

Parent charts control the subchart via the `skupper:` section in their `values.yaml`. The `condition: skupper.enabled` in `Chart.yaml` allows toggling the entire subchart on/off.

## Download History

```bash
# Original download command
helm pull oci://quay.io/skupper/helm/skupper --version 2.1.3
tar -xzf skupper-2.1.3.tgz
```

## Modifications from Official Chart

1. **Grant Server Configuration** (`values.yaml`, `templates/*-controller-deployment.yaml`)
   - Added `grantServer.enabled` option (default: `true` for hub use)
   - When `false`: `-enable-grants` and `-grant-server-autoconfigure` args are NOT passed to the controller
   - This prevents the `skupper-grant-server` LoadBalancer service from being created
   - Useful for spoke-only sites or clusters with private subnets (OCI, AWS VPCs)

2. **Documentation** (`docs/grant-server-parameters.md`)
   - Added detailed documentation explaining grant server parameters and hub vs spoke deployments

3. **Configurable Controller Namespace** (`values.yaml`, `templates/cluster-controller-deployment.yaml`, `templates/controller-namespace.yaml`)
   - Added `controllerNamespace` value (default: `""`, falls back to `.Release.Namespace`)
   - When set, the controller ServiceAccount, Deployment, and ClusterRoleBinding target that namespace instead of the Helm release namespace
   - Added `templates/controller-namespace.yaml` to create the controller namespace when `controllerNamespace` is set
   - Enables separating the controller (e.g. `skupper` namespace) from site resources (e.g. `customers` namespace) within a single Helm release

---

## Configuration

Key values in `values.yaml`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `controllerNamespace` | `""` (release namespace) | Namespace for controller deployment |
| `controllerImage` | `quay.io/skupper/controller:2.1.3` | Skupper controller image |
| `kubeAdaptorImage` | `quay.io/skupper/kube-adaptor:2.1.3` | Kubernetes adaptor image |
| `routerImage` | `quay.io/skupper/skupper-router:3.4.2` | Skupper router image |
| `scope` | `cluster` | Controller scope: `cluster` or `namespace` |
| `grantServer.enabled` | `true` | Enable grant server for hub sites |

---

## Resources Created

### Custom Resource Definitions (CRDs)

The following CRDs are installed (unless `--skip-crds` is used):

| CRD | Description |
|-----|-------------|
| `sites.skupper.io` | Defines a Skupper site (network endpoint) |
| `links.skupper.io` | Connects two Skupper sites |
| `listeners.skupper.io` | Exposes a service to the Skupper network |
| `connectors.skupper.io` | Connects to a service on the Skupper network |
| `accessgrants.skupper.io` | Grants access for linking sites |
| `accesstokens.skupper.io` | Token for establishing site links |
| `certificates.skupper.io` | TLS certificates for secure communication |
| `routeraccesses.skupper.io` | Router access configuration |
| `securedaccesses.skupper.io` | Secured access endpoints |
| `attachedconnectors.skupper.io` | Attached connector resources |
| `attachedconnectorbindings.skupper.io` | Bindings for attached connectors |

### Cluster Scope (default: `scope=cluster`)

| Resource | Name | Namespace | Description |
|----------|------|-----------|-------------|
| Namespace | `{controllerNamespace}` | — | Created when `controllerNamespace` is set |
| ServiceAccount | `skupper-controller` | `{controllerNamespace}` | Identity for the controller |
| ClusterRole | `skupper-controller` | — | Cluster-wide permissions for all Skupper CRDs |
| ClusterRoleBinding | `skupper-controller` | — | Binds role to service account |
| Deployment | `skupper-controller` | `{controllerNamespace}` | The Skupper controller deployment |

### Namespace Scope (`scope=namespace`)

| Resource | Name | Description |
|----------|------|-------------|
| ServiceAccount | `skupper-controller` | Identity for the controller |
| Role | `skupper-controller` | Namespace-scoped permissions |
| RoleBinding | `skupper-controller` | Binds role to service account |
| ConfigMap | `skupper` | Controller configuration |
| Deployment | `skupper-controller` | The Skupper controller deployment |

### Runtime Resources (Created by Controller)

When you create Skupper `Site`, `Listener`, or `Connector` CRs, the controller will create additional resources:

- **Deployments**: `skupper-router` (the AMQP router)
- **Services**: For listeners, grant server, and inter-site communication
- **Secrets**: TLS certificates and credentials
- **ConfigMaps**: Router configuration

---

## Grant Server Configuration

The grant server issues `AccessGrant` tokens that allow OTHER sites to connect TO this cluster.

| Deployment Type | `grantServer.enabled` | Description |
|-----------------|----------------------|-------------|
| **Hub** (default) | `true` | Site issues tokens for other sites to connect. Creates `skupper-grant-server` LoadBalancer. |
| **Spoke** | `false` | Site only connects outbound. No LoadBalancer created. |

See `docs/grant-server-parameters.md` for detailed documentation.

---

## References

- [Skupper Official Documentation](https://skupper.io)
- [Skupper GitHub Repository](https://github.com/skupperproject/skupper)
- Original chart README: [README.md](./README.md)
