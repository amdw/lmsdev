# Claude Code guidance for lmstest

## Key commands

**Drush** (Drupal CLI) — full invocation from the host:
```bash
docker compose exec drupal /var/www/html/drupal10/vendor/bin/drush \
    --root=/var/www/html/drupal10/web <command>
```

**Clear Drupal cache** (required after changing `.info.yml` files or adding hooks):
```bash
docker compose exec drupal /var/www/html/drupal10/vendor/bin/drush \
    --root=/var/www/html/drupal10/web cr
```

**Run a database query:**
```bash
docker compose exec drupal bash -c \
    "mysql --skip-ssl -h db -udrupal -pdrupal drupal -e 'SELECT …;'"
```
`--skip-ssl` is required — the containerised MySQL client enables TLS by default
but the server does not have a certificate.

## v2 API keys

API keys are stored as SHA-256 hashes only; the plaintext is never persisted.
Generate a fresh key at the start of each session:

```bash
docker compose exec drupal /var/www/html/drupal10/vendor/bin/drush \
    --root=/var/www/html/drupal10/web \
    php-eval "echo \Drupal\league\ApiKey::create(1, 'dev');"
```

To create a key and assign it to a shell variable in one step:

```bash
KEY=$(docker compose exec drupal /var/www/html/drupal10/vendor/bin/drush \
    --root=/var/www/html/drupal10/web \
    php-eval "echo \Drupal\league\ApiKey::create(1, 'dev');")
```

Use it in API requests:

```bash
curl -s "http://localhost:8080/lmsdev/lmsrest/v2/event/1/results" \
    -H "Authorization: Bearer $KEY" | python3 -m json.tool
```

**Clean up dev keys** before creating a new one to prevent accumulation:

```bash
docker compose exec drupal bash -c \
    "mysql --skip-ssl -h db -udrupal -pdrupal drupal \
     -e \"DELETE FROM league_api_key WHERE label = 'dev';\""
```

Or combined — delete old dev keys then create a fresh one:

```bash
docker compose exec drupal bash -c \
    "mysql --skip-ssl -h db -udrupal -pdrupal drupal \
     -e \"DELETE FROM league_api_key WHERE label = 'dev';\"" && \
KEY=$(docker compose exec drupal /var/www/html/drupal10/vendor/bin/drush \
    --root=/var/www/html/drupal10/web \
    php-eval "echo \Drupal\league\ApiKey::create(1, 'dev');")
```
