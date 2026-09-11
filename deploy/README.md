# Social Flow deployment

The Confideleap workflows build and validate the monorepo, publish an immutable
image to GHCR, check the target VPS, and deploy the application through Traefik.
The deployment reuses the existing Postiz PostgreSQL, Redis, Temporal, uploads,
and configuration resources on the VPS.

| Branch                 | Environment | VPS user          |
| ---------------------- | ----------- | ----------------- |
| `dev` or `Confideleap` | `dev`       | `dev-socialflow`  |
| `uat`                  | `uat`       | `uat-socialflow`  |
| `main`                 | `prod`      | `prod-socialflow` |

All three entry workflows also support manual dispatch.

## GitHub setup

Create the `dev`, `uat`, and `prod` GitHub environments. Add the repository
variable `INFISICAL_IDENTITY_ID` and allow its OIDC identity to read the matching
environment in the Infisical project whose slug is `social-flow`.

The `/ci` Infisical path must contain:

- `GHCR_PAT`
- `VPS_HOST`
- `VPS_SSH_KEY`

The project root must contain `NEXT_PUBLIC_BACKEND_URL` for the image build.

## VPS setup

Install Docker with Compose and the Infisical CLI. For each environment, create
`/var/www/social-flow-<environment>/.infisical-credentials` with mode `600`:

```dotenv
INFISICAL_UNIVERSAL_AUTH_CLIENT_ID=<environment-client-id>
INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET=<environment-client-secret>
INFISICAL_PROJECT_ID=<social-flow-project-id>
```

The universal-auth identity must be read-only and restricted to its matching
Infisical environment. The exported runtime configuration must include the
application settings from `.env.example` and these deployment values:

```dotenv
APP_DOMAIN=social-flow.example.com
POSTIZ_DATABASE_URL=postgresql://postiz-user:encoded-password@postiz-postgres:5432/postiz-db-local
POSTIZ_REDIS_URL=redis://postiz-redis:6379
TEMPORAL_ADDRESS=temporal:7233
POSTIZ_NETWORK=social-flow_postiz-network
TEMPORAL_NETWORK=temporal-network
POSTIZ_CONFIG_VOLUME=social-flow_postiz-config
POSTIZ_UPLOADS_VOLUME=social-flow_postiz-uploads
APP_PORT=4007
```

Percent-encode reserved URL characters in the password embedded in
`POSTIZ_DATABASE_URL`. Configure DNS and TLS routing for `APP_DOMAIN` on the
VPS Traefik instance before the first deployment.

Confirm the existing resource names before deploying:

```bash
docker inspect postiz-postgres --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{println}}{{end}}'
docker inspect temporal --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{println}}{{end}}'
docker inspect postiz --format '{{range .Mounts}}{{println .Name .Destination}}{{end}}'
```

Set the corresponding Infisical values if they differ from the defaults above.
The first successful CI deployment stops the legacy `postiz` application
container immediately before starting the new application. It leaves the
existing database, Redis, and Temporal containers running. If health checks
fail, the workflow stops the new application and restarts the legacy container.

The deployment runs Prisma `db push` without `--accept-data-loss`; a schema
change that could discard data fails the deployment instead of being applied.
Schema changes must remain backward-compatible with the previous application
image so application rollback remains safe.
