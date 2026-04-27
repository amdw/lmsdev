#!/bin/bash
# Export the current Drupal database as a compressed seed that the entrypoint
# will automatically import on fresh container starts.
#
# Usage (from the host):
#   docker compose exec drupal /scripts/export-seed.sh
set -e

SEED_FILE=/seed/seed.sql.gz

echo "Exporting database '${MYSQL_DATABASE:-drupal}' to $SEED_FILE ..."
mysqldump \
    -h"${MYSQL_HOST:-db}" \
    -u"${MYSQL_USER:-drupal}" \
    -p"${MYSQL_PASSWORD:-drupal}" \
    --skip-ssl \
    --no-tablespaces \
    --single-transaction \
    --routines \
    --triggers \
    "${MYSQL_DATABASE:-drupal}" \
    | gzip > "$SEED_FILE"

SIZE=$(du -sh "$SEED_FILE" | cut -f1)
echo "Done – seed is $SIZE at $SEED_FILE"
echo ""
echo "To reset to this state on the next fresh start:"
echo "  docker compose down -v   # destroys volumes"
echo "  docker compose up        # imports seed automatically"
