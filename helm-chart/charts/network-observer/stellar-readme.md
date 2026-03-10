# Stellar Skupper Network Observer Subchart

This directory contains a local copy of the Skupper Network Observer Helm chart, used as a **subchart** by the cloud-side parent chart.

## About This Chart

The Network Observer provides the Skupper Console UI and telemetry collection. It attaches to the Skupper router to collect operational data from ALL sites in the network.

**Current Version:** 2.1.3

**Source:** `oci://quay.io/skupper/helm/network-observer`

## How This Subchart Is Used

Embedded in the parent chart `skupper-on-scgsdev-to-ngsaas-DP` via `Chart.yaml` dependency:

```yaml
dependencies:
  - name: network-observer
    version: "2.1.3"
    repository: "file://charts/network-observer"
    condition: network-observer.enabled
```

The parent chart overrides these values:

| Parameter | Parent Override | Why |
|-----------|---------------|-----|
| `fullnameOverride` | `skupper-network-observer` | Match existing service name on scgs-dev |
| `service.type` | `LoadBalancer` | External access to console UI |
| `auth.strategy` | `none` | No authentication required |
| `tls.skupperIssued` | `true` | TLS cert issued by Skupper controller |

## Download History

```bash
helm pull oci://quay.io/skupper/helm/network-observer --version 2.1.3
tar -xzf network-observer-2.1.3.tgz
```

## Modifications from Official Chart

**None.** This chart is used as-is from the official source. All customization is done via parent chart value overrides.

## Requirements

- Must be deployed in the **same namespace** as the Skupper Site (`customers`)
- Connects to `skupper-router-local` service in that namespace
- Requires a running Skupper Site with an active router

## Resources Created

| Resource | Name | Description |
|----------|------|-------------|
| Deployment | `skupper-network-observer` | Observer + Prometheus + Nginx containers |
| Service | `skupper-network-observer` | LoadBalancer for console access |
| ConfigMap | `skupper-network-observer-nginx` | Nginx reverse proxy config |
| ConfigMap | `skupper-network-observer-prometheus` | Prometheus scrape config |
| Certificate | `skupper-network-observer-client` | Client cert for router connection |
| Certificate | `skupper-network-observer-tls` | Server TLS cert (skupper-issued) |

## References

- [Skupper Console Documentation](https://skupper.io/docs/console/index.html)
- [Network Observer GitHub](https://github.com/skupperproject/skupper-console)
- Original chart README: [README.md](./README.md)
