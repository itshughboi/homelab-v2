# Wazuh

> **Keep in Docker for now.** Migrating Wazuh to k8s is possible but significantly more complex than other apps — internal mutual TLS between manager, indexer, and dashboard requires a certificate bootstrap process that doesn't translate cleanly to standard k8s Deployments. Defer until the rest of the migration is complete.

## Why It's Difficult to Migrate

Wazuh's three components (manager, indexer, dashboard) communicate over mutual TLS using internally-generated certificates. The Docker compose ships a `wazuh_indexer_ssl_certs/` directory with pre-generated certs that are volume-mounted. In k8s you need to:

1. Generate or copy these certs into Secrets
2. Handle cert rotation (Wazuh doesn't integrate with cert-manager)
3. Manage the indexer's OpenSearch configuration which expects specific CN/SAN values in those certs
4. Handle `ulimits.memlock.soft=-1` for the indexer (requires `securityContext.allowedUnsafeSysctls`)

## Migration Path (When Ready)

The recommended approach is the [Wazuh Kubernetes deployment guide](https://documentation.wazuh.com/current/deployment-options/kubernetes/index.html) which includes:
- Official `wazuh/wazuh-kubernetes` repo with pre-built manifests
- Built-in cert generation via init containers
- StatefulSets (not Deployments) for the indexer cluster

Steps:
```bash
git clone https://github.com/wazuh/wazuh-kubernetes
# Follow https://documentation.wazuh.com/current/deployment-options/kubernetes/index.html
```

## Current Docker Config

The Docker setup runs:
- `wazuh/wazuh-manager` — SIEM manager + Filebeat to indexer
- `wazuh/wazuh-indexer` — OpenSearch-based log indexer
- `wazuh/wazuh-dashboard` — Kibana-based UI

All three use TLS from `wazuh_indexer_ssl_certs/`. The manager ships integration scripts (Discord notifications etc.) from `apps/docker/wazuh/config/`.
