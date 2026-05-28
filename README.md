# WordPress Plugin Tester

A generic, one-command WordPress + PHP + MariaDB Docker stack for testing **any** WordPress plugin. You give it a URL, it gives you a working WordPress with the plugin installed and activated.

## Features

- **Any plugin source**: git URL, ZIP URL, or WordPress.org slug
- **Configurable versions**: WordPress, PHP, MariaDB
- **Admin user**: `test` / `test` by default
- **Pretty permalinks** + `WP_DEBUG` + `SCRIPT_DEBUG` on
- **phpMyAdmin** at `:8081` for DB inspection
- **WP-CLI shell** ready to use

## Requirements

- Docker Desktop 24+ (Compose v2)
- ~2 GB free disk
- Ports `8080` (WP) and `8081` (phpMyAdmin) free

## Quick start

### 1. Choose the plugin to test

Edit `.env` (copy from `.env.example`) and set `PLUGIN_SOURCE`:

```bash
cp .env.example .env
```

Examples:

```env
# WordPress.org slug — installs the latest from the WP plugin directory
PLUGIN_SOURCE=woocommerce

# Git HTTPS URL — clones the repo's default branch
PLUGIN_SOURCE=https://github.com/owner/plugin-name.git

# Git URL pinned to a branch
PLUGIN_SOURCE=https://github.com/owner/plugin-name.git#feature/new-stuff

# ZIP archive URL — downloads and unzips
PLUGIN_SOURCE=https://example.com/my-plugin.zip

# Local folder (relative to project root) — bind-mounts the path
PLUGIN_SOURCE=file:///path/to/local/plugin
```

### 2. (Optional) tweak versions

```env
WP_VERSION=6.6
PHP_VERSION=8.2
MARIADB_VERSION=11
```

### 3. Start the stack

```bash
docker compose up -d
```

Watch the initializer:

```bash
docker compose logs -f cli
```

When you see `✓ All set.` you're ready.

## Endpoints

| URL | Purpose | Credentials |
|---|---|---|
| <http://localhost:8080> | WordPress front-end | — |
| <http://localhost:8080/wp-admin> | WordPress admin | **test / test** |
| <http://localhost:8081> | phpMyAdmin | `root` / `rootpass` |

## How it works

```
┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│   plugin     │ → │      db      │ → │  wordpress   │ → │     cli      │
│  (one-shot)  │   │   (mariadb)  │   │ (apache+php) │   │  (wp-cli)    │
└──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
   downloads        starts MariaDB,    boots WordPress    runs init.sh:
   PLUGIN_SOURCE    waits to be        with bind-mounted   wp core install
   into shared      healthy            plugin volume       wp user create test/test
   volume                                                  wp plugin activate <slug>
```

1. **plugin** (one-shot) reads `PLUGIN_SOURCE`, downloads the plugin via the appropriate method (git/zip/wp.org/local), writes it to a named volume at `/plugins/<slug>/`.
2. **db** starts MariaDB; healthcheck-gated.
3. **wordpress** mounts the plugin volume at `wp-content/plugins/<slug>`.
4. **cli** runs `init.sh`: WP install, test user creation, plugin auto-detection + activation.
5. **phpmyadmin** (optional) for DB browsing.

## Plugin source detection

The `plugin` service auto-detects the source type:

| Pattern | Action |
|---|---|
| starts with `http(s)://` and ends `.git` (or has `#branch`) | `git clone --depth=1` |
| starts with `http(s)://` and ends `.zip` | `curl + unzip` |
| starts with `file://` | bind mount (path relative to project root) |
| any other string | treated as WordPress.org slug → `wp plugin install <slug>` |

## Common workflows

### Test a different plugin without losing data

```bash
# Stop, change PLUGIN_SOURCE in .env, drop only the plugin volume, restart:
docker compose down
docker volume rm wordpress-plugin-tester_plugin_data
docker compose up -d
```

### Full reset

```bash
docker compose down -v   # drops all volumes (db + wp + plugin)
docker compose up -d
```

### Open a WP-CLI shell

```bash
docker compose run --rm cli wp shell
```

### Run any WP-CLI command

```bash
docker compose run --rm cli wp plugin list
docker compose run --rm cli wp user list
docker compose run --rm cli wp option get siteurl
```

### Tail debug.log

```bash
docker compose exec wordpress tail -f /var/www/html/wp-content/debug.log
```

### Stop without losing data

```bash
docker compose down       # keeps volumes — restart with `up -d`
```

## File layout

```
wordpress-plugin-tester/
├── docker-compose.yml         # the stack
├── .env.example                # template — copy to .env
├── scripts/
│   ├── fetch-plugin.sh         # downloads PLUGIN_SOURCE
│   └── init.sh                 # WP install + user + plugin activation
└── README.md                   # this file
```

## Configuration reference

All knobs live in `.env`. Defaults are sensible — most users only set `PLUGIN_SOURCE`.

| Var | Default | Notes |
|---|---|---|
| `PLUGIN_SOURCE` | _(required)_ | git URL / zip URL / wp.org slug / `file://` path |
| `PLUGIN_SLUG` | _(auto)_ | Folder name inside `wp-content/plugins/`. Auto-derived from source; override to force a specific name. |
| `WP_VERSION` | `6.6` | Major.minor — used in the WP image tag. |
| `PHP_VERSION` | `8.2` | Used in WP + CLI images. |
| `MARIADB_VERSION` | `11` | MariaDB major version. |
| `WP_PORT` | `8080` | Host port for WordPress. |
| `PMA_PORT` | `8081` | Host port for phpMyAdmin. |
| `WP_ADMIN_USER` | `test` | Admin username. |
| `WP_ADMIN_PASS` | `test` | Admin password. |
| `WP_ADMIN_EMAIL` | `test@plugin-tester.local` | Admin email. |
| `WP_SITE_TITLE` | `Plugin Tester` | Site title. |

## Troubleshooting

**Plugin shows as installed but not active**
The init script tries to auto-detect the plugin's main file. If detection fails, set `PLUGIN_SLUG` in `.env` to the exact slug expected by `wp plugin activate`.

**Port already in use**
Change `WP_PORT` or `PMA_PORT` in `.env`.

**`fetch-plugin.sh` fails to clone**
Private repos need credentials. Either use a public mirror or extend `fetch-plugin.sh` to inject a token via Docker secrets.

**Want to test a plugin that needs paid dependencies (e.g., GSAP Business)**
Put your build artifacts in a ZIP and use `PLUGIN_SOURCE=https://your-host/plugin.zip`.

## License

GPLv3 — match the WordPress ecosystem.
