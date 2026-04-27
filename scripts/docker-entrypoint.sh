#!/bin/bash
set -e

DRUPAL_ROOT=/var/www/html/drupal10
WEB_ROOT=$DRUPAL_ROOT/web
SITES_DEFAULT=$WEB_ROOT/sites/default
SEED_FILE=/seed/seed.sql.gz

# ---------------------------------------------------------------------------
# Write settings.php using environment variables.  This is called whenever
# the database already exists (seed import or restarted container) so that
# Drupal can connect without needing the drush installer to run again.
# The fresh-install path intentionally skips this so drush site:install can
# create settings.php itself (it gets confused by getenv() calls).
# ---------------------------------------------------------------------------
write_settings_php() {
    chmod u+w "$SITES_DEFAULT"
    chmod u+w "$SITES_DEFAULT/settings.php" 2>/dev/null || true

    # Single-quoted heredoc delimiter prevents shell expansion inside the
    # PHP file, which contains its own $ variables and getenv() calls.
    cat > "$SITES_DEFAULT/settings.php" << 'SETTINGS_PHP'
<?php

$databases['default']['default'] = [
  'database'        => getenv('MYSQL_DATABASE') ?: 'drupal',
  'username'        => getenv('MYSQL_USER')     ?: 'drupal',
  'password'        => getenv('MYSQL_PASSWORD') ?: 'drupal',
  'prefix'          => '',
  'host'            => getenv('MYSQL_HOST')     ?: 'db',
  'port'            => '3306',
  'isolation_level' => 'READ COMMITTED',
  'driver'          => 'mysql',
  'namespace'       => 'Drupal\\mysql\\Driver\\Database\\mysql',
  'autoload'        => 'core/modules/mysql/src/Driver/Database/mysql/',
];

// Fixed salt – fine for dev; change for any internet-facing deployment.
$settings['hash_salt'] = 'lms-dev-hash-salt-not-for-production-use';

$settings['update_free_access']          = FALSE;
$settings['file_scan_ignore_directories'] = ['node_modules', 'bower_components'];
$settings['entity_update_batch_size']    = 50;
$settings['config_sync_directory']       = '../config/sync';
$settings['container_yamls'][]           = $app_root . '/' . $site_path . '/services.yml';

// Relaxed trusted-host check for local development.
$settings['trusted_host_patterns'] = [
  '^localhost$',
  '^127\.0\.0\.1$',
  '^.*$',
];
SETTINGS_PHP
}

# ---------------------------------------------------------------------------
# Block until MySQL is accepting connections.
# ---------------------------------------------------------------------------
wait_for_db() {
    echo "Waiting for MySQL at ${MYSQL_HOST:-db}..."
    until mysql \
            -h"${MYSQL_HOST:-db}" \
            -u"${MYSQL_USER:-drupal}" \
            -p"${MYSQL_PASSWORD:-drupal}" \
            --skip-ssl \
            -e "SELECT 1" >/dev/null 2>&1; do
        sleep 3
    done
    echo "MySQL is ready."
}

# ---------------------------------------------------------------------------
# Returns 0 (true) when the Drupal schema is present in the database.
# ---------------------------------------------------------------------------
drupal_is_installed() {
    mysql \
        -h"${MYSQL_HOST:-db}" \
        -u"${MYSQL_USER:-drupal}" \
        -p"${MYSQL_PASSWORD:-drupal}" \
        --skip-ssl \
        "${MYSQL_DATABASE:-drupal}" \
        -e "SHOW TABLES LIKE 'users_field_data';" 2>/dev/null \
    | grep -q "users_field_data"
}

# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------
wait_for_db

if drupal_is_installed; then
    echo "Existing Drupal database found – writing settings.php and starting."
    write_settings_php
else
    echo "Empty database detected."
    if [ -f "$SEED_FILE" ]; then
        echo "Importing seed database from $SEED_FILE ..."
        write_settings_php
        zcat "$SEED_FILE" \
            | mysql \
                -h"${MYSQL_HOST:-db}" \
                -u"${MYSQL_USER:-drupal}" \
                -p"${MYSQL_PASSWORD:-drupal}" \
                --skip-ssl \
                "${MYSQL_DATABASE:-drupal}"
        echo "Seed database imported."
    else
        echo "No seed found – running full LMS installation (this takes several minutes)..."
        /scripts/install-lms.sh
        echo "Installation complete."
    fi
fi

# Ensure Drupal's public files directory is owned by the web-server user.
mkdir -p "$SITES_DEFAULT/files"
chown -R www-data:www-data "$SITES_DEFAULT/files"

echo "Starting Apache..."
exec apache2-foreground
