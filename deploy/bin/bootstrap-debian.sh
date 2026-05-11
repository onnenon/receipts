#!/usr/bin/env bash
set -euo pipefail

APP_USER=${APP_USER:-receipts}
APP_DIR=${APP_DIR:-/opt/receipts}
ENV_DIR=${ENV_DIR:-/etc/receipts}
BACKUP_DIR=${BACKUP_DIR:-/var/backups/receipts}
ENV_FILE="$ENV_DIR/receipts.env"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root, for example: sudo $0" >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl fail2ban git gnupg unattended-upgrades ufw

install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi

. /etc/os-release
cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable
EOF

apt-get update
apt-get install -y containerd.io docker-buildx-plugin docker-ce docker-ce-cli docker-compose-plugin

if ! id "$APP_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" --home "$APP_DIR" "$APP_USER"
fi

usermod -aG docker "$APP_USER"

install -d -o "$APP_USER" -g "$APP_USER" "$APP_DIR"
install -d -m 0750 -o root -g "$APP_USER" "$ENV_DIR"
install -d -m 0750 -o root -g "$APP_USER" "$BACKUP_DIR"

if [[ -n "${REPO_URL:-}" && ! -d "$APP_DIR/.git" ]]; then
  git clone "$REPO_URL" "$APP_DIR"
  chown -R "$APP_USER:$APP_USER" "$APP_DIR"
fi

if [[ ! -f "$ENV_FILE" && -f "$APP_DIR/deploy/receipts.env.example" ]]; then
  install -m 0640 -o root -g "$APP_USER" "$APP_DIR/deploy/receipts.env.example" "$ENV_FILE"
fi

cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

ufw allow OpenSSH
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

cat >/etc/systemd/system/receipts.service <<EOF
[Unit]
Description=Receipts Docker Compose application
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/docker compose --env-file $ENV_FILE -f $APP_DIR/deploy/docker-compose.prod.yml up -d postgres web cloudflared
ExecStop=/usr/bin/docker compose --env-file $ENV_FILE -f $APP_DIR/deploy/docker-compose.prod.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/receipts-backup.service <<EOF
[Unit]
Description=Backup Receipts Postgres database
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
Environment=APP_DIR=$APP_DIR
Environment=ENV_FILE=$ENV_FILE
Environment=BACKUP_DIR=$BACKUP_DIR
ExecStart=$APP_DIR/deploy/bin/backup-postgres.sh
EOF

cat >/etc/systemd/system/receipts-backup.timer <<'EOF'
[Unit]
Description=Run Receipts Postgres backup daily

[Timer]
OnCalendar=*-*-* 04:15:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable docker fail2ban unattended-upgrades

if [[ -x "$APP_DIR/deploy/bin/backup-postgres.sh" ]]; then
  systemctl enable receipts-backup.timer
fi

echo "Debian host bootstrap complete."
echo "Next:"
echo "  1. Put the application checkout in $APP_DIR if it is not already there."
echo "  2. Fill in $ENV_FILE."
echo "  3. Run: sudo -u $APP_USER $APP_DIR/deploy/bin/deploy.sh"
echo "  4. Run: sudo systemctl enable receipts.service"
