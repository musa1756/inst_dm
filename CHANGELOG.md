# Changelog

## 0.1.0 — 2026-08-22

Первый релиз `inst_dm`:

- полностью самостоятельная установка на зарубежный Ubuntu 24.04 VPS и собственный домен;
- обязательная сверка DNS A-записи с публичным IPv4 выбранного VPS;
- собственные пути `/opt/inst_dm`, `/var/backups/inst_dm`, service user, cookie, база, Docker project и systemd units;
- автоматический HTTPS через Caddy и закрытый от интернета PostgreSQL;
- генерация независимых admin/session/encryption/webhook/database secrets;
- ежедневные структурно проверенные backup, полная проверка восстановления в одноразовой БД и явный restore;
- обновление только по аннотированному release tag с backup, readiness check и rollback;
- отдельная read-only диагностика `scripts/doctor.sh`;
- инструкция от выбора VPS и DNS до Meta OAuth, webhooks и первого реального теста;
- удалены конфигурации, привязанные к инфраструктуре исходного сопровождающего и альтернативным хостинг-платформам;
- сохранена MIT-атрибуция исходного проекта `xvn3x/comment-to-dm`.
