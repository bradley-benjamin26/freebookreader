# Deploying Free Book Reader on a DigitalOcean Droplet

Step by step, from an empty Droplet to a working site. It puts everything on one server:

```
             https://books.example.org        https://api.books.example.org
                        │                                  │
                  ┌─────┴──────────── Caddy (HTTPS) ───────┴─────┐
                  │ Flutter web build (static files)             │
                  └──────────────────────────────┬───────────────┘
                                                 │ 127.0.0.1:8000
                                       Backend (FastAPI, uvicorn)
                                ┌────────────────┼──────────────────────────┐
                    127.0.0.1:8001               │                          │
              Gutendex (Django, gunicorn)   HathiTrust index      EPUB cache (Gutenberg books,
                        │                   (SQLite, 1.5 GB)      fetched on first read)
                 Postgres (300 MB)
                 + catalog files (2.1 GB)
```

LibriVox, Open Library and DOAB are searched live; nothing of theirs is stored except a 5-minute search cache in
memory. Bookmarks and reading places live on each reader's device, so the server holds nothing that can't be rebuilt.

Replace these placeholders everywhere:

| Placeholder | Meaning |
|---|---|
| `books.example.org` | the address of the app |
| `api.books.example.org` | the address of the backend |
| `you@example.com` | the contact address sent in the User-Agent to the book sources |

Paths used below: the code in `/srv/freebookreader`, data in `/var/lib/freebookreader`, settings in
`/etc/freebookreader`, the built app in `/srv/freebookreader-web`. Everything runs as the user `freebookreader`.

---

## 1. Check the network first (a $6 test Droplet, 15 minutes)

Some book sources block data-centre addresses. Our home address is already refused by DOAB's REST API, OAPEN's
PDFs and HathiTrust's reader. Before choosing a Droplet, create the cheapest one in the region you plan to use, run
these, then destroy it.

```bash
UA="Free Book Reader (you@example.com)"
c() { printf '%-28s ' "$1"; curl -s -o /dev/null -w '%{http_code}\n' -A "$UA" --max-time 20 "$2"; }
c "Gutenberg EPUB"            "https://www.gutenberg.org/ebooks/1342.epub3.images"
c "Gutenberg catalog feed"    "https://gutenberg.org/cache/epub/feeds/rdf-files.tar.bz2" # a big file; the code is enough
c "LibriVox"                  "https://librivox.org/api/feed/audiobooks?title=%5Ehamlet&format=json&limit=1"
c "Open Library search"       "https://openlibrary.org/search.json?q=pride&limit=1"
c "DOAB OpenSearch"           "https://directory.doabooks.org/open-search/discover?query=democracy"
c "DOAB OAI"                  "https://directory.doabooks.org/oai/request?verb=Identify"
c "DOAB REST (blocked at home)" "https://directory.doabooks.org/rest/search?query=democracy"
c "OAPEN library"             "https://library.oapen.org/"
c "HathiTrust file list"      "https://www.hathitrust.org/files/hathifiles/hathi_file_list.json"
c "HathiTrust reader"         "https://babel.hathitrust.org/cgi/pt?id=hvd.hx66p3"
```

`200` (or a redirect, `301`/`302`) is good. A `403` or a timeout means that source blocks the region. For each
source the app needs (Gutenberg, LibriVox, Open Library, DOAB OpenSearch and OAI, the HathiTrust file list), a block
is a reason to try another region or provider. OAPEN, the DOAB REST API and the HathiTrust reader are already
worked around (links open outside the app).

## 2. Create the Droplet and the DNS records

- **Image:** Ubuntu 24.04 LTS.
- **Size:** Basic, 4 GB RAM / 80 GB disk (about $24 a month) is comfortable; 2 GB RAM will probably work.
  Disk use at the start is about 6 GB: catalog files 2.1 GB, HathiTrust index 1.5 GB plus room for a rebuild,
  Postgres 0.3 GB. The EPUB cache adds up to 2 GB (`FBR_EPUB_CACHE_MB`).
- **Authentication:** an SSH key.
- **DNS:** two `A` records pointing at the Droplet's IP address: `books.example.org` and `api.books.example.org`.

Then send the email that is waiting for an IP address: ask info@oapen.org to allow the Droplet's address for DOAB's
REST API and OAPEN's PDF downloads (see AGENTS.md).

