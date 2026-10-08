# Canvas test deployment

This Compose project runs a Canvas instance with delayed jobs, PostgreSQL with pgvector, and Redis.

## Configure

Copy the environment template and replace its placeholder values:

```bash
cp .env.canvas.example .env.canvas
```

Generate a different random value for each of `POSTGRES_PASSWORD`,
`CANVAS_LMS_ADMIN_PASSWORD`, `ENCRYPTION_KEY`, and `JWT_ENCRYPTION_KEY`:

```bash
openssl rand -hex 32
```

Set `CANVAS_DOMAIN` to the hostname users will use to reach Canvas, and point
its DNS record at the server's Elastic IP. The files under `config/` are safe
starting points for this test deployment. Then deploy using the steps in the
[main README](../../README.md#deploy).

The first deployment initializes the database and creates the administrator
from `CANVAS_LMS_ADMIN_EMAIL` and `CANVAS_LMS_ADMIN_PASSWORD`. Re-running it is
safe: it skips that setup and does not reset the administrator password.

The deploy script copies files to `/opt/uni-in-a-box/deployment/canvas` on the
server and runs `start.sh` there. You can rerun it on the server at any time
to pull the latest images and start Canvas:

```bash
/opt/uni-in-a-box/deployment/canvas/start.sh
```

It runs these steps, which you can also run manually from that directory:

```bash
docker compose --env-file .env.canvas pull
docker compose --env-file .env.canvas up -d --wait postgres redis
docker compose --env-file .env.canvas --profile init run --rm init  # fresh database only
docker compose --env-file .env.canvas up -d web jobs
```

To discard the test instance and all its data (on the server):

```bash
docker compose --env-file .env.canvas down -v
```
