# Cloud-Side Chart Design: skupper-on-scgsdev-to-ngsaas-DP

## Overview

This chart is deployed on `scgs-dev` (in the `customers` namespace) and manages the **complete Skupper deployment** for the cloud hub — controller, Site, and service exposure for **all DP clusters** that connect to it.

**Chart location:** `helm-chart/` (aligned with the DP repo `skupper-on-ngsaas-DP-to-scgsdev`).

Unlike the DP-side chart (one install per DP), this is a single, continuously evolving deployment:

- **New DPs join** → add their envKey to the values, `helm upgrade`
- **New services to expose** → add Connectors or Listeners to templates/values, `helm upgrade`
- **Kafka scales up** → bump broker replicas, `helm upgrade`

Every change is a `helm upgrade` on the same release. The chart is designed so that adding DPs or services requires only values changes, not template modifications.

## The Asymmetry

| Chart | Deployed on | How many installs | Handles |
|-------|------------|-------------------|---------|
| `skupper-on-ngsaas-DP-to-scgsdev` (DP side) | Each NG-SaaS DP cluster | One per DP | One DP's config (pre-SaaS and on-prem DPs are not covered by this chart — they use kustomize-based provisioning) |
| `skupper-on-scgsdev-to-ngsaas-DP` (this chart) | scgs-dev only | **One** | **All DPs** |

Both charts use the same Skupper subchart (`charts/skupper/`) for the controller, but with different configurations:

| Config | Cloud Hub (this chart) | DP Side |
|--------|----------------------|---------|
| Scope | `cluster` | `cluster` |
| Controller namespace | `skupper` | `skupper` |
| Grant server | `enabled: true` (hub issues tokens) | `enabled: false` (spoke, no tokens) |
| Site type | Hub (`linkAccess: default`) | Spoke (`edge: true`) |

## Three Layers of Resources

### Layer 0: Skupper Infrastructure (toggleable)

**Controller + CRDs** — installed once, manages all Skupper resources cluster-wide.

- Deployed in `skupper` namespace (separate from site resources)
- Cluster scope — one controller handles Sites in any namespace
- Grant server enabled — issues AccessGrants for DP link activation
- Toggle: `skupper.enabled` (default `false` while standalone release exists)

**Site** — the hub site that all DPs connect to.

- Created in `customers` namespace
- `linkAccess: default` — allows incoming links from DPs
- Toggle: `site.enabled` (default `true`)

### Layer 1: Per-DP Resources (scale with number of DPs)

**MongoDB Listeners + Bridge Services** — each DP has its own MongoDB, so the hub needs a separate Listener per DP per MongoDB instance. Each Listener also gets a bridge service in the application namespace so apps can access it.

For each DP, the chart creates (per MongoDB instance):
1. **Listener** in `customers` namespace — Skupper routes traffic to the DP's MongoDB
2. **Bridge Service** (ExternalName) in the DP's `bridgeNamespace` — apps access MongoDB here

Example for salesdemo (bridgeNamespace: `scai`):

| Resource | Namespace | Name |
|----------|-----------|------|
| Listener | `customers` | `ns-prod--salesdemo--stellar-conf-mongo` |
| Bridge | `scai` | `ns-prod--salesdemo--stellar-conf-mongo` → `...customers.svc.cluster.local` |

Example for dev-dp6 (bridgeNamespace: `scai-dev`):

| Resource | Namespace | Name |
|----------|-----------|------|
| Listener | `customers` | `ns-dev--dev-dp6--stellar-conf-mongo` |
| Bridge | `scai-dev` | `ns-dev--dev-dp6--stellar-conf-mongo` → `...customers.svc.cluster.local` |

**Mechanism:** The values file uses `dpTypes[].envKeys[]` — each entry has a `key` (envKey) and `bridgeNamespace`. To onboard a new DP, add its entry to `helm-chart/values.yaml` and `helm upgrade`. The template loops over dpTypes x envKeys x instances to generate all Listeners and bridges.

### Layer 2: Shared Resources (fixed, serve all DPs)

**Kafka Connectors** — all DPs connect to the same Kafka on scgs-dev. One set of Connectors serves every DP.

- `scgs-dev-kafka` (bootstrap)
- `scgs-dev-kafka-broker-{0..N}` (per-broker)

**AutoSOC Cloud Connector** — all DPs access the same autosoc-cloud service.

- `scgs-dev--scai-dev--autosoc-cloud`

These don't change when a new DP joins.

## Namespace Layout

```
scgs-dev cluster
├── skupper namespace          ← Controller (cluster scope, grant server)
├── customers namespace        ← Site, Listeners, Connectors, Kafka/AutoSOC bridges
├── scai-dev namespace         ← MongoDB bridge services for dev DPs
├── scai namespace             ← MongoDB bridge services for prod DPs
└── ykou namespace             ← Kafka (not managed by this chart, Kafka bridges point here)
```

## Adding a New DP

When a new NG-SaaS DP cluster joins (e.g., `prod-dp1`):

