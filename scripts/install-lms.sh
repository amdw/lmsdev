#!/bin/bash
# Full LMS installation via drush.
# Called by docker-entrypoint.sh on first boot when no seed is present.
set -e

DRUPAL_ROOT=/var/www/html/drupal10
WEB_ROOT=$DRUPAL_ROOT/web
SITES_DEFAULT=$WEB_ROOT/sites/default
DRUSH="$DRUPAL_ROOT/vendor/bin/drush --root=$WEB_ROOT"

# drush site:install needs a writable sites/default and no existing settings.php
# (it gets confused by our getenv() template).
chmod u+w "$SITES_DEFAULT"
rm -f "$SITES_DEFAULT/settings.php"

echo "=== Installing Drupal ==="
$DRUSH site:install standard \
    --db-url="mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}/${MYSQL_DATABASE}" \
    --account-name="${DRUPAL_ADMIN_USER:-admin}" \
    --account-pass="${DRUPAL_ADMIN_PASSWORD:-admin}" \
    --site-name="${DRUPAL_SITE_NAME:-LMS}" \
    --site-mail="${DRUPAL_SITE_MAIL:-lms@example.com}" \
    -y

# Clear cache so Drupal discovers the custom modules in the bind-mounted dirs.
echo "=== Clearing cache ==="
$DRUSH cr

echo "=== Enabling base contrib modules ==="
# book: removed from Drupal 10 core in 10.3; now a contrib module.
$DRUSH pm:enable book -y
$DRUSH pm:enable devel -y
$DRUSH pm:enable captcha riddler -y
$DRUSH pm:enable legal genpass -y

# bootstrap5 must be enabled BEFORE league (league ships block config that
# references it). lms_theme must be enabled AFTER league and user_tools
# (it ships block config that references those modules).
echo "=== Enabling bootstrap5 theme ==="
$DRUSH theme:enable bootstrap5 -y

echo "=== Enabling LMS custom modules ==="
# Dependency order: user_tools → rating_list → rating_fide → league → *_test
$DRUSH pm:enable user_tools -y
$DRUSH pm:enable rating_list rating_fide rating_test -y
$DRUSH pm:enable league -y
$DRUSH pm:enable league_test -y

echo "=== Enabling lms_theme (requires league + user_tools to be present) ==="
$DRUSH theme:enable lms_theme -y
$DRUSH config:set system.theme default lms_theme -y

echo "=== Enabling REST API and content sync ==="
$DRUSH pm:enable rest restui -y
$DRUSH pm:enable single_content_sync -y

echo "=== Disabling internal page cache ==="
# The cache means anonymous users see stale pages; not suitable for dev.
$DRUSH pm:uninstall page_cache -y

echo "=== Development settings ==="
$DRUSH config:set system.performance css.preprocess 0 -y
$DRUSH config:set system.performance js.preprocess 0 -y
# Prevent cron from trying to send rating files (automated_cron module).
$DRUSH config:set automated_cron.settings interval 0 -y

echo "=== Configuring rating system URLs (Drupal state) ==="
# These are read by RatingDefaults::__construct() via \Drupal::state()->get().
$DRUSH state:set rating_fide_url "http://ratings.fide.com/download"
# ECF URL – only useful if you later switch to the ECF flavour.
$DRUSH state:set rating_ecf_url "https://rating-sbox.englishchess.org.uk" 2>/dev/null || true

echo "=== Setting user permissions ==="
$DRUSH role:perm:add anonymous    "league view" -y
$DRUSH role:perm:add authenticated "league view" -y

echo "=== Configuring single_content_sync ==="
# Disable UUID checking so the help ZIP can be imported.
$DRUSH config:set single_content_sync.settings check_uuid 0 -y 2>/dev/null || true

echo "=== Loading test ratings ==="
# Copy the bundled test CSV into Drupal's public files area, then tell
# RatingDefaults where to find it.
TEST_RATINGS_DIR="$WEB_ROOT/sites/default/files/rating_test"
mkdir -p "$TEST_RATINGS_DIR"
cp "$WEB_ROOT/modules/custom/rating_list/modules/rating_test/playerDetails.csv" \
   "$TEST_RATINGS_DIR/playerDetails.csv"
# Leave the directory root-owned here; the entrypoint chowns the whole files
# tree to www-data after this script returns.  Drupal's stream wrapper does
# stat-based permission checks (no root exception), so the directory must be
# owned by the running user (root) for is_writable() to return true.

$DRUSH state:set rating_test_url "$TEST_RATINGS_DIR/playerDetails.csv"
$DRUSH cr

$DRUSH rll test \
    && echo "Test ratings loaded." \
    || echo "WARNING: test ratings load failed – this can be retried later with: drush rll test"

echo "=== Importing help content ==="
HELP_ZIP="$WEB_ROOT/modules/custom/league/help.zip"
if [ -f "$HELP_ZIP" ]; then
    # content:import resolves paths relative to the web root, so pass a
    # relative path (not the absolute $HELP_ZIP).
    $DRUSH content:import "modules/custom/league/help.zip" \
        && echo "Help content imported." \
        || echo "WARNING: help import failed (likely site UUID mismatch – see lms_install.txt step 14). Skipping."
else
    echo "No help.zip found – skipping."
fi

echo ""
echo "=== LMS installation complete ==="
echo "  Site URL : http://localhost:${WEB_PORT:-8080}/"
echo "  Admin    : ${DRUPAL_ADMIN_USER:-admin} / ${DRUPAL_ADMIN_PASSWORD:-admin}"
echo ""
echo "Next steps (manual, via the Drupal admin UI):"
echo "  1. Admin > Structure > Organisation: add an organisation."
echo "  2. Admin > Structure > Block Layout: configure menus as per lms_install.txt steps 6."
echo "  3. When ready, run:  docker compose exec drupal /scripts/export-seed.sh"
echo "     to capture this state as a seed DB for fast future startups."
