# Skupper Controller Grant Server Parameters

This document explains the `-enable-grants` and `-grant-server-autoconfigure` parameters used by the Skupper controller.

## Overview

The Skupper controller can run a **Grant Server** that handles `AccessGrant` resources. This server is used to issue tokens that allow other Skupper sites to connect to this site. These parameters control whether and how the grant server operates.

## Parameters

### `-enable-grants`

| Property | Value |
|----------|-------|
| Environment Variable | `SKUPPER_ENABLE_GRANTS` |
| Type | Boolean |
| Default | `false` |
| Description | Enable use of AccessGrants |

**What it does when enabled (`true`):**
- Starts the grant server to handle `AccessGrant` resources
- Watches for `AccessGrant` resources in Kubernetes
- Generates link configuration tokens for secure site-to-site connections
- Manages TLS credentials for the grant server

**What it does when disabled (`false`):**
- The grant server is NOT started
- Any `AccessGrant` resources created will be marked with status: "AccessGrants are not enabled"
- The site can still function as a spoke (using `AccessToken` to connect outbound)

### `-grant-server-autoconfigure`

| Property | Value |
|----------|-------|
| Environment Variable | `SKUPPER_GRANT_SERVER_AUTOCONFIGURE` |
| Type | Boolean |
| Default | `false` |
| Description | Automatically configure the URL and TLS credentials for the AccessGrant Server |

**What it does when enabled (`true`):**
- Creates a `Certificate` resource (`skupper-grant-server-ca`) as a CA for signing
- Creates a `SecuredAccess` resource (`skupper-grant-server`) that configures:
  - TLS certificates
  - External URL/endpoint for the grant server
- Watches `SecuredAccess` changes to dynamically update the grant server URL
- Delays server startup until the endpoint URL is ready

**What it does when disabled (`false`):**
- The grant server starts immediately (if `-enable-grants=true`)
- You must manually configure:
  - TLS credentials
  - The grant server URL (`-base-url` flag or `SKUPPER_GRANT_SERVER_BASE_URL`)

## Code Path

```
cmd/controller/main.go
    └── controller.BoundConfig(flags)
            └── internal/kube/controller/config.go
                    └── grants.BoundGrantConfig(flags)
                            └── internal/kube/grants/config.go

Controller initialization:
    └── internal/kube/controller/controller.go: NewController()
            └── grants.Initialise(config)
                    └── internal/kube/grants/init.go
                            ├── if config.Enabled → enabled()
                            │       └── internal/kube/grants/enabled.go
                            │               └── if config.AutoConfigure → newAutoConfigure()
                            │                       └── internal/kube/grants/autoconfigure.go
                            └── if !config.Enabled → disabled()
                                    └── internal/kube/grants/disabled.go
```

## Service Type for `skupper-grant-server`

When `-grant-server-autoconfigure=true`, the controller creates a `SecuredAccess` resource **without** an explicit `AccessType`. The actual service type is determined by the controller's default access type configuration:

### Default Access Type Resolution

1. On **OpenShift**: Uses `route` (if route client is available and enabled)
2. On **Kubernetes**: Uses `loadbalancer` (if enabled)
3. Otherwise: Uses the first entry in `-enabled-access-types`

### Controlling the Access Type

You can control the service type using these controller flags:

| Flag | Environment Variable | Description |
|------|---------------------|-------------|
| `-default-access-type` | `SKUPPER_DEFAULT_ACCESS_TYPE` | Explicitly set the default access type |
| `-enabled-access-types` | `SKUPPER_ENABLED_ACCESS_TYPES` | List of enabled access types |

**Available access types:**
- `loadbalancer` - Kubernetes LoadBalancer Service
- `route` - OpenShift Route
- `nodeport` - Kubernetes NodePort Service (requires `-cluster-host`)
- `ingress-nginx` - NGINX Ingress (requires `-ingress-domain`)
- `contour-http-proxy` - Contour HTTPProxy (requires `-http-proxy-domain`)
- `gateway` - Kubernetes Gateway API (requires `-gateway-class`)
- `local` - ClusterIP Service (internal only)

## Hub vs Spoke Deployment Scenarios

### Scenario 1: Hub Site (Issues Tokens)

A hub site that needs to issue `AccessGrant` tokens for other sites to connect.

```yaml
args:
  - "-enable-grants"
  - "-grant-server-autoconfigure"
```

This creates:
- A grant server listening for token requests
- A `SecuredAccess` resource (`skupper-grant-server`)
- An external endpoint (LoadBalancer/Route/etc.) for token distribution

### Scenario 2: Spoke Site (Connects Outbound Only)

A spoke site that only uses `AccessToken` to connect to other hubs. It does not need to issue tokens.

```yaml
args: []
# Or explicitly:
# args:
#   - "-enable-grants=false"
```

Benefits:
- No LoadBalancer service created
- No external exposure required
- Reduced resource usage
- Site can still connect outbound using `AccessToken` resources

### Scenario 3: Hub with Manual Configuration

A hub site where you want to manually control TLS certificates and URLs.

```yaml
args:
  - "-enable-grants"
  - "-base-url=https://grants.example.com"
  - "-tls-credentials=my-tls-secret"
```

## Summary Table

| Deployment Type | `-enable-grants` | `-grant-server-autoconfigure` | External Service Created |
|-----------------|------------------|-------------------------------|-------------------------|
| Hub (auto-config) | `true` | `true` | Yes (LoadBalancer/Route) |
| Hub (manual config) | `true` | `false` | No (manual setup) |
| Spoke only | `false` | N/A | No |

## AccessGrant and AccessToken Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                           HUB SITE                                  │
│  (-enable-grants=true, -grant-server-autoconfigure=true)            │
│                                                                     │
│  1. User creates AccessGrant resource                               │
│  2. Grant server generates token URL                                │
│  3. User downloads token (contains connection info + CA cert)       │
│                                                                     │
│  ┌─────────────────┐    ┌──────────────────┐                       │
│  │  Grant Server   │───▶│ skupper-grant-   │◀── External Access    │
│  │                 │    │ server Service   │    (LoadBalancer)     │
│  └─────────────────┘    └──────────────────┘                       │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Token downloaded
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          SPOKE SITE                                 │
│  (-enable-grants=false)                                             │
│                                                                     │
│  4. User applies AccessToken resource                               │
│  5. Controller creates Link resource                                │
│  6. Skupper router connects outbound to Hub                         │
│                                                                     │
│  ┌─────────────────┐         ┌─────────────────┐                   │
│  │  AccessToken    │────────▶│     Link        │──── Outbound ────▶│
│  │  (from Hub)     │         │   (auto-created)│     Connection     │
│  └─────────────────┘         └─────────────────┘                   │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Source Files

| File | Purpose |
|------|---------|
| `internal/kube/grants/config.go` | Flag definitions for grant server |
| `internal/kube/grants/init.go` | Initialization logic (enabled vs disabled) |
| `internal/kube/grants/enabled.go` | Grant server enabled functionality |
| `internal/kube/grants/disabled.go` | Behavior when grants are disabled |
| `internal/kube/grants/autoconfigure.go` | Auto-configuration of SecuredAccess |
| `internal/kube/securedaccess/config.go` | Access type configuration |
| `internal/kube/controller/config.go` | Controller config binding |
| `cmd/controller/main.go` | Main entry point |
