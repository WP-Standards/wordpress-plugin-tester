#!/bin/bash
# Download PLUGIN_SOURCE into /plugins/<slug>/ inside the shared volume.
#
# Supported source patterns:
#   *.git or contains #branch        → git clone (depth=1)
#   *.zip over http(s)               → curl + unzip
#   file:///path                     → cp from /local mount
#   anything else                    → WordPress.org slug (download zip from wp.org)

set -e

SOURCE="${PLUGIN_SOURCE:?Set PLUGIN_SOURCE in .env}"
TARGET_DIR=/plugins
SLUG_OVERRIDE="${PLUGIN_SLUG:-}"

echo "════════════════════════════════════════════════════════"
echo "WordPress Plugin Tester — fetch-plugin"
echo "════════════════════════════════════════════════════════"
echo "PLUGIN_SOURCE: $SOURCE"
echo "PLUGIN_SLUG:   ${SLUG_OVERRIDE:-(auto-detect)}"
echo "────────────────────────────────────────────────────────"

# Install fetch tools (Debian — reliable CA bundle, no SSL issues on Windows Docker).
echo "→ Installing fetch tools..."
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends git curl unzip ca-certificates >/dev/null 2>&1

# Clean previous fetch (allows re-running with different source).
rm -rf "$TARGET_DIR"/*

# ----------------------------------------------------------------------
# Helper — derive slug from URL when not explicitly set.
# ----------------------------------------------------------------------
derive_slug() {
	url="$1"
	# Strip trailing `.git`, `.zip`, `#branch`, query strings
	base=$( echo "$url" | sed -E \
		-e 's/#.*$//' \
		-e 's/\?.*$//' \
		-e 's/\.git$//' \
		-e 's/\.zip$//' \
		-e 's|/$||' )
	# Last path segment
	basename "$base"
}

# ----------------------------------------------------------------------
# Dispatch by source pattern.
# ----------------------------------------------------------------------
case "$SOURCE" in

	# Git URL (recognized by ".git" or "#branch" or known git hosts)
	*.git|*.git#*|https://github.com/*|https://gitlab.com/*|https://bitbucket.org/*|git@*)
		# Extract branch if specified as URL#branch
		repo_url="${SOURCE%%#*}"
		case "$SOURCE" in
			*#*) branch="${SOURCE#*#}" ;;
			*)   branch="" ;;
		esac

		slug="${SLUG_OVERRIDE:-$( derive_slug "$repo_url" )}"
		dest="$TARGET_DIR/$slug"

		echo "→ Cloning git: $repo_url${branch:+ (branch $branch)} → $dest"
		if [ -n "$branch" ]; then
			git clone --depth=1 --branch="$branch" "$repo_url" "$dest"
		else
			git clone --depth=1 "$repo_url" "$dest"
		fi
		rm -rf "$dest/.git"
		echo "✓ Cloned."
		;;

	# ZIP archive over HTTP(S)
	*.zip)
		slug="${SLUG_OVERRIDE:-$( derive_slug "$SOURCE" )}"
		dest="$TARGET_DIR/$slug"
		tmp_zip="/tmp/plugin.zip"

		echo "→ Downloading ZIP: $SOURCE"
		curl -fsSL -o "$tmp_zip" "$SOURCE"

		echo "→ Extracting → $dest"
		mkdir -p "$dest"
		unzip -q "$tmp_zip" -d "$TARGET_DIR/__extract"

		# wp.org ZIPs include a top-level dir matching the slug; agency builds
		# may or may not. Detect and flatten.
		entries=$( ls "$TARGET_DIR/__extract" 2>/dev/null | wc -l )
		first_entry=$( ls "$TARGET_DIR/__extract" 2>/dev/null | head -1 )
		if [ "$entries" -eq 1 ] && [ -d "$TARGET_DIR/__extract/$first_entry" ]; then
			# Single top-level dir — move its contents into $dest.
			mv "$TARGET_DIR/__extract/$first_entry"/* "$dest/"
			mv "$TARGET_DIR/__extract/$first_entry"/.[!.]* "$dest/" 2>/dev/null || true
		else
			# Multiple top-level entries — move them all.
			mv "$TARGET_DIR/__extract"/* "$dest/"
		fi
		rm -rf "$TARGET_DIR/__extract" "$tmp_zip"
		echo "✓ Extracted."
		;;

	# Local folder (mounted at /local by docker-compose)
	file://*)
		path="${SOURCE#file://}"
		# Normalize: file:///local/foo → /local/foo
		case "$path" in
			/local/*) src="$path" ;;
			/*)       src="/local${path}" ;;
			*)        src="/local/${path}" ;;
		esac

		if [ ! -d "$src" ]; then
			echo "✗ Local path not found: $src"
			echo "  (LOCAL_PLUGINS_ROOT in .env is mounted at /local)"
			exit 1
		fi

		slug="${SLUG_OVERRIDE:-$( basename "$src" )}"
		dest="$TARGET_DIR/$slug"

		echo "→ Copying local: $src → $dest"
		mkdir -p "$dest"
		cp -a "$src/." "$dest/"
		echo "✓ Copied."
		;;

	# Anything else → wp.org plugin slug
	*)
		slug="${SLUG_OVERRIDE:-$SOURCE}"
		dest="$TARGET_DIR/$slug"
		wp_zip_url="https://downloads.wordpress.org/plugin/${slug}.latest-stable.zip"
		tmp_zip="/tmp/plugin.zip"

		echo "→ Downloading from WordPress.org: $wp_zip_url"
		if ! curl -fsSL -o "$tmp_zip" "$wp_zip_url"; then
			echo "✗ Plugin '$slug' not found on WordPress.org."
			echo "  If '$SOURCE' is supposed to be a URL, prefix it with https:// and check that it ends in .git or .zip."
			exit 1
		fi

		echo "→ Extracting → $dest"
		mkdir -p "$TARGET_DIR/__extract"
		unzip -q "$tmp_zip" -d "$TARGET_DIR/__extract"
		first_entry=$( ls "$TARGET_DIR/__extract" 2>/dev/null | head -1 )
		if [ -n "$first_entry" ] && [ -d "$TARGET_DIR/__extract/$first_entry" ]; then
			mv "$TARGET_DIR/__extract/$first_entry" "$dest"
		else
			mkdir -p "$dest"
			mv "$TARGET_DIR/__extract"/* "$dest/"
		fi
		rm -rf "$TARGET_DIR/__extract" "$tmp_zip"
		echo "✓ Installed from WordPress.org."
		;;
esac

# Write the resolved slug to a metadata file the cli init script reads.
echo "$slug" > "$TARGET_DIR/.detected-slug"

echo "────────────────────────────────────────────────────────"
echo "✓ Plugin fetched: $slug"
echo "  Files: $( ls -1 "$TARGET_DIR/$slug" 2>/dev/null | wc -l ) entries"
echo "════════════════════════════════════════════════════════"
