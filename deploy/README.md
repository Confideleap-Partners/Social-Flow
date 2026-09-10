# Social Flow deployment

The Confideleap workflows build and validate the monorepo, publish an immutable
image to GHCR, check the target VPS, and deploy the application stack through
Traefik.

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
POSTIZ_DATABASE_URL=postgresql://postiz-user:encoded-password@postgres:5432/postiz
POSTGRES_USER=postiz-user
POSTGRES_PASSWORD=<strong-password>
POSTGRES_DB=postiz
```

Percent-encode reserved URL characters in the password embedded in
`POSTIZ_DATABASE_URL`. Configure DNS and TLS routing for `APP_DOMAIN` on the
VPS Traefik instance before the first deployment.

The deployment runs Prisma `db push` without `--accept-data-loss`; a schema
change that could discard data fails the deployment instead of being applied.
