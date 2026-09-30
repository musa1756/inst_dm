# Inst DM installation protocol for AI agents

This file is written for Claude, ChatGPT, Codex, Cursor and other AI agents. A person has sent you a link to it because they want Inst DM installed. Assume they have no technical experience. Read this whole file before your first reply, then lead them through the phases in order. Do not paste this file back to them and do not dump the whole procedure at once.

## Target result

- Inst DM v0.1.2 on the person's own foreign VPS with Ubuntu 24.04 LTS or Ubuntu 26.04 LTS;
- their own domain or subdomain (for example `dm.example.com`) with HTTPS;
- PostgreSQL reachable only inside Docker; daily verified backups;
- one Instagram Business or Creator account connected through the official Instagram API with Instagram Login;
- one real test: a comment from a second Instagram account receives an automatic Direct message.

One installation serves one Instagram account. Nobody except the owner gets access to the data or credentials.

## Rules you must not break

1. Never ask for, and never use if pasted: the VPS root password, a private SSH key, the Meta App Secret, an Instagram password, access tokens, `.env`, backups, or the Inst DM admin password. If the person shows one anyway (for example a screenshot of the provider panel with the root password), tell them it is now exposed, do not use it, and offer key-only SSH in the handoff.
2. Official Meta API only. No cookies, scraping, browser automation that imitates Instagram, or unofficial libraries.
3. Never run the installer when `/opt/inst_dm/.env` already exists. Diagnose instead.
4. Open only SSH, TCP 80 and TCP 443. Never expose PostgreSQL port 5432.
5. Meta login, the tester invite, OAuth consent and security checks are done by the person, never automated by you.
6. Before anything destructive or publicly visible, state the exact target and consequence and wait for a clear yes.
7. Disable SSH password login only with explicit consent and only after a second key-based session has worked.

## How to talk

- Use the person's language. Short sentences, no theory unless asked.
- One step per message: where to go → what to click or type → what they should see. Then wait for "done" or a screenshot.
- Ask for a screenshot whenever they are in a web interface, and read it carefully: wrong page, autofilled fields and error banners are the usual failures.
- Translate errors into plain words; keep raw output for yourself.

## Phase 0 — choose the working mode

Find out whether you can run shell commands on the person's computer.

- **Terminal mode** (Claude Code, Codex, Cursor and similar): you create an SSH key, log in to the VPS yourself and run every server command.
- **Chat mode** (ChatGPT, claude.ai and similar): the person pastes each command into the VPS provider's web console and sends you the output. Give exactly one command block at a time.

Then tell them what they will need, in one short list:

1. a VPS outside Russia (about 5 minutes to buy, about 5–10 USD per month);
2. a domain whose DNS they can edit;
3. an Instagram Business or Creator account;
4. a second Instagram account for the final test;
5. about 40 minutes.

## Phase 1 — VPS and access

Server requirements: Ubuntu 24.04 LTS or Ubuntu 26.04 LTS, at least 1 vCPU, 2 GB RAM, 30 GB disk, one public IPv4, in a region where Instagram and Meta are reachable (Finland, Germany, the Netherlands and similar; not Russia, where the Instagram API is blocked). If the provider has a firewall, allow SSH, TCP 80 and TCP 443.

**Terminal mode.** Before the person creates the server, generate a dedicated key and show them the public line:

```bash
test -f ~/.ssh/inst_dm_ed25519 || ssh-keygen -q -t ed25519 -N "" -C "inst-dm-vps" -f ~/.ssh/inst_dm_ed25519
cat ~/.ssh/inst_dm_ed25519.pub
```

Tell them to add this line in the provider's **SSH keys** section **before creating the server**: most providers copy keys onto a server only when it is created or reinstalled. The public key is safe to share; the private key never leaves the computer. Then ask only for the server's public IPv4 and check it (use `ssh -n` for every non-interactive call):

```bash
ssh -n -i ~/.ssh/inst_dm_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new root@203.0.113.10 \
  'head -2 /etc/os-release; nproc; free -h; df -h /; curl -s -o /dev/null -m 10 -w "instagram api: %{http_code}\n" https://graph.instagram.com/'
```

