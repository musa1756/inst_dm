#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

PROJECT_DIR="${INSTDM_PROJECT_DIR:-/opt/inst_dm}"
BACKUP_DIR="${INSTDM_BACKUP_DIR:-/var/backups/inst_dm}"
APP_USER="${INSTDM_APP_USER:-instdm}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "Ошибка: $*" >&2
  exit 1
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  fail "запустите установщик через sudo: sudo bash scripts/install-vps.sh"
fi

if [[ ! -r /etc/os-release ]]; then
  fail "не удалось определить операционную систему"
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  fail "установщик поддерживает только Ubuntu Server"
fi
case "${VERSION_ID:-}" in
  24.04|26.04) ;;
  *) fail "установщик поддерживает Ubuntu 24.04 LTS и Ubuntu 26.04 LTS" ;;
esac

if [[ -f "$PROJECT_DIR/.env" ]]; then
  fail "в $PROJECT_DIR уже есть установка. Скрипт не перезаписывает рабочие данные"
fi

normalize_host() {
  local raw="$1"
  raw="${raw#http://}"
  raw="${raw#https://}"
  raw="${raw%%/*}"
  raw="${raw%.}"

  if [[ "$raw" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    fail "укажите собственный домен, а не IP-адрес (например, dm.example.com)"
  fi

  if [[ ! "$raw" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ || "$raw" != *.* ]]; then
    fail "укажите доменное имя, например dm.example.com"
  fi
  printf '%s\n' "${raw,,}"
}

validate_ipv4() {
  local raw="$1"
  local part
  local -a parts
  [[ "$raw" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "неверный публичный IPv4: $raw"
  IFS='.' read -r -a parts <<< "$raw"
  for part in "${parts[@]}"; do
    (( part >= 0 && part <= 255 )) || fail "неверный публичный IPv4: $raw"
  done
}

host_input="${1:-}"
if [[ -z "$host_input" ]]; then
  if [[ ! -t 0 ]]; then
    fail "передайте домен первым аргументом, например: sudo bash scripts/install-vps.sh dm.example.com"
  fi
  echo "Введите домен, A-запись которого уже указывает на этот VPS (например, dm.example.com)."
  read -r -p "> " host_input
fi

APP_DOMAIN="$(normalize_host "$host_input")"
expected_ipv4="${2:-}"
if [[ -z "$expected_ipv4" ]]; then
  if [[ ! -t 0 ]]; then
    fail "передайте публичный IPv4 VPS вторым аргументом"
  fi
  echo "Введите публичный IPv4 этого VPS, чтобы проверить DNS."
  read -r -p "> " expected_ipv4
fi
validate_ipv4 "$expected_ipv4"

cpu_count="$(nproc)"
memory_kib="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
disk_kib="$(df -Pk / | awk 'NR == 2 { print $4 }')"
(( cpu_count >= 1 )) || fail "нужен минимум 1 vCPU; найдено: $cpu_count"
(( memory_kib >= 1800000 )) || fail "нужно минимум 2 ГБ RAM"
(( disk_kib >= 23068672 )) || fail "нужно минимум 22 ГБ свободного места на диске"

echo
echo "Inst DM будет доступен по адресу: https://$APP_DOMAIN"
echo "Устанавливаю Docker, приложение, HTTPS и ежедневные резервные копии."
echo

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git docker.io docker-compose-v2 unattended-upgrades
systemctl enable --now docker

resolved_ipv4="$(getent ahostsv4 "$APP_DOMAIN" | awk '{ print $1 }' | sort -u | paste -sd, -)"
if [[ -z "$resolved_ipv4" ]]; then
  fail "домен $APP_DOMAIN ещё не имеет доступной A-записи. Настройте DNS и повторите установку"
fi
if ! tr ',' '\n' <<< "$resolved_ipv4" | grep -Fqx "$expected_ipv4"; then
  fail "A-запись $APP_DOMAIN указывает на $resolved_ipv4, а ожидается IP этого VPS: $expected_ipv4"
fi
echo "DNS проверен: $APP_DOMAIN -> $resolved_ipv4"

# На тарифах с 1 vCPU и 2 ГБ RAM сборка образа надёжно проходит только с подкачкой.
if [[ -z "$(swapon --noheadings --show=NAME)" ]] && (( memory_kib < 3500000 )); then
  if [[ ! -e /swapfile ]]; then
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
  fi
  swapon /swapfile || fail "не удалось включить /swapfile. Проверьте этот файл вручную и повторите установку"
  grep -Eq '^/swapfile[[:space:]]' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "Добавлен файл подкачки 2 ГБ: на небольшом VPS без него сборке может не хватить памяти."
fi

if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "/var/lib/$APP_USER" --shell /usr/sbin/nologin "$APP_USER"
fi
usermod -aG docker "$APP_USER"

install -d -m 0750 -o "$APP_USER" -g "$APP_USER" "$PROJECT_DIR"
install -d -m 0750 -o "$APP_USER" -g "$APP_USER" "$PROJECT_DIR/incoming"

if git -C "$SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$SOURCE_DIR" archive --format=tar HEAD | tar -xf - -C "$PROJECT_DIR"
else
  fail "запускайте установщик из клонированного GitHub-репозитория"
fi

chmod 755 "$PROJECT_DIR/scripts/"*.sh
chmod 644 "$PROJECT_DIR/Caddyfile"

env_output="$(docker run --rm \
  -v "$PROJECT_DIR:/app" \
  -w /app \
  node:22-bookworm-slim@sha256:d649c27dae7ba0137b3cef5dd75baa422c08dc3d9e3fc0c23dfb172dc3cc6436 \
  node scripts/generate-env.mjs "$APP_DOMAIN")"

echo "$env_output"
echo
echo "Сохраните пароль администратора сейчас. Установка продолжится автоматически."
echo

chown -R "$APP_USER:$APP_USER" "$PROJECT_DIR"
chmod 600 "$PROJECT_DIR/.env"
install -m 0644 "$PROJECT_DIR/deploy/apt/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades

cd "$PROJECT_DIR"
docker compose up -d --build

ready=0
for _ in $(seq 1 90); do
  if docker compose exec -T app node -e \
    'fetch("http://127.0.0.1:3000/ready").then(async response => { if (!response.ok) process.exit(1); const body = await response.json(); if (!body.ok || !body.database || !body.worker) process.exit(1); }).catch(() => process.exit(1))' \
    >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done

if (( ready != 1 )); then
  docker compose logs --tail=120 app >&2 || true
  fail "приложение не стало готово за 3 минуты. Скопируйте лог выше при обращении за помощью"
fi

install -d -m 0700 -o "$APP_USER" -g "$APP_USER" "$BACKUP_DIR"
install -m 0644 "$PROJECT_DIR/deploy/systemd/inst_dm-backup.service" /etc/systemd/system/
install -m 0644 "$PROJECT_DIR/deploy/systemd/inst_dm-backup.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now inst_dm-backup.timer
systemctl start inst_dm-backup.service

echo
echo "Установка завершена."
echo "Адрес: https://$APP_DOMAIN"
echo "Откройте его в браузере и сохраните показанный выше пароль администратора."
echo "Если страница пока не открывается, подождите 1–2 минуты: Caddy получает HTTPS-сертификат."
echo "Дальше следуйте разделу «Настройка Meta» в docs/INSTALL-RU.md."