## 3. Prepare the server

Log in as root once, then:

```bash
apt update && apt -y upgrade
apt -y install git postgresql rsync bzip2 curl unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades       # security updates install themselves

# Firewall: only SSH and the web. Postgres, Gutendex and the backend listen on 127.0.0.1 only.
ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw --force enable

# Swap: cheap insurance for the monthly HathiTrust rebuild on a small Droplet.
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# The service user and its folders.
adduser --system --group --home /srv/freebookreader freebookreader
mkdir -p /var/lib/freebookreader/epub /etc/freebookreader /srv/freebookreader-web
chown -R freebookreader:freebookreader /var/lib/freebookreader /srv/freebookreader-web
```

**Python 3.14.** The code is tested on Python 3.14 (Ubuntu 24.04 ships 3.12, which is untested). The simplest way
to get 3.14 is `uv`:

```bash
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
sudo -u freebookreader -H uv python install 3.14
```

## 4. Get the code

The repository is private, so give the server a read-only **deploy key**:

```bash
sudo -u freebookreader mkdir -p -m 700 /srv/freebookreader/.ssh
sudo -u freebookreader -H ssh-keygen -t ed25519 -N '' -f /srv/freebookreader/.ssh/id_ed25519
cat /srv/freebookreader/.ssh/id_ed25519.pub
```

Add that key on GitHub (repository → Settings → Deploy keys, read access only), then:

```bash
cd /srv/freebookreader
sudo -u freebookreader -H git clone git@github.com:bradley-benjamin26/freebookreader.git repo
```

The checkout is `/srv/freebookreader/repo`; the rest of this guide uses that path.

Create the top-level `.env` (JSON). The backend sends `projectName` and `email` in its User-Agent and never sends
`name`:

```bash
sudo -u freebookreader tee /srv/freebookreader/repo/.env >/dev/null <<'EOF'
{"name": "", "email": "you@example.com", "projectName": "Free Book Reader"}
EOF
```

## 5. Postgres and Gutendex

```bash
# A database and a role that owns it. Pick a long random password.
DBPASS=$(openssl rand -hex 24)
sudo -u postgres psql -c "CREATE ROLE gutendex LOGIN PASSWORD '$DBPASS';"
sudo -u postgres psql -c "CREATE DATABASE gutendex OWNER gutendex;"
echo "$DBPASS"      # needed in the next file only
```

Gutendex reads `gutendex/gutendex/.env`. Every key must be present, even when empty. Leaving `ADMIN_EMAILS` and
`EMAIL_HOST_ADDRESS` empty turns off the mailed update log.

```bash
cd /srv/freebookreader/repo/gutendex
sudo -u freebookreader tee gutendex/.env >/dev/null <<EOF
ADMIN_EMAILS=
ADMIN_NAMES=
ALLOWED_HOSTS=127.0.0.1,localhost
DATABASE_HOST=127.0.0.1
DATABASE_NAME=gutendex
DATABASE_PASSWORD=$DBPASS
DATABASE_PORT=5432
DATABASE_USER=gutendex
DEBUG=false
EMAIL_HOST=
EMAIL_HOST_ADDRESS=
EMAIL_HOST_PASSWORD=
EMAIL_HOST_USER=
MANAGER_EMAILS=
MANAGER_NAMES=
MEDIA_ROOT=/var/lib/freebookreader/gutendex-media/
SECRET_KEY=$(openssl rand -hex 32)
STATIC_ROOT=/var/lib/freebookreader/gutendex-static/
EOF
chmod 600 gutendex/.env

sudo -u freebookreader -H bash -c '
  uv venv --python 3.14 venv &&
  uv pip install --python venv/bin/python -r requirements.txt gunicorn &&
  venv/bin/python manage.py migrate &&
  venv/bin/python manage.py updatecatalog'
```

The first `updatecatalog` downloads Project Gutenberg's whole catalog and imports every book; it takes a while.
It exits with an error if any step fails. Check that it worked:

```bash
sudo -u freebookreader /srv/freebookreader/repo/gutendex/venv/bin/python \
  /srv/freebookreader/repo/gutendex/manage.py shell -c "from books.models import Book; print(Book.objects.count())"
```

Run Gutendex as a service on `127.0.0.1:8001`, `/etc/systemd/system/gutendex.service`:

```ini
[Unit]
Description=Gutendex (Project Gutenberg catalog API, local only)
After=network.target postgresql.service

[Service]
User=freebookreader
WorkingDirectory=/srv/freebookreader/repo/gutendex
ExecStart=/srv/freebookreader/repo/gutendex/venv/bin/gunicorn gutendex.wsgi --bind 127.0.0.1:8001 --workers 2
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Refresh the catalog every night, `/etc/systemd/system/gutendex-update.service` and `.timer`:

```ini
# gutendex-update.service
[Unit]
Description=Refresh the Gutendex catalog from Project Gutenberg
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=oneshot
User=freebookreader
WorkingDirectory=/srv/freebookreader/repo/gutendex
ExecStart=/srv/freebookreader/repo/gutendex/venv/bin/python manage.py updatecatalog
TimeoutStartSec=3h
Nice=10
```

```ini
# gutendex-update.timer
[Unit]
Description=Nightly Gutendex catalog refresh

[Timer]
OnCalendar=*-*-* 04:00:00 UTC
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
```

```bash
systemctl daemon-reload
systemctl enable --now gutendex.service gutendex-update.timer
curl -s 'http://127.0.0.1:8001/books/?ids=1342' | head -c 300; echo
```

## 6. The backend

Settings come from `FBR_*` variables; put them in `/etc/freebookreader/backend.env`:

```bash
tee /etc/freebookreader/backend.env >/dev/null <<'EOF'
# Only the app's address may call the API from a browser.
FBR_CORS_ORIGINS=https://books.example.org
FBR_GUTENDEX_URL=http://127.0.0.1:8001
FBR_HATHITRUST_INDEX=/var/lib/freebookreader/hathitrust.sqlite
FBR_EPUB_CACHE_DIR=/var/lib/freebookreader/epub
FBR_EPUB_CACHE_MB=2000
EOF

cd /srv/freebookreader/repo/backend
sudo -u freebookreader -H bash -c '
  uv venv --python 3.14 venv &&
  uv pip install --python venv/bin/python -r requirements.lock'
```

`requirements.lock` is the exact set the tests passed with (`pip freeze`, test packages included). Other settings,
such as search time limits, are listed in `backend/tests/README.md`; the defaults are fine.

`/etc/systemd/system/freebookreader-backend.service`:

```ini
[Unit]
Description=Free Book Reader backend
After=network.target gutendex.service

[Service]
User=freebookreader
WorkingDirectory=/srv/freebookreader/repo/backend
EnvironmentFile=/etc/freebookreader/backend.env
# One worker: the search cache, the outage tracker and the per-source limits live in the process. With several
# workers each would keep its own, and Open Library would see several times our request rate.
ExecStart=/srv/freebookreader/repo/backend/venv/bin/uvicorn app.main:create_app --factory \
  --host 127.0.0.1 --port 8000 --workers 1 --proxy-headers
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload && systemctl enable --now freebookreader-backend.service
curl -s http://127.0.0.1:8000/health; echo      # {"status":"ok","hathitrust_index":false} until step 7
```

## 7. The HathiTrust index

Two ways to get the first index:

- **Copy the one you already have** (1.5 GB, built 2026-10-11). From your own computer:
  ```bash
  rsync -P backend/cache/hathitrust.sqlite root@<droplet-ip>:/var/lib/freebookreader/hathitrust.sqlite
  ssh root@<droplet-ip> chown freebookreader:freebookreader /var/lib/freebookreader/hathitrust.sqlite
  ```
  The nightly job then adds the daily files since it was built.
- **Or build it on the server** (downloads 1.2 GB, about 4 minutes). Install the timer first and start it once (below).

Install the nightly job from `backend/deploy/`. Copy the two files, then edit the service: set
`WorkingDirectory` and `ExecStart` to `/srv/freebookreader/repo/backend/...`, and add
`EnvironmentFile=/etc/freebookreader/backend.env`, so the job writes the same index the backend reads.

```bash
cp /srv/freebookreader/repo/backend/deploy/hathitrust-update.{service,timer} /etc/systemd/system/
nano /etc/systemd/system/hathitrust-update.service        # the edits above
systemctl daemon-reload && systemctl enable --now hathitrust-update.timer
systemctl start hathitrust-update.service                 # run once now; a first build takes about 4 minutes
journalctl -u hathitrust-update.service -n 20
curl -s http://127.0.0.1:8000/health; echo                # "hathitrust_index": true
```

The backend opens the index per search, so it does not need a restart after an update.

## 8. Build and upload the app

Build on your own computer (Flutter is not needed on the server), with the backend's public address:

```bash
cd app
flutter build web --release --dart-define=BACKEND_URL=https://api.books.example.org
rsync -a --delete build/web/ root@<droplet-ip>:/srv/freebookreader-web/
```

Do not add `--dart-define=FBR_SEMANTICS=true` to a production build; it is only for browser test runs.

## 9. HTTPS with Caddy

Caddy gets and renews the certificates itself.

```bash
apt -y install debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
apt update && apt -y install caddy
```

`/etc/caddy/Caddyfile`:

```
books.example.org {
	root * /srv/freebookreader-web
	encode zstd gzip
	# The app routes in the browser; unknown paths load the app.
	try_files {path} /index.html
	file_server
}