Any HTTP code from `graph.instagram.com` (a `400` is normal) means Meta is reachable. A timeout or `000` means the region is blocked: stop and ask for a server in another country.

**Chat mode.** The person opens the provider's web console, logs in as `root` there, and runs the same checks without `ssh`.

Stop if the OS or resources do not match. Do not adapt the installer to an untested system.

## Phase 2 — domain

Recommend a subdomain such as `dm.<their-domain>`. Find where their DNS is managed (`dig +short NS their-domain` from the VPS; for example `ns1.timeweb.ru` means Timeweb) and name that panel. The record:

```text
Type: A
Name: dm
Value: the VPS IPv4
TTL: default
```

Cloudflare users set it to **DNS only**. Do not add an AAAA record. Verify from the VPS, because DNS on the person's computer can lag or be filtered:

```bash
getent ahostsv4 dm.example.com
```

The answer must contain the VPS IP. Propagation usually takes 5–30 minutes. Do not start the installation before that.

## Phase 3 — install

**Terminal mode.** Start the installer detached and write its output to a root-only log, so the admin password never enters your conversation:

```bash
ssh -n -i ~/.ssh/inst_dm_ed25519 -o IdentitiesOnly=yes root@203.0.113.10 'set -e
test ! -e /opt/inst_dm/.env
apt-get update -qq && apt-get install -y -qq git >/dev/null
rm -rf /tmp/inst_dm && git clone -q --depth 1 --branch v0.1.2 https://github.com/musa1756/inst_dm.git /tmp/inst_dm
cd /tmp/inst_dm && umask 077
(nohup bash scripts/install-vps.sh dm.example.com 203.0.113.10 > /root/inst_dm-install.log 2>&1 < /dev/null; echo "EXIT=$?" >> /root/inst_dm-install.log) > /dev/null 2>&1 &
echo started'
```

Check progress every 30–60 seconds. Never print the password line:

```bash
ssh -n -i ~/.ssh/inst_dm_ed25519 -o IdentitiesOnly=yes root@203.0.113.10 'grep -v "Admin password" /root/inst_dm-install.log | tail -5'
```

It takes 5–15 minutes, longer on 1 vCPU. The last line `EXIT=0` means success. Then the person reads the password **in their own terminal app, not through you**: commands you run, and `!` commands typed into your chat, become part of the conversation.

```bash
ssh -i ~/.ssh/inst_dm_ed25519 root@203.0.113.10 "grep 'Admin password' /root/inst_dm-install.log"
```

When they confirm the password is saved in a password manager, delete the log: `rm /root/inst_dm-install.log`.

**Chat mode.** The person runs this in the web console and saves the `Admin password` line themselves. They never send it to you:

```bash
apt update && apt install -y git
git clone --depth 1 --branch v0.1.2 https://github.com/musa1756/inst_dm.git /tmp/inst_dm
cd /tmp/inst_dm
bash scripts/install-vps.sh dm.example.com 203.0.113.10
```

Replace `dm.example.com` and `203.0.113.10` with their domain and IP. The installer refuses an existing installation; checks Ubuntu, 1 vCPU, 2 GB RAM, 22 GB free disk and that the A record points to this IP; adds a 2 GB swap file on small servers; installs Docker; generates independent secrets; starts PostgreSQL, the app and Caddy with HTTPS; enables daily backups and Ubuntu security updates.

If it fails, read the end of the log and explain the cause. A retry is safe only while `/opt/inst_dm/.env` does not exist.

## Phase 4 — verify the server

On the VPS:

```bash
cd /opt/inst_dm
docker compose ps
docker compose exec -T app node -e 'fetch("http://127.0.0.1:3000/ready").then(async r => { console.log(await r.text()); process.exit(r.ok ? 0 : 1) })'
systemctl is-active inst_dm-backup.timer
grep -E '^(APP_DOMAIN|PUBLIC_BASE_URL)=' .env
```

Expected: `db`, `app` and `caddy` are up, `{"ok":true,"database":true,"worker":true}`, `active`, and both `.env` lines contain their domain. Then check `https://dm.example.com/ready` from outside.

