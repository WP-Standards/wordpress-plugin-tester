#!/bin/sh
# WordPress + plugin initializer — runs once after the WP container is up.
#
# Steps:
#   1. Wait for wp-load.php (volume populated by WP container entrypoint).
#   2. Wait for the database.
#   3. Copy the fetched plugin from /__plugin_src into wp-content/plugins/.
#   4. Install WordPress if not already installed (admin user from env).
#   5. Set pretty permalinks.
#   6. Activate the plugin.
#   7. Print endpoint summary.

set -e

SITE_URL="http://localhost:${WP_PORT:-8080}"
SITE_TITLE=${WP_SITE_TITLE:-"Plugin Tester"}
ADMIN_USER=${WP_ADMIN_USER:-test}
ADMIN_PASS=${WP_ADMIN_PASS:-test}
ADMIN_EMAIL=${WP_ADMIN_EMAIL:-test@plugin-tester.local}

echo "════════════════════════════════════════════════════════"
echo "WordPress Plugin Tester — initialization"
echo "════════════════════════════════════════════════════════"
echo "Site URL:    $SITE_URL"
echo "Title:       $SITE_TITLE"
echo "Admin user:  $ADMIN_USER"
echo "Admin pass:  $ADMIN_PASS"
echo "────────────────────────────────────────────────────────"

# ----------------------------------------------------------------------
# 1. Wait for WordPress files.
# ----------------------------------------------------------------------
echo "→ Waiting for WordPress files…"
i=0
while [ ! -f /var/www/html/wp-load.php ]; do
	i=$((i+1))
	[ "$i" -gt 60 ] && { echo "✗ wp-load.php not found after 60s."; exit 1; }
	sleep 1
done
echo "✓ WordPress files ready."

# ----------------------------------------------------------------------
# 2. Wait for the database.
# ----------------------------------------------------------------------
echo "→ Waiting for database…"
i=0
until wp db check --quiet 2>/dev/null; do
	i=$((i+1))
	[ "$i" -gt 60 ] && { echo "✗ Database not reachable after 60s."; exit 1; }
	sleep 1
done
echo "✓ Database is up."

# ----------------------------------------------------------------------
# 3. Determine plugin slug + copy from fetch volume into wp-content/plugins.
# ----------------------------------------------------------------------
DETECTED_SLUG_FILE=/__plugin_src/.detected-slug
if [ -f "$DETECTED_SLUG_FILE" ]; then
	PLUGIN_SLUG_RESOLVED=$( cat "$DETECTED_SLUG_FILE" )
else
	# Fallback — first folder in /__plugin_src
	PLUGIN_SLUG_RESOLVED=$( ls /__plugin_src 2>/dev/null | grep -v '^\.' | head -1 )
fi

if [ -z "$PLUGIN_SLUG_RESOLVED" ]; then
	echo "✗ No plugin found in /__plugin_src — did 'plugin' service fail?"
	exit 1
fi

SRC_DIR="/__plugin_src/$PLUGIN_SLUG_RESOLVED"
DEST_DIR="/var/www/html/wp-content/plugins/$PLUGIN_SLUG_RESOLVED"

if [ ! -d "$SRC_DIR" ]; then
	echo "✗ Plugin source missing at $SRC_DIR"
	exit 1
fi

echo "→ Installing plugin: $PLUGIN_SLUG_RESOLVED"
rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"
cp -a "$SRC_DIR/." "$DEST_DIR/"
echo "✓ Plugin files copied to $DEST_DIR."

# ----------------------------------------------------------------------
# 4. Install WordPress if not already installed.
# ----------------------------------------------------------------------
if wp core is-installed 2>/dev/null; then
	echo "→ WordPress already installed — skipping core install."
else
	echo "→ Installing WordPress…"
	wp core install \
		--url="$SITE_URL" \
		--title="$SITE_TITLE" \
		--admin_user="$ADMIN_USER" \
		--admin_password="$ADMIN_PASS" \
		--admin_email="$ADMIN_EMAIL" \
		--skip-email
	echo "✓ WordPress installed."
fi

# Ensure test user exists with correct password every run.
if wp user get "$ADMIN_USER" --field=ID 2>/dev/null >/dev/null; then
	wp user update "$ADMIN_USER" --user_pass="$ADMIN_PASS" --role=administrator >/dev/null
else
	wp user create "$ADMIN_USER" "$ADMIN_EMAIL" \
		--role=administrator \
		--user_pass="$ADMIN_PASS" >/dev/null
fi
echo "✓ Admin user '$ADMIN_USER' ready."

# ----------------------------------------------------------------------
# 5. Pretty permalinks.
# ----------------------------------------------------------------------
wp rewrite structure '/%postname%/' --hard >/dev/null 2>&1 || true
wp rewrite flush --hard >/dev/null 2>&1 || true
echo "✓ Permalinks set to /%postname%/."

# ----------------------------------------------------------------------
# 6. Try to activate the plugin (best-effort — surfaces wp-cli errors).
# ----------------------------------------------------------------------
echo "→ Activating plugin '$PLUGIN_SLUG_RESOLVED'…"
if wp plugin activate "$PLUGIN_SLUG_RESOLVED" 2>&1; then
	echo "✓ Plugin activated."
else
	echo "⚠ Could not activate '$PLUGIN_SLUG_RESOLVED' as-is."
	echo "  Trying to auto-detect the correct slug…"
	# Some plugins have a different slug than their folder. Find the main file
	# and re-derive.
	for candidate in $( wp plugin list --field=name 2>/dev/null ); do
		case "$candidate" in
			"$PLUGIN_SLUG_RESOLVED"/*)
				echo "  → Found: $candidate"
				wp plugin activate "$candidate" || true
				;;
		esac
	done
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "✓ All set."
echo "════════════════════════════════════════════════════════"
echo ""
echo "  Front-end:  $SITE_URL"
echo "  Admin:      $SITE_URL/wp-admin"
echo "  User:       $ADMIN_USER"
echo "  Password:   $ADMIN_PASS"
echo ""
echo "  Plugin:     wp-content/plugins/$PLUGIN_SLUG_RESOLVED"
echo "  Source:     $PLUGIN_SOURCE"
echo ""
echo "  phpMyAdmin: http://localhost:${PMA_PORT:-8081}"
echo "              (root / rootpass)"
echo ""
echo "════════════════════════════════════════════════════════"
