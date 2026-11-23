# Suncoast Discourse

GitOps source for the Suncoast Systems Discourse deployment.

## Architecture

- Discourse runs as a single Kubernetes web/Sidekiq pod built from the official
  Discourse launcher and an immutable `tests-passed` commit.
- PostgreSQL runs on the existing Oracle VM. Pods reach it only through the
  established Vault-backed, loopback-only SSH tunnel.
- Redis is the shared platform service. Logical database 4 is reserved for
  Discourse and database 5 for short-lived worker idempotency records.
- The native Discourse UI is enrolled in Teleport at
  `discourse.teleport.app.suncoast.systems`.
- Discourse uses the Keycloak `internal` realm through a public PKCE client.
  The GitHub team `k8s_discourse_admins` is emitted in the `suncoast_roles`
  claim and reconciled to Discourse administrator status at login. Removing a
  user from the team revokes that status on their next OIDC membership sync.
- The bootstrap `administrator` account remains available for recovery and for
  the Kafka integration API key; it is not governed by the GitHub team.
- Suncoast customer applications do not call the Discourse API directly. They
  use the existing `graphql.async.requests.v1` / `graphql.async.responses.v1`
  Kafka contract with `route.handler: discourse`.
- `/shared` is an RWX Longhorn volume containing uploads, logs, and local
  Discourse backups.

## Durable Vault inputs

The deployment deliberately does not create durable credentials. Before the
Argo CD application is registered, create these flat retained secrets. Every
path contains exactly one key named `value`:

- `secret/discourse_db_password`
- `secret/discourse_secret_key_base`
- `secret/discourse_admin_password`
- `secret/discourse_integration_api_key`

The bootstrap job fails closed if any required key is absent. Existing platform
secrets are reused for the Oracle SSH tunnel, Redis, Cloudflare SMTP, and the
GraphQL async Kafka principal.

## Build

The `build.yml` workflow builds and publishes:

- `ghcr.io/dotcomrow/discourse:97c86cedd020484e0fd51e8739ade8474352fec7-suncoast1`
- `ghcr.io/dotcomrow/discourse:latest`

The manifests deliberately deploy `ghcr.io/dotcomrow/discourse:latest` with
`imagePullPolicy: Always`. The immutable tag remains available for build audit
and rollback, but publishing a replacement `latest` image does not require a
manifest tag change. Because Kubernetes does not restart an unchanged workload
when a mutable tag moves, the deployment still needs to be restarted through
the operator-controlled rollout process to consume the newly published image.

## Validation

Run `./scripts/validate.sh`. The validator checks every manifest, duplicate
Kubernetes identities, embedded shell syntax, the `latest` deployment contract,
and the expected platform contracts.
