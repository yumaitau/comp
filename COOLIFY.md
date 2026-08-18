# Coolify deployment

This Compose stack is managed by the `TryCompAI` Coolify project.

- `app` listens on host loopback port `3100`.
- `portal` listens on host loopback port `3102`.
- `api` listens on host loopback port `3333`.
- Cloudflare Tunnel publishes those loopback listeners.
- Coolify generates the database, auth, and internal API secrets from the Compose magic variables; they are editable in the Coolify UI and are not committed.
- The existing PostgreSQL container and `comp_comp_pgdata` volume remain in place. The managed services reach it through the external `comp_default` network.

The PostgreSQL `comp` role password is rotated once to the Coolify-managed `SERVICE_PASSWORD_64_POSTGRES` value during migration. Do not remove the external network until the database is imported as a separate Coolify resource.
