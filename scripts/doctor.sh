#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${INSTDM_PROJECT_DIR:-/opt/inst_dm}"

ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }

echo "Inst DM: безопасная диагностика без изменения данных"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  echo "OS: ${PRETTY_NAME:-unknown}"
else
  warn "Не удалось прочитать /etc/os-release"
fi

echo "CPU: $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo unknown)"
echo "Memory:"
free -h 2>/dev/null || vm_stat 2>/dev/null | head -n 6 || true
echo "Disk:"
df -h "$PROJECT_DIR" 2>/dev/null || df -h /

if [[ ! -f "$PROJECT_DIR/docker-compose.yml" || ! -f "$PROJECT_DIR/.env" ]]; then
  warn "Рабочая установка не найдена в $PROJECT_DIR"
  exit 2
fi
ok "Установка найдена: $PROJECT_DIR"

cd "$PROJECT_DIR"
docker compose ps

if docker compose exec -T app node -e \
  'fetch("http://127.0.0.1:3000/ready").then(async r => { console.log(await r.text()); process.exit(r.ok ? 0 : 1) }).catch(() => process.exit(1))'; then
  ok "Приложение, база и worker готовы"
else
  warn "Проверка /ready не пройдена"
fi

if systemctl is-active --quiet inst_dm-backup.timer; then
  ok "Таймер backup активен"
  systemctl list-timers inst_dm-backup.timer --no-pager
else
  warn "Таймер inst_dm-backup.timer не активен"
fi

if [[ -d /var/backups/inst_dm ]]; then
  echo "Последние backup-файлы:"
  find /var/backups/inst_dm -maxdepth 1 -type f -name 'inst_dm-*.tar.gz' -printf '%TY-%Tm-%Td %TH:%TM %s bytes %f\n' \
    | sort -r | head -n 3
else
  warn "Каталог /var/backups/inst_dm не найден"
fi

echo "Готово. Скрипт не выводит .env, токены, пароли или содержимое сообщений."
