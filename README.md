# inst_dm

[![CI](https://github.com/musa1756/inst_dm/actions/workflows/ci.yml/badge.svg)](https://github.com/musa1756/inst_dm/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-2f312d.svg)](./LICENSE)

`inst_dm` — самостоятельная автоматизация Instagram для одного Professional Account. Комментарий, входящее сообщение в Direct или ответ на Story может запустить публичный ответ, private reply, кнопку с материалом, проверку подписки и follow-up.

Всё принадлежит владельцу установки: домен, VPS, Meta-приложение, база и секреты. Проект не просит пароль Instagram, не отправляет данные разработчику и использует только официальный Instagram API with Instagram Login.

> Версия `0.1.1` основана на проверенном открытом проекте [xvn3x/comment-to-dm](https://github.com/xvn3x/comment-to-dm) по MIT-лицензии и адаптирована под полностью самостоятельную установку. Перед важным аккаунтом проверьте сценарий на тестовой публикации.

## Что понадобится

- собственный домен или поддомен, например `dm.example.com`;
- зарубежный VPS в регионе, где доступны Instagram и Meta API;
- Ubuntu 24.04 LTS или Ubuntu 26.04 LTS, 2 vCPU, 2 ГБ RAM, 30 ГБ диска и публичный IPv4;
- Instagram Professional Account: Creator или Business;
- собственное приложение в Meta for Developers;
- примерно 40–60 минут на первую настройку.

Facebook Page для используемого здесь потока Instagram Login не требуется. Открытыми должны быть только ваш SSH-порт и TCP `80`/`443`; PostgreSQL-порт `5432` наружу не открывается.

## Как всё связано

```text
Пользователь Instagram
        │ комментарий / Direct / Story
        ▼
Официальный Meta API ── webhook ──► ваш домен (HTTPS)
                                      │
                                      ▼
                              inst_dm + worker
                                      │
                                      ▼
                           PostgreSQL внутри VPS
```

Разработчик проекта не находится в этой цепочке и не получает доступ к данным установки.

## Быстрая установка

### 1. Подготовьте VPS и домен

Создайте VPS с Ubuntu 24.04 LTS или Ubuntu 26.04 LTS в зарубежном регионе. В firewall провайдера разрешите SSH, TCP `80` и TCP `443`.

У регистратора домена создайте DNS-запись:

```text
Тип: A
Имя: dm
Значение: ПУБЛИЧНЫЙ_IP_VPS
```

Для корневого домена имя обычно `@`. Дождитесь, пока домен начнёт возвращать IP сервера. Если используете проксирование DNS-провайдера, на время первого запуска лучше оставить запись в режиме «только DNS».

### 2. Запустите установщик на VPS

Подключитесь к серверу по SSH или откройте его веб-консоль и выполните:

```bash
sudo apt update
sudo apt install -y git
git clone --depth 1 --branch v0.1.1 https://github.com/musa1756/inst_dm.git /tmp/inst_dm
cd /tmp/inst_dm
sudo bash scripts/install-vps.sh dm.example.com 203.0.113.10
```

Замените `dm.example.com` на свой домен, а `203.0.113.10` — на публичный IPv4 VPS. Установщик проверит Ubuntu, ресурсы и совпадение DNS с этим IP, установит Docker, создаст уникальные секреты, запустит PostgreSQL и HTTPS через Caddy, а затем включит ежедневные структурно проверенные резервные копии.

Пароль администратора показывается один раз. Сохраните его в менеджере паролей и никому не отправляйте.

### 3. Подключите Instagram

Откройте `https://ВАШ_ДОМЕН`, войдите и перейдите в **Подключение**. Панель покажет точные значения для Meta:

- OAuth callback;
- Webhook callback и Verify Token;
- Deauthorize callback;
- Data Deletion URL;
- Privacy Policy URL.

В Meta for Developers создайте своё Business-приложение, добавьте **Instagram API with Instagram Login** и разрешения:

- `instagram_business_basic`;
- `instagram_business_manage_comments`;
- `instagram_business_manage_messages`.

Добавьте нужный Instagram-аккаунт тестировщиком, примите приглашение в Instagram, перенесите URL из панели `inst_dm`, подпишитесь на `comments`, `messages` и `messaging_postbacks`, затем вставьте App ID и App Secret в собственную панель.

Пароль Instagram вводится только на официальной странице Meta/Instagram. Не вставляйте его в `inst_dm`, `.env`, терминал или сообщения.

Полный маршрут от покупки инфраструктуры до первого реального комментария: **[docs/INSTALL-RU.md](./docs/INSTALL-RU.md)**. Инструкция для AI-помощника, который должен вести пользователя по одному шагу: **[docs/AI-INSTALL.md](./docs/AI-INSTALL.md)**.

## Проверка после установки

На VPS:

```bash
cd /opt/inst_dm
sudo docker compose ps
sudo docker compose exec -T app node -e 'fetch("http://127.0.0.1:3000/ready").then(async r => { console.log(await r.text()); process.exit(r.ok ? 0 : 1) })'
sudo systemctl status inst_dm-backup.timer --no-pager
```

Ожидаемый ответ готовности:

```json
{"ok":true,"database":true,"worker":true}
```

Первое правило тестируйте на отдельном Post/Reel, с уникальным ключевым словом и вторым Instagram-аккаунтом. Старый уже обработанный комментарий не сработает повторно — это защита от дублей.

## Обслуживание

Ручной backup и его безопасная проверка:

```bash
sudo /opt/inst_dm/scripts/backup.sh manual
sudo /opt/inst_dm/scripts/verify-backup.sh
```

Ежедневный backup проверяет читаемость дампа и архива. `verify-backup.sh` дополнительно восстанавливает дамп в одноразовую БД, проверяет обязательные таблицы и удаляет тестовую БД, не меняя рабочую.

Полное восстановление меняет рабочую БД. Сначала проверьте точный путь архива; скрипт сам создаст ещё одну страховочную копию:

```bash
sudo INSTDM_RESTORE_CONFIRM=RESTORE_INST_DM \
  /opt/inst_dm/scripts/restore-backup.sh \
  /var/backups/inst_dm/<archive>.tar.gz
```

По умолчанию `.env` текущей установки сохраняется. Добавляйте `INSTDM_RESTORE_ENV=1` только когда осознанно восстанавливаете секреты из архива на новом сервере.

Обновление выполняется только на явно выбранный релизный тег. Перед заменой версии автоматически создаётся backup, а при неуспешном `/ready` приложение откатывается:

```bash
sudo /opt/inst_dm/scripts/update-vps.sh v0.1.1
```

Копии в `/var/backups/inst_dm` содержат базу и production-секреты. Не публикуйте их и периодически храните свежую копию отдельно от VPS в зашифрованном виде.

## Возможности и границы

- одна установка — один Instagram Creator/Business account;
- правила для комментариев, входящих Direct и ответов/реакций на Stories;
- ключевые слова, точное совпадение или любой входящий текст;
- публичные ответы, private reply, HTTPS- и postback-кнопки;
- проверка подписки только после добровольного postback пользователя;
- долговечная очередь, повторы, rate-limit control, watchdog и защита от дублей;
- RU/EN, светлая и тёмная темы, интерфейс от 320 px;
- локальная аналитика и журнал без хранения текста входящих комментариев и Direct;
- ежедневные структурно проверенные backup, отдельная полная проверка восстановления и безопасное обновление с rollback.

Не поддерживаются холодные рассылки, scraping, Instagram cookies, welcome-DM каждому новому подписчику, несколько аккаунтов в одной установке и сложный visual flow builder. Meta может менять правила, разрешения и требования App Review; официальный API снижает риск, но не отменяет ограничения платформы.

## Локальная разработка

Нужны Node.js 22+ и PostgreSQL:

```bash
npm ci
npm test
npm run build
npm run lint
```

Production-архитектура: React/Vite, Fastify/TypeScript, PostgreSQL, встроенный worker, Caddy и Docker Compose. Проверки состояния доступны по `/health` и `/ready`.

## Безопасность и происхождение

Секреты не должны попадать в Git. Подробная модель угроз и порядок действий при утечке: **[SECURITY.md](./SECURITY.md)**.

Проект распространяется по MIT-лицензии. Исходная атрибуция сохранена в [LICENSE](./LICENSE), а сведения о производной работе — в [NOTICE.md](./NOTICE.md).
