# PrairieLearn test deployment

This Compose project runs a small, single-container PrairieLearn instance.
PrairieLearn's PostgreSQL data is stored in a named Docker volume and course
repositories are stored under `courses/` on the host.

> External graders and coding workspaces don't work in this setup; standard
> questions do.

## Configure Google OAuth

PrairieLearn supports Google OAuth 2 as the login method for self-hosted
instances. Create a Google OAuth client before starting the service:

1. In Google Cloud Console, create or select a project.
2. Under **Google Auth Platform**, configure the OAuth consent screen.
3. Create an OAuth client with application type **Web application**.
4. Add `https://pl.example.com` as an authorized JavaScript origin, replacing
   the example hostname with the public PrairieLearn hostname.
5. Add `https://pl.example.com/pl/oauth2callback` as an authorized redirect
   URI, using the same hostname.
6. Copy the configuration template and fill in the hostname, cookie domain,
   client ID, client secret, and two application keys:

   ```bash
   cp config.example.json config.json
   openssl rand -hex 32
   openssl rand -hex 32
   ```

The values of `serverCanonicalHost` and `googleRedirectUrl` must use the public
HTTPS hostname, and the callback path must remain `/pl/oauth2callback`.
`cookieDomain` must begin with a dot; for `pl.example.com`, use
`.pl.example.com`. Put the two different 64-character hexadecimal values from
the `openssl` commands in `secretKey` and `databaseEncryptionKey`.

## Configure GitHub access for PrairieLearn

The Compose file mounts the host user's SSH directory read-only. Add the public key used by the server to the course repository as a deploy key:

```bash
ls -la /home/admin/.ssh
cat /home/admin/.ssh/id_ed25519.pub
```

If the server uses a different key name, configure it
in `/home/admin/.ssh/config`.

If the key directory is elsewhere, set `PRAIRIELEARN_SSH_DIR` before running
Compose.

## Deploy PrairieLearn

After configuring `config.json`, deploy using the steps in the
[main README](../../README.md#deploy).

On the server, the files are in `/opt/uni-in-a-box/deployment/prairielearn`,
where the commands below should be run.

## Create the first administrator

First sign in through Google once so PrairieLearn creates your user. Then open
PrairieLearn's PostgreSQL shell:

```bash
docker compose exec app psql -U postgres -d postgres
```

Find your PrairieLearn user ID:

```sql
SELECT id, uid, uin, name FROM users;
```

Promote that user, replacing `1` with the correct ID:

```sql
INSERT INTO administrators (user_id) VALUES (1);
```

Exit with `\q`, then reload PrairieLearn in the browser.

## Add a course

Place each course repository in `courses/`, for example:

```bash
git clone https://github.com/example/course.git courses/course
```

In PrairieLearn, go to **Admin**, add a course, and use its container path:

```text
/courses/course
```

Keeping repositories in this bind-mounted directory preserves them when the
application container is replaced.

## Operate and remove the instance

View logs or update to the current `us-prod-live` image:

```bash
docker compose logs --follow app
docker compose pull
docker compose up -d
```

To discard the database permanently, including users and course-instance data:

```bash
docker compose down -v
```

Course repositories under `courses/` are not deleted by `down -v`.

## Scope and references

This is a low-footprint test deployment, not a high-availability production
design. Back up both the PostgreSQL volume and `courses/` before storing data
that matters.

- [PrairieLearn: Using Docker Compose](https://docs.prairielearn.com/running-in-production/docker-compose/)
- [PrairieLearn: Running in Production](https://docs.prairielearn.com/running-in-production/setup/)
- [PrairieLearn: User Authentication](https://docs.prairielearn.com/running-in-production/authentication/)
- [PrairieLearn: Admin User Setup](https://docs.prairielearn.com/running-in-production/admin-user/)
