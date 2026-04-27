# LMS Development Environment

Dockerised development environment for the ECF [League Management
System](https://www.drupal.org/project/league) — a Drupal 10 application for
running chess leagues.

The setup provides:
- A PHP 8.2 / Apache container with Drupal 10.6 and all required modules
  pre-installed
- A MySQL 8.0 database container
- The four LMS git repositories (`league`, `rating_list`, `user_tools`,
  `lms_theme`) as git submodules, mounted read-only into the container so you
  can edit code on the host and see changes immediately
- A seed database that is automatically imported on first start, skipping the ~3
  minute full installation

---

## Prerequisites

### Host operating system

Tested on **Debian 13 (trixie)**. Any recent Debian or Ubuntu release should
work without changes. Other distributions may require minor adjustments to
package names in the install steps below.

The containers themselves run Debian internally, so the host OS only needs to
provide Docker and Git.

### Required packages

Install with `apt` (or your distro's equivalent):

```bash
sudo apt-get install docker.io docker-compose git
```

Minimum tested versions:

| Package       | Tested version |
|---------------|----------------|
| Docker        | 26.1.5         |
| Docker Compose| 2.26.1         |
| Git           | 2.47           |

All `docker` commands in this guide assume `sudo` access. Prefix them with
`sudo` if your user is not already permitted to run Docker directly.

### No local MySQL needed

The database runs entirely inside a Docker container. Nothing needs to be
installed on the host for MySQL.

### Network access

The web server binds to `127.0.0.1:8080` only — it is **not** reachable from the
public internet. If you are working on a remote server (e.g. a cloud VM), use an
SSH tunnel to access it from your local browser:

```bash
ssh -L 8080:localhost:8080 your-server
```

Then open `http://localhost:8080/` on your local machine.

---

## First-time setup

### 1. Clone the repository (with submodules)

```bash
git clone --recurse-submodules <this-repo-url> lmstest
cd lmstest
```

If you have already cloned without `--recurse-submodules`, initialise the
submodules manually:

```bash
git submodule update --init --recursive
```

The LMS source repositories will be checked out under `lms/`:

```
lms/
├── league/       – core league management module
├── rating_list/  – rating loading framework + test/ECF/FIDE/CS submodules
├── user_tools/   – user ownership and mailing-list support
└── lms_theme/    – Bootstrap 5 sub-theme
```

### 2. Review configuration

Copy or review `.env`. The defaults work out of the box:

```bash
cat .env
```

Notable settings:

| Variable               | Default    | Purpose                        |
|------------------------|------------|--------------------------------|
| `DRUPAL_ADMIN_USER`    | `admin`    | Drupal admin username          |
| `DRUPAL_ADMIN_PASSWORD`| `admin`    | Drupal admin password          |
| `DRUPAL_SITE_NAME`     | `LMS Test` | Site name shown in the UI      |
| `WEB_PORT`             | `8080`     | Host port (loopback only)      |
| `MYSQL_PASSWORD`       | `drupal`   | Database password              |

Change passwords before use if this environment will be accessible to others.

### 3. Build the Docker image

This step downloads Drupal core and all composer dependencies. It takes **5–15
minutes** the first time but is fully cached afterwards.

```bash
docker compose build
```

### 4. Start the containers

```bash
docker compose up -d
```

**First start behaviour** (no seed database present):

The entrypoint script detects an empty database and runs the full LMS
installation automatically. This takes approximately **3–5 minutes** and
performs the following steps via `drush`:

- Installs Drupal with the standard profile
- Enables all required contrib modules (`book`, `devel`, `captcha`, `riddler`,
  `legal`, `genpass`, …)
- Enables the bootstrap5 theme, then all LMS custom modules (`user_tools`,
  `rating_list`, `rating_fide`, `rating_test`, `league`, `league_test`)
- Enables and sets `lms_theme` as the active theme
- Disables the internal page cache and CSS/JS aggregation (development-friendly
  settings)
- Loads the bundled test rating data
- Imports the help content

Follow progress with:

```bash
docker compose logs -f drupal
```

The site is ready when you see `Starting Apache...` in the logs.

**Subsequent starts** (seed database present, or volumes intact):

The entrypoint detects an initialised database and starts Apache immediately —
typically within a few seconds.

### 5. Open the site

If running locally:

```
http://localhost:8080/
```

If on a remote server, set up the SSH tunnel first (see [Network
access](#network-access) above).

Log in with the credentials from `.env` (default: `admin` / `admin`).

---

## Day-to-day usage

### Starting and stopping

```bash
docker compose up -d       # start in background
docker compose stop        # stop containers, preserve data
docker compose down        # stop and remove containers (data volumes preserved)
docker compose down -v     # stop, remove containers AND wipe all data
```

### Editing LMS code

Edit files directly under `lms/` on the host. The directories are bind-mounted
read-only into the container, so PHP picks up your changes on the next page load
(no container restart needed). If you change a `.info.yml` or add a new hook,
clear Drupal's cache:

```bash
docker compose exec drupal /var/www/html/drupal10/vendor/bin/drush \
    --root=/var/www/html/drupal10/web cr
```

Or use the shell alias shortcut once inside the container:

```bash
docker compose exec drupal bash
# inside the container:
drush cr
```

The `drush` binary is at `/var/www/html/drupal10/vendor/bin/drush` with
`--root=/var/www/html/drupal10/web`. For convenience you can add this alias to
your shell:

```bash
alias drush='docker compose exec drupal /var/www/html/drupal10/vendor/bin/drush --root=/var/www/html/drupal10/web'
```

### Keeping submodules up to date

Each `lms/` directory is a normal git repository. To pull the latest commits
from upstream on all four:

```bash
git submodule update --remote
```

Or for a single module:

```bash
git submodule update --remote lms/league
```

---

## Seed database

The seed file (`seed/seed.sql.gz`) captures the full database state after
installation, including all module configuration, test rating data, and help
content. When present, the entrypoint imports it instead of running the full
installer.

### Export a new seed

After making configuration changes in the Drupal UI (e.g. block layout, adding
an organisation), export a fresh seed so those changes survive a container
rebuild:

```bash
docker compose exec drupal /scripts/export-seed.sh
```

The seed is written to `seed/seed.sql.gz` on the host. Commit it to version
control if you want others on the team to share the same starting state.

### Reset to the seed

```bash
docker compose down -v   # wipes the database and files volumes
docker compose up -d     # imports seed.sql.gz automatically
```

### Full rebuild from scratch (no seed)

Remove the seed file, then reset:

```bash
rm seed/seed.sql.gz
docker compose down -v
docker compose up -d     # runs full installation (~3–5 min)
```

---

## Remaining manual configuration

Some steps from `lms_install.txt` require the Drupal admin UI and have not been
automated. Perform them once after the first install, then export a new seed to
preserve them.

| Step                              | Where in the UI                                                        |
|-----------------------------------|------------------------------------------------------------------------|
| Block layout (menus, navigation)  | Admin › Structure › Block Layout                                       |
| Add an Organisation               | Admin (top menu) › Tools (left sidebar) › Add Club/League Organisation |
| User field visibility             | Admin › Configuration › People › Account Settings › Manage Display     |
| Google Maps field on Organisation | Admin › Structure › Organisation › Manage Display                      |

See `lms_install.txt` steps 6, 9, and 10 for the full details.

---

## File layout

```
lmstest/
├── Dockerfile                 – PHP 8.2 / Apache image
├── docker-compose.yml         – service definitions
├── .env                       – environment variables (edit for your setup)
├── config/
│   ├── apache-drupal.conf     – Apache virtual host
│   └── php.ini                – PHP settings (memory_limit, opcache, …)
├── scripts/
│   ├── docker-entrypoint.sh   – container startup logic
│   ├── install-lms.sh         – full drush-based installation
│   └── export-seed.sh         – database export utility
├── seed/
│   └── seed.sql.gz            – compressed seed database (auto-imported on first start)
└── lms/                       – git submodules (LMS source code)
    ├── league/
    ├── rating_list/
    ├── user_tools/
    └── lms_theme/
```