If HTTPS fails with a TLS "internal error", look at `docker compose logs --tail=50 caddy`. Version 0.1.1 wrote `dm.example.com` into `.env`: fix those two lines to the real domain, then run `docker compose up -d` and `docker compose restart caddy`.

Now the person opens `https://their-domain`, logs in with the admin password and opens **Подключение / Connection**. That screen shows every URL Meta needs, with copy buttons. Always take values from there; never type them from memory.

## Phase 5 — Meta and Instagram

The person clicks; you guide. Labels below are from the Russian Meta interface with English in brackets. Meta renames things occasionally: match by meaning and ask for a screenshot when unsure.

1. **Account type.** In Instagram: Settings → **Тип аккаунта и инструменты** (Account type and tools). It must be **Бизнес** (Business) or **Автор** (Creator).
2. **New Meta app.** https://developers.facebook.com/apps → **Создать приложение** (Create app) → name, for example `Shop DM` → use case **Управление сообщениями и контентом в Instagram** (Manage messaging & content on Instagram) → business portfolio: **Пока не подключать** (don't connect yet) → **Создать приложение**. Use a new app for every installation: an app has only one webhook URL, so an app from another installation cannot be reused.
3. **Настройки приложения → Основное** (App settings → Basic):
   - **Домены приложений** (App domains): their domain;
   - **URL Политики конфиденциальности** (Privacy policy URL): value `Политика` / `Privacy` from Inst DM;
   - **URL-адрес Пользовательского соглашения** (Terms of service URL): the same privacy URL;
   - **Удаление данных пользователей** (User data deletion): choose **URL обратного вызова для удаления данных** (Data deletion callback URL) and paste `Удаление данных` / `Data deletion`;
   - **Категория** (Category): **Бизнес и страницы** (Business and pages);
   - **Сохранить изменения** (Save changes).

   The App ID and secret on this page belong to the Facebook app. **They do not go into Inst DM.**
4. **Сценарии использования** (Use cases) → Instagram → **Настроить** (Customize) → **Настройка API со входом через Instagram** (API setup with Instagram login):
   1. Add the permissions `instagram_business_basic`, `instagram_business_manage_comments` and `instagram_business_manage_messages`.
   2. **Роли в приложении → Роли → Добавить людей → Тестировщик Instagram** (App roles → Add people → Instagram Tester) → their Instagram username. On the phone, in that Instagram account: Settings → **Приложения и сайты** (Apps and websites) → **Приглашения тестировщика** (Tester invites) → **Принять** (Accept). The account then appears in block 2 on the API setup page.
   3. Block **2. Сгенерируйте маркеры доступа** (Generate access tokens): press nothing. Do not press **Сгенерировать маркер** (Generate token) and do not flip the webhook switch there. Inst DM gets its own token through OAuth and subscribes automatically.
   4. Block **3. Настройте Webhooks** (Configure webhooks): **URL обратного вызова** (Callback URL) = `Webhook`; **Подтверждение маркера** (Verify token) = `Маркер Webhook` / `Webhook verify token` (hidden on screen, use its copy button); leave the client certificate switch off; **Подтвердить и сохранить** (Verify and save). In the list of fields that appears, keep only `comments`, `messages` and `messaging_postbacks` on and turn everything else off (`live_comments`, `message_edit`, `message_reactions`, `messaging_referral`, `messaging_seen`…): Inst DM does not handle them and reports them as unrecognized webhooks. If verification fails: HTTPS must open, copy both values again without spaces, and never use the OAuth callback here.
   5. Block **4. Настройте вход в бизнес-аккаунт Instagram** (Set up Instagram business login) → **Настроить**: OAuth redirect URL = `OAuth callback`; deauthorize callback URL = `Деавторизация` / `Deauthorize`; data deletion request URL = `Удаление данных` / `Data deletion` → **Сохранить** (Save).
   6. At the top of this page, copy **ID приложения Instagram** (Instagram app ID) and **Секрет приложения Instagram** (Instagram app secret, button **Показать** / Show). These are different from the values in step 3.
