# Skupper Cloud Hub Chart — skupper-on-scgsdev-to-ngsaas-DP

This Helm chart manages the complete Skupper deployment on the cloud hub cluster (scgs-dev), including the controller, Site, and all service exposure (Listeners, Connectors, Bridge Services).

**Chart location:** `helm-chart/` (same layout as the companion DP repo `skupper-on-ngsaas-DP-to-scgsdev`).

This chart runs on scgs-dev and handles the cloud side for **all** DP clusters. For each DP's own resources, see the companion chart `skupper-on-ngsaas-DP-to-scgsdev`.

## Overview

Using dev-dp6's MongoDB and Kafka connection as an example:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           scgs-dev (Hub Cluster)                            │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │  skupper namespace                                                 │     │
│  │  Controller (cluster scope) + Grant Server                         │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │  customers namespace — Skupper Site: scgs-dev                      │     │
│  │                                                                    │     │
│  │  MongoDB Listeners              Kafka Connectors                   │     │
│  │  ┌─────────────────────────┐   ┌───────────────────────────────┐  │     │
│  │  │ ns-dev--dev-dp6--       │   │ Bootstrap: scgs-dev-kafka     │  │     │
│  │  │   stellar-conf-mongo    │   │ Broker-0:  ...-broker-0       │  │     │
│  │  │ ns-dev--dev-dp6--       │   │ Broker-1:  ...-broker-1       │  │     │
│  │  │   stellar-data-mongo    │   │ Broker-2:  ...-broker-2       │  │     │
│  │  │ ns-dev--dev-dp6--       │   │ → via bridge svcs to ykou ns  │  │     │
│  │  │   stellar-user-mongo    │   └───────────────────────────────┘  │     │
│  │  └─────────────────────────┘                                      │     │
│  └──────────────────────────┬─────────────────────────────────────────┘     │
│                              │                                              │
│  ┌───────────────────────────┼────────────────────────────────────────┐     │
│  │  scai-dev namespace       │  (Bridge Services for dev-dp6)         │     │
│  │  ExternalName → customers │  ns-dev--dev-dp6--stellar-*-mongo      │     │
│  └───────────────────────────┼────────────────────────────────────────┘     │
│                              │                                              │
└──────────────────────────────┼──────────────────────────────────────────────┘
                               │ Skupper Links (mTLS)
                               │
┌──────────────────────────────┼──────────────────────────────────────────────┐
│                              │                                              │
│  ┌───────────────────────────┴────────────────────────────────────────┐     │
│  │  cloud--scgs-dev namespace — Skupper Site: ngsaas--dev-dp6--...    │     │
│  │                                                                    │     │
│  │  MongoDB Connectors (DP chart)     Kafka Listeners (DP chart)      │     │
│  │  ┌─────────────────────────┐   ┌───────────────────────────────┐  │     │
│  │  │ stellar-conf-mongo      │   │ Bootstrap: kafka:9092         │  │     │
│  │  │ stellar-data-mongo      │   │ Broker-0: kafka-broker-0:9192 │  │     │
│  │  │ stellar-user-mongo      │   │ Broker-1: kafka-broker-1:9192 │  │     │
│  │  │ → Exposes MongoDB pods  │   │ ...+ bridge svcs in default   │  │     │
│  │  └─────────────────────────┘   └───────────────────────────────┘  │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│                           dev-dp6 (DP Cluster)                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## What This Chart Manages

| Layer | Resources | Toggle |
|-------|-----------|--------|
| **Controller** | Skupper CRDs, controller Deployment in `skupper` ns | `skupper.enabled` |
| **Site** | Site CR `scgs-dev` in `customers` ns | `site.enabled` |
| **MongoDB Listeners** | Per-DP Listeners + bridge Services in app ns | `mongodb.enabled` |
| **Kafka Connectors** | Bootstrap + per-broker Connectors + bridge Services | `kafka.bootstrap.enabled`, `kafka.brokers.enabled` |
| **AutoSOC Connector** | Connector + bridge Service (testing) | `autosocCloud.enabled` |

## Prerequisites

- Kubernetes 1.25+
- Helm 3.x
- Kafka service exists in `ykou` namespace (for Kafka connectors)
- Strimzi `advertisedHost` configured per broker
- DP clusters onboarded with matching Connectors/Listeners