**On this chart (scgs-dev side):**
1. Add the DP entry to `helm-chart/values.yaml` under `mongodb.dpTypes[ng-saas].envKeys`:
   ```yaml
   envKeys:
     - key: ns_dev__dev-dp6
       bridgeNamespace: scai-dev
     - key: ns_prod__salesdemo
       bridgeNamespace: scai
     - key: ns_prod__prod-dp1    # new
       bridgeNamespace: scai
   ```
2. `helm upgrade skupper-scgs-dev ./helm-chart -n customers`
3. Three new MongoDB Listeners + bridge services are created automatically

**On the DP side (prod-dp1):**
1. Create `values-prod-dp1.yaml` with the cluster's `dpSite.clusterName` and `envKey` (in the DP repo's `helm-chart/` directory)
2. From the DP repo: `helm install skupper-dp ./helm-chart -f helm-chart/values-prod-dp1.yaml`
3. Generate AccessGrant and activate

No template changes needed on either side — just values.

## RoutingKey Alignment

RoutingKeys must match between DP Connectors/Listeners and hub Listeners/Connectors:

### MongoDB (per-DP, DP→hub)

| DP side (Connector) | Hub side (Listener) | Match? |
|---------------------|---------------------|--------|
| `ns-prod--salesdemo.stellar-conf-mongo` | `ns-prod--salesdemo.stellar-conf-mongo` | Must match |

Both derive from the same `envKey` — the DP chart uses `chart-helper.envKeyDns` and the hub chart uses `skupper.sanitizeEnvKey` in `helm-chart/templates/_helpers.tpl`. As long as the envKey is the same in both values files, they match automatically.

### Kafka (shared, hub→DPs)

| Hub side (Connector) | DP side (Listener) | Match? |
|---------------------|---------------------|--------|
| routingKey in `kafka.bootstrap.routingKey` | `{cloud.name}-kafka` (auto-derived) | Must match |
| routingKey `{kafka.brokers.routingKeyPrefix}-{i}` | `{cloud.name}-kafka-broker-{i}` (auto-derived) | Must match |

The hub chart uses `scgs-dev-kafka` which matches what the DP chart derives from `cloud.name: scgs-dev`.

## Values Structure

```yaml
# Layer 0: Skupper infrastructure
skupper:
  enabled: false              # Toggle controller subchart
  controllerNamespace: skupper
  scope: cluster
  grantServer:
    enabled: true

site:
  enabled: true
  name: scgs-dev
  linkAccess: default

# Layer 1: Per-DP resources (add envKeys when new DPs join)
mongodb:
  dpTypes:
    - name: ng-saas
      instances: [stellar-conf-mongo, stellar-data-mongo, stellar-user-mongo]
      envKeys:
        - key: ns_dev__dev-dp6
          bridgeNamespace: scai-dev
        - key: ns_prod__salesdemo
          bridgeNamespace: scai
        # Add new NG-SaaS DPs here

# Layer 2: Shared resources (fixed, serve all DPs)
kafka:
  bootstrap: ...
  brokers: ...

autosocCloud: ...
```

See `helm-chart/values.yaml` for the full structure.

## Adding a New Service

When a new service needs to be exposed across the Skupper network:

**Per-DP service (like MongoDB)** — each DP has its own instance:
1. Add a new template (e.g., `04-listeners-redis.yaml`) with the same `dpTypes[].envKeys[]` loop pattern
2. Add a new section in `helm-chart/values.yaml` (e.g., `redis:`) with instances and the same envKeys list
3. `helm upgrade skupper-scgs-dev ./helm-chart -n customers`
4. Add matching Connectors on the DP side

**Shared service (like Kafka)** — one instance on scgs-dev serves all DPs:
1. Add a new template (e.g., `05-connectors-elasticsearch.yaml`)
2. Add a new section in `helm-chart/values.yaml` with the connector/listener config
3. `helm upgrade skupper-scgs-dev ./helm-chart -n customers`
4. Add matching Listeners on the DP side

## Controller Consolidation Plan

Currently on scgs-dev, the Skupper controller is installed via a standalone `skupper` Helm release (v2.1.2, namespace scope). This chart includes the same controller as a subchart but defaults to `skupper.enabled: false`.

To consolidate into a single release:
1. Set `skupper.enabled: true` in helm-chart/values.yaml
2. `helm upgrade skupper-scgs-dev ./helm-chart -n customers`
3. Verify the new controller is running: `kubectl get pods -n skupper`
4. `helm uninstall skupper -n customers` (remove the standalone release)

This upgrades from namespace scope to cluster scope and from v2.1.2 to v2.1.3.

## Deployment Flow

```
helm upgrade --install skupper-scgs-dev ./helm-chart -n customers
```

Every change — new DPs, new services, scaling — is a `helm upgrade` on this single release.

## ArgoCD Integration

This chart is designed for GitOps with ArgoCD:

- One ArgoCD Application → one Helm release → manages everything
- Controller toggle (`skupper.enabled`) prevents duplicate controller installs during migration
- Site and service exposure changes are values-only — no template edits needed
- ArgoCD auto-sync safely re-applies identical manifests (no disruption to Site or Links)
