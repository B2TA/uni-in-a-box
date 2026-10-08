# Canvas test deployment

This Compose project runs a Canvas instance with delayed jobs, PostgreSQL with pgvector, and Redis.

## Configure

Copy the environment template and replace its placeholder values:

```bash
cp .env.canvas.example .env.canvas
```

Set `CANVAS_DOMAIN` to the hostname users will use to reach Canvas, and point
its DNS record at the server's Elastic IP. The files under `config/` are safe
starting points for this test deployment. Then deploy using the steps in the
[main README](../../README.md#deploy).

The first deployment initializes the database and creates the administrator
from `CANVAS_LMS_ADMIN_EMAIL` and `CANVAS_LMS_ADMIN_PASSWORD`. Re-running it is
safe: it skips that setup and does not reset the administrator password.

The deploy script copies files to `/opt/uni-in-a-box/deployment/canvas` on the
server. To run the steps manually from there:

```bash
docker compose --env-file .env.canvas up -d postgres redis
docker compose --env-file .env.canvas --profile init run --rm init  # fresh database only
docker compose --env-file .env.canvas up -d web jobs
```

To discard the test instance and all its data (on the server):

```bash
docker compose --env-file .env.canvas down -v
```
