# Self-hosted Iceberg REST catalog

This repository deploys the [tabulario/iceberg-rest](https://hub.docker.com/r/tabulario/iceberg-rest) image (JdbcCatalog backend + REST API) onto your EC2 nginx host via **CodeDeploy**. The catalog keeps durable **namespace → table → metadata pointer** state in SQLite on the instance EBS volume; **table data and Iceberg metadata files** live under the configured **S3 warehouse** prefix (typically the same bucket you use as your lake).

## What you get

- **REST catalog** on `http://127.0.0.1:8085` on the instance (Docker maps host 8085 → container `REST_PORT`, default 9000), proxied by nginx at `/iceberg-catalog/` (path configured in CDK).
- **HTTP Basic auth** on `/iceberg-catalog/` via nginx and an **htpasswd** file on the instance (`aws-infra` enables this; credentials come from a **GitHub secret**, never from git).
- **Configurable warehouse** — set `CATALOG_WAREHOUSE=s3://your-bucket/prefix/` (GitHub Actions writes `deploy/iceberg-catalog.env` from a repo variable).
- **Persistence** — `catalog.db` under `/var/lib/iceberg-catalog` (bind-mounted into the container).

## GitHub Actions deploy (automated)

Pushes to **`main`** (and **workflow_dispatch**) run [`.github/workflows/deploy-aws.yml`](.github/workflows/deploy-aws.yml): assume OIDC role → read CloudFormation outputs → build `deploy/iceberg-catalog.env` and `deploy/iceberg-catalog.htpasswd` → zip `appspec.yml`, `deploy/`, `scripts/` → upload to the nginx artifact bucket → wait for an idle CodeDeploy group → create deployment → wait for success. **No manual zip or AWS CLI on your laptop** is required once secrets and variables are set.

### One-time setup

1. **AWS (already in `aws-infra`)**  
   Deploy **`AwsInfra-GitHubOidc`** and **`AwsInfra-Ec2Nginx`** so the shared CodeDeploy app, **`iceberg-catalog`** deployment group, and artifact bucket exist. The EC2 stack’s nginx config must include Basic auth for this path — that is defined in [`aws-infra` `lib/config/ec2-nginx-apps.ts`](https://github.com/ran310/aws-experimentation/blob/main/aws-infra/lib/config/ec2-nginx-apps.ts) (`nginxBasicAuth` on the `iceberg-catalog` app). After pulling CDK changes, run `cdk deploy` for **`AwsInfra-Ec2Nginx`** so SSM applies the updated nginx config.

2. **GitHub repository**  
   - **Secret `AWS_ROLE_TO_ASSUME`** — IAM role ARN from stack output `GitHubActionsRoleArn` on **`AwsInfra-GitHubOidc`**.  
   - **Secret `ICEBERG_CATALOG_HTPASSWD`** — full contents of the htpasswd file (one or more `user:hash` lines). Generate locally (never commit the file):
     ```bash
     htpasswd -nbBC 10 iceberg_admin 'your-strong-password'
     ```
     Paste the **entire line** (or multiple lines) into the secret. The workflow writes it to `deploy/iceberg-catalog.htpasswd` only inside the CI runner and includes it in the zip; the artifact is in your private S3 bucket.
   - **Variable `CATALOG_WAREHOUSE`** — e.g. `s3://mylakehouse-906037744971-us-east-1/warehouse/` (must match how you use the lake and what the instance role can access).

Optional variables: `AWS_REGION`, `AWS_EC2_STACK_NAME` (default `AwsInfra-Ec2Nginx`).

### Startup on EC2

CodeDeploy **`ApplicationStart`** runs `systemctl start iceberg-catalog.service`. The unit is **enabled**, so it also starts after reboot. **`after_install`** refreshes `/etc/iceberg-catalog.env` from the bundle when `deploy/iceberg-catalog.env` is present, installs `/etc/nginx/.htpasswd-iceberg-catalog` from `deploy/iceberg-catalog.htpasswd`, and **`nginx -t && systemctl reload nginx`**.

## Manual deploy (optional)

If you need a local deploy without GitHub:

```bash
export CODEDEPLOY_APPLICATION='learn-aws-ec2-nginx-apps'    # use your projectName prefix
export CODEDEPLOY_DEPLOYMENT_GROUP='learn-aws-ec2-nginx-dg-iceberg-catalog'
export CODEDEPLOY_S3_BUCKET='<artifact bucket from CloudFormation>'
./scripts/deploy-codedeploy.sh
```

You must still supply `deploy/iceberg-catalog.env` and, for Basic auth to work, add `deploy/iceberg-catalog.htpasswd` before zipping (or reload nginx after creating the file on the host).

## `deploy/iceberg-catalog.env`

Copy `deploy/iceberg-catalog.env.example` locally if you are not using Actions. Set **`AWS_REGION`** and **`CATALOG_WAREHOUSE`**. The JDBC user/password entries are **placeholders** for the REST image’s JdbcCatalog wiring, not AWS credentials; S3 access uses the **EC2 instance role**.

Do not commit `deploy/iceberg-catalog.env` or `deploy/iceberg-catalog.htpasswd`.

## Docker on EC2

The nginx EC2 host uses **Amazon Linux’s `docker` package and systemd**. If Docker was added in a CDK update after the instance was created, user-data does not re-run; install Docker once (SSM or SSH) or replace the instance.

```bash
sudo dnf install -y docker && sudo systemctl enable --now docker
sudo systemctl is-active docker   # expect: active
```

## Locking down access

- **nginx** terminates TLS (ALB) or speaks HTTP on :80; **`auth_basic`** restricts `/iceberg-catalog/` to clients that send valid **Basic** credentials.
- The **REST process** still listens on **localhost:8085** only; it is not exposed except through nginx.
- The **S3 warehouse** should be reachable only from the instance role and the principals that need lake access.
- Add **WAF**, **VPN**, or **private ALB** if you need stricter network controls.

## Client configuration

Use your HTTPS URL including the path prefix, for example:

`https://<your-domain>/iceberg-catalog/`

Engines must support **HTTP Basic authentication** for REST requests (or a custom client that sets `Authorization: Basic …`). Test with:

```bash
curl -fsS -u 'iceberg_admin:your-strong-password' \
  'https://<your-domain>/iceberg-catalog/v1/config'
```

## References

- [Iceberg REST catalog spec](https://iceberg.apache.org/rest-catalog-spec)
- [iceberg-rest-image source](https://github.com/databricks/iceberg-rest-image) (environment variables prefixed with `CATALOG_`)