5. **Connect in Inst DM → Подключение** (Connection): App ID = the Instagram app ID. In App Secret, **clear the field first**: browsers often autofill it with the saved admin password (the field turns yellow). Then paste the Instagram app secret. Leave Graph API at its default → **Сохранить и подключить** (Save and connect). On the Instagram page the person logs in to the business account and presses **Разрешить** (Allow).

   Expected in **Готовность** (Readiness): Instagram token, webhook subscription and queue worker are all "Готово" (Ready). **Последний Webhook** (Last webhook) turns green after the first real event.
6. **Publish.** Meta states that webhooks are delivered only to an app with status **Опубликовано** (Live). Left menu → **Публикация** (Publish) → publish, filling in whatever Meta asks for (category, icon, privacy URL). If Meta demands App Review, stop and explain what it asks for; do not invent a submission.

## Phase 6 — first rule and real test

In Inst DM: **Автоматизации → Создать правило** (Automations → New rule):

- trigger **Комментарий** (Comment); publication: a specific Reel or Post; keyword, for example `тест`;
- Direct message text; optionally a button with an HTTPS link, for example `https://t.me/<channel>` for a Telegram channel. Button text should stay within 20 characters. Button clicks are counted; links written in the text are clickable but not counted;
- save the rule as active.

From the **second** Instagram account, post a **new** comment with the keyword under that publication. A Direct message should arrive within seconds and appear in **Журнал** (Activity). An already processed comment never triggers the same rule again; this is deliberate duplicate protection, so always test with a new comment.

If nothing arrives, check in order: the app is published; the tester invite is accepted; the rule is active and matches the publication and word; **Подключение → Проверить** (Connection → Check); then `docker compose logs --tail=150 app` (remove tokens and personal data before showing anyone).

## Phase 7 — handoff

Tell the person:

- the admin password lives only in their password manager. To change it later, they run this in their own terminal (not in your chat):

  ```bash
  ssh -i ~/.ssh/inst_dm_ed25519 root@203.0.113.10 'cd /opt/inst_dm && P=$(openssl rand -base64 18 | tr "+/" "-_" | tr -d "=") && sed -i "s#^ADMIN_PASSWORD=.*#ADMIN_PASSWORD=$P#" .env && docker compose up -d --force-recreate app >/dev/null 2>&1 && echo "New password: $P"'
  ```

- key-only SSH is recommended. Apply `deploy/ssh/99-inst_dm-hardening.conf` only with their consent, after a second key session has succeeded: copy it to `/etc/ssh/sshd_config.d/`, run `sshd -t`, reload SSH, verify a new session;
- backups (`/var/backups/inst_dm`) contain secrets and stay on the same VPS. They protect against a bad update, not against losing the server, so a fresh archive should be downloaded now and then;
- incoming comment and message text is not stored; technical history is kept for 30 days;
- the installation never updates itself. Updates are explicit, by release tag: `sudo /opt/inst_dm/scripts/update-vps.sh vX.Y.Z` (backup, build, readiness check, automatic rollback);
- one installation serves one Instagram account.

## Troubleshooting

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| Installer: `нужно минимум …` | the server is too small | a bigger tariff; do not edit the check |
| Installer: A record points elsewhere | DNS not propagated or wrong IP | fix the record, wait, retry |
| HTTPS: TLS internal error | Caddy has no certificate yet, or `APP_DOMAIN` in `.env` is wrong | wait 2 minutes; check `.env` and the Caddy logs (Phase 4) |
| Meta cannot verify the webhook | HTTPS down, token copied with spaces, OAuth callback used | recopy the values from the Connection screen |
| OAuth error after "Save and connect" | Facebook app ID used instead of the Instagram app ID, or an autofilled secret | Phase 5, steps 4.6 and 5 |
| Token and subscription are fine, no DM arrives | app not published, tester invite pending, old comment reused | Phase 5, steps 6 and 4.2; a new comment |
| "Last webhook" shows unrecognized events | extra webhook fields are enabled | turn off everything except the three fields |

Sanitize everything before it leaves the server: no tokens, App Secret, passwords, `.env`, backups or personal message content.
