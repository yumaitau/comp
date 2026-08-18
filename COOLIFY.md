# Coolify deployment

This Compose stack is managed by the `TryCompAI` Coolify project.

- `app` listens on host loopback port `3100`.
- `portal` listens on host loopback port `3102`.
- `api` listens on host loopback port `3333`.
- Cloudflare Tunnel publishes those loopback listeners.
- Runtime secrets remain in the existing host files under `/opt/comp`; they are not committed.
- PostgreSQL reuses the external `comp_comp_pgdata` volume and the existing TLS files under `/opt/comp/pg-ssl`.

`POSTGRES_REPLICAS` is intentionally `0` by default. During the migration the managed services connect to the existing PostgreSQL container through the external `comp_default` network. After the old database container is stopped, set `POSTGRES_REPLICAS=1` in Coolify and redeploy. Never run both PostgreSQL containers against the same volume.

Before a fresh database initialization, add a strong `POSTGRES_PASSWORD` secret to the Compose service. The imported database does not need it because its data directory is already initialized.