## Installation

### Initial install (clean cluster — controller + observer + site + services)

```bash
helm upgrade --install skupper-scgs-dev ./helm-chart \
  -n customers \
  -f ./helm-chart/values-init.yaml
```

### Subsequent upgrades (add DPs, scale Kafka, etc. — skip controller + observer)

```bash
helm upgrade skupper-scgs-dev ./helm-chart \
  -n customers \
  -f ./helm-chart/values-services-only.yaml
```

### Verify and inspect

```bash
# Verify resources
kubectl get site,listeners,connectors -n customers

# Dry-run to see what will be created
helm template skupper-scgs-dev ./helm-chart -n customers -f ./helm-chart/values-init.yaml

# Show diff before upgrade
helm diff upgrade skupper-scgs-dev ./helm-chart -n customers --suppress-secrets
```

## Template Files

| File | Purpose | Resources Created |
|------|---------|-------------------|
| `helm-chart/charts/skupper/` | Skupper controller subchart | CRDs, ServiceAccount, ClusterRole, Deployment |
| `helm-chart/templates/00-site.yaml` | Skupper Site for the hub | Site CR |
| `helm-chart/templates/01-listeners-mongodb.yaml` | MongoDB Listeners + bridge services | Listeners + ExternalName Services |
| `helm-chart/templates/02-connectors-kafka.yaml` | Kafka bootstrap + per-broker Connectors | Connectors + ExternalName Services |
| `helm-chart/templates/03-connectors-autosoc-cloud.yaml` | AutoSOC Cloud Connector | Connector + ExternalName Service |
| `helm-chart/templates/_helpers.tpl` | Shared template helpers | — |

## Configuration

### Controller (subchart)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `skupper.enabled` | Enable Skupper controller subchart | `false` |
| `skupper.controllerNamespace` | Namespace for controller | `skupper` |
| `skupper.scope` | Controller scope | `cluster` |
| `skupper.grantServer.enabled` | Enable grant server (hub needs this) | `true` |

> **Note:** `skupper.enabled` defaults to `false` because scgs-dev currently has the controller
> installed via a standalone `skupper` Helm release. Set to `true` when ready to consolidate
> and uninstall the standalone release.

### Site

| Parameter | Description | Default |
|-----------|-------------|---------|
| `site.enabled` | Create the Skupper Site CR | `true` |
| `site.name` | Site name | `scgs-dev` |
| `site.linkAccess` | Link access mode (allows DPs to connect) | `default` |

### MongoDB Listeners

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mongodb.enabled` | Enable MongoDB Listeners | `true` |
| `mongodb.dpTypes` | List of DP types with instances and envKeys | See helm-chart/values.yaml |

Each envKey entry specifies:
- `key`: The envKey (can contain underscores, auto-sanitized for K8s names)
- `bridgeNamespace`: Namespace where the bridge service is created (`scai`, `scai-dev`)

### Kafka Connectors

| Parameter | Description | Default |
|-----------|-------------|---------|
| `kafka.bootstrap.enabled` | Enable bootstrap Connector | `true` |
| `kafka.bootstrap.name` | Connector name | `scgs-dev-kafka` |
| `kafka.bootstrap.port` | Strimzi internal listener port | `9192` |
| `kafka.brokers.enabled` | Enable per-broker Connectors | `true` |
| `kafka.brokers.replicas` | Number of broker Connectors | `3` |
| `kafka.brokers.bridgeService.targetNamespace` | Namespace where Kafka lives | `ykou` |

> **Port note:** Connectors use port 9192 (Strimzi internal listener). DP-side Listeners
> expose `kafka:9092` locally. Skupper decouples the ports — only `routingKey` must match.

### AutoSOC Cloud Connector

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autosocCloud.enabled` | Enable AutoSOC connector | `true` |
| `autosocCloud.port` | HTTP port | `8000` |
| `autosocCloud.bridgeService.targetNamespace` | Source namespace | `scai-dev` |

## Adding a New DP Cluster

1. Add the DP entry to `mongodb.dpTypes[<type>].envKeys` in helm-chart/values.yaml:

```yaml
mongodb:
  dpTypes:
    - name: ng-saas
      envKeys:
        - key: ns_dev__dev-dp6
          bridgeNamespace: scai-dev
        - key: ns_prod__salesdemo
          bridgeNamespace: scai
        - key: ns_prod__prod-dp1      # new
          bridgeNamespace: scai
```

2. Deploy:

```bash
helm upgrade skupper-scgs-dev ./helm-chart -n customers
```

3. Three new MongoDB Listeners + bridge services are created automatically.

4. On the DP side, install `skupper-on-ngsaas-DP-to-scgsdev` with matching envKey and activate the link.

## Traffic Flow

### MongoDB (Hub ← DP)

```
App (scai-dev) → Bridge Service (ExternalName) → Listener (customers) → [Skupper] → Connector (DP) → MongoDB pods
```

### Kafka (DP → Hub)

```
App (DP) → Listener (DP) → [Skupper] → Connector (customers) → Bridge Service → Kafka (ykou)
```

**Port mapping:**

| Side | Service | Port |
|------|---------|------|
| DP | `kafka` Listener — apps connect here | 9092 |
| Cloud | Bootstrap Connector → `my-cluster-kafka-bootstrap` | 9192 |
| Cloud | Broker Connectors → individual broker pods | 9192 |

## Cross-Namespace Access (Bridge Services)

Skupper Connectors can only reach pods/services in the **same namespace**. Bridge services (ExternalName) bridge namespace gaps:

- **Kafka:** `customers` → `ykou` (Kafka lives in ykou)
- **AutoSOC:** `customers` → `scai-dev` (autosoc-cloud lives in scai-dev)
- **MongoDB:** `scai`/`scai-dev` → `customers` (apps access Listeners in customers)

## Routing Key Matching

| Service | Hub (scgs-dev) | DP Cluster | Routing Key |
|---------|----------------|------------|-------------|
| MongoDB conf | Listener | Connector | `ns-dev--dev-dp6.stellar-conf-mongo` |
| MongoDB data | Listener | Connector | `ns-dev--dev-dp6.stellar-data-mongo` |
| MongoDB user | Listener | Connector | `ns-dev--dev-dp6.stellar-user-mongo` |
| Kafka bootstrap | Connector | Listener | `scgs-dev-kafka` |
| Kafka broker-0 | Connector | Listener | `scgs-dev-kafka-broker-0` |

## Naming Convention

| Field | Format | Example | Dots allowed? |
|-------|--------|---------|---------------|
| `name`/`host` | `{envKey}--{mongo}` | `ns-dev--dev-dp6--stellar-conf-mongo` | No |
| `routingKey` | `{envKey}.{mongo}` | `ns-dev--dev-dp6.stellar-conf-mongo` | Yes |

`--` (double hyphen) separates envKey from instance name since both can contain single hyphens.

## Verification

```bash
# Check all Skupper resources
kubectl get site,listeners,connectors -n customers

# Check bridge services
kubectl get svc -n customers | grep bridge

# Check MongoDB bridge services in app namespaces
kubectl get svc -n scai-dev
kubectl get svc -n scai

# Check controller (if managed by this chart)
kubectl get pods -n skupper

# Check Skupper router logs
kubectl logs -n customers -l skupper.io/component=router
```

## Troubleshooting

### Listener shows "Pending" or "No matching connectors"

1. Verify the DP cluster has a Connector with matching routingKey
2. Verify the link is established: `kubectl get links -n customers`
3. Check router logs for errors

### Connector shows "Pending"

1. Verify the target service exists in the target namespace
2. Verify the bridge service was created: `kubectl get svc -n customers | grep bridge`

### Controller not starting (when skupper.enabled=true)

1. Check RBAC: `kubectl get clusterrole skupper-controller`
2. Check the skupper namespace exists: `kubectl get ns skupper`
3. Check logs: `kubectl logs -n skupper deployment/skupper-controller`

## Related Charts

- **`skupper-on-ngsaas-DP-to-scgsdev`**: DP-side chart (controller, Site, MongoDB Connectors, Kafka Listeners); chart in `helm-chart/`
- **`helm-chart/charts/skupper/`**: Skupper controller subchart (shared with DP-side chart)
