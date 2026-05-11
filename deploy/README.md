# Home Server Deployment

This deployment runs the app, Postgres, and Cloudflare Tunnel with Docker Compose.
No app or database ports are published on the host; Cloudflare reaches Phoenix
through the `cloudflared` container on the private compose network.

## Cloudflare setup

1. In Cloudflare Zero Trust, create a Cloudflared tunnel.
2. Copy the tunnel token into `CLOUDFLARED_TOKEN` in `/etc/receipts/receipts.env`.
3. Add a public hostname for your domain, for example `receipts.example.com`.
4. Set the hostname service URL to `http://web:4000`.

## Debian bootstrap

On a fresh Debian host, run the script from a temporary checkout:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/YOUR_USER/receipts.git /tmp/receipts
cd /tmp/receipts
sudo REPO_URL=https://github.com/YOUR_USER/receipts.git ./deploy/bin/bootstrap-debian.sh
```

If you clone or copy the repo yourself, put it at `/opt/receipts` and run the
bootstrap script from there without `REPO_URL`.

The bootstrap installs Docker, Docker Compose, UFW, fail2ban, unattended
upgrades, systemd units, and a daily Postgres backup timer. UFW allows SSH and
denies inbound traffic; the web app is exposed only through Cloudflare Tunnel.

## Configure secrets

Create the server env file from the example:

```bash
sudo install -m 0640 -o root -g receipts deploy/receipts.env.example /etc/receipts/receipts.env
sudo editor /etc/receipts/receipts.env
```

Generate secrets on the server:

```bash
openssl rand -base64 48  # SECRET_KEY_BASE
openssl rand -base64 32  # POSTGRES_PASSWORD
```

Required values:

- `PHX_HOST`
- `SECRET_KEY_BASE`
- `ADMIN_PASSWORD`
- `POSTGRES_PASSWORD`
- `CLOUDFLARED_TOKEN`
- `RIOT_API_KEY`

Discord and Gemini values are required when those features are enabled.

## Deploy

```bash
sudo -u receipts /opt/receipts/deploy/bin/deploy.sh
sudo systemctl enable receipts.service
```

Deploying builds the release image, starts Postgres, runs migrations, and then
starts the web and Cloudflare Tunnel containers.

The deploy script passes `RECEIPTS_VERSION` into the image and runtime
environment. With a Git checkout this is the short commit SHA, with `-dirty`
appended when the checkout has uncommitted changes. The app exposes it at:

```bash
curl https://receipts.example.com/version
```

Useful commands:

```bash
sudo docker compose --env-file /etc/receipts/receipts.env -f /opt/receipts/deploy/docker-compose.prod.yml ps
sudo docker compose --env-file /etc/receipts/receipts.env -f /opt/receipts/deploy/docker-compose.prod.yml logs -f --tail=100 web
sudo systemctl status receipts.service
sudo systemctl status receipts-backup.timer
```

## Backups

Backups are written to `/var/backups/receipts` and retained for 14 days by
default. Run one manually with:

```bash
sudo /opt/receipts/deploy/bin/backup-postgres.sh
```

To restore, stop the app, create an empty database if needed, and pipe a backup
into `psql` inside the Postgres container.