api.books.example.org {
	# The backend gzips its own answers.
	reverse_proxy 127.0.0.1:8000
}
```

```bash
systemctl reload caddy
```

## 10. Check that it works

```bash
curl -s https://api.books.example.org/health; echo
curl -s 'https://api.books.example.org/search?q=pride%20and%20prejudice' | head -c 400; echo
```

Then, in a browser at `https://books.example.org`:

1. Search for "Pride and Prejudice". Results arrive from several sources, and no source is listed as missing.
2. Open the Project Gutenberg book. The text appears in the app (this checks the EPUB download and the
   `/publications` path).
3. Search with **Audio** chosen and play a LibriVox recording.
4. Search for something HathiTrust holds (try "history of rome"); its results open HathiTrust's site.
5. On a phone, check that the first result is visible without scrolling.

If a source shows as missing, `journalctl -u freebookreader-backend -n 100` says why.

## 11. Keeping it running

**Watch:**
- `https://api.books.example.org/health`, from an uptime monitor (for example UptimeRobot, free). Alert if it is
  down, or if `"hathitrust_index"` is `false`.
- Disk: `df -h /`. The EPUB cache stays under `FBR_EPUB_CACHE_MB`; the catalog and the index grow slowly.
- Logs: `journalctl -u freebookreader-backend`, `-u gutendex`, `-u gutendex-update`, `-u hathitrust-update`.
- Timers: `systemctl list-timers` shows the next catalog and index refreshes.

**Deploy a new version:**

```bash
cd /srv/freebookreader/repo
sudo -u freebookreader git pull
sudo -u freebookreader -H bash -c 'cd backend && uv pip install --python venv/bin/python -r requirements.lock'
sudo -u freebookreader -H bash -c 'cd gutendex && uv pip install --python venv/bin/python -r requirements.txt gunicorn && venv/bin/python manage.py migrate'
systemctl restart gutendex freebookreader-backend
```

Then rebuild and upload the app (step 8). If a pull adds a Gutendex migration that adds catalog fields, run the
catalog update once by hand: `systemctl start gutendex-update.service`.

**Backups:** only `/etc/freebookreader/`, the two `.env` files and `/etc/caddy/Caddyfile`. Everything else is
rebuilt by the update jobs, and readers' bookmarks are on their devices.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Every search shows a source as missing (`error`) | The backend cannot reach it. `curl` it from the server with the User-Agent from step 1. |
| HathiTrust is always missing | No index: `/health` says `"hathitrust_index": false`. Run `systemctl start hathitrust-update.service`. Check that the service and the backend use the same `FBR_HATHITRUST_INDEX`. |
| `updatecatalog` fails with "The temporary path ... already exists" | An earlier run was killed. Make sure none is running (`systemctl status gutendex-update`), then delete `gutendex/catalog_files/tmp`. |
| The browser blocks API calls (CORS) | `FBR_CORS_ORIGINS` must be exactly `https://books.example.org`, with no trailing slash. Restart the backend after changing it. |
| Gutenberg books don't open in the app | `journalctl -u freebookreader-backend`. The EPUB download from gutenberg.org failed, or the book is newer than the last catalog update (it answers 404 until `updatecatalog` runs). |
| A Gutendex request answers 400 | `ALLOWED_HOSTS` in `gutendex/gutendex/.env` must include `127.0.0.1`. |
