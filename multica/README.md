# Multica — настройка и подключение

[Multica](https://github.com/multica-ai/multica) — open-source рабочее пространство, где люди и AI-агенты
(Claude Code, Codex, Cursor и др.) работают как одна команда: задачи назначаются агентам через issues,
агенты сами берут их в работу, отчитываются о прогрессе и отдают результат на ревью.

| Параметр        | Значение                                   |
|-----------------|--------------------------------------------|
| URL             | https://multica.borodoy.com                |
| Сервер          | `109.172.9.44` (`ssh borodoy@109.172.9.44`) |
| Каталог проекта | `/home/borodoy/n8n-install`                |
| Профиль Compose | `multica`                                  |
| Дата установки  | 2026-10-19                                 |

---

## Архитектура

```
Браузер / CLI / daemon
        │ HTTPS (443)
        ▼
     caddy  ── multica.borodoy.com
        ├── /ws, /ws/*  ──────────────► multica-backend:8080   (WebSocket, flush_interval -1)
        └── всё остальное ────────────► multica-frontend:3000  (Next.js)
                                              │ rewrites /api, /auth, /uploads, /v1
                                              ▼
                                        multica-backend:8080 (Go API)
                                              ├── postgres:5432  → база `multica`
                                              └── redis:6379     → логическая БД 5
```

| Контейнер          | Образ                                       | Назначение |
|--------------------|---------------------------------------------|------------|
| `multica-db-init`  | `postgres:17`                               | Одноразовый: создаёт базу `multica` в общем Postgres, если её нет |
| `multica-backend`  | `ghcr.io/multica-ai/multica-backend:latest` | REST API + WebSocket, миграции БД при старте |
| `multica-frontend` | `ghcr.io/multica-ai/multica-web:latest`     | Веб-интерфейс |

- **База данных:** отдельная БД `multica` в общем контейнере `postgres` (пользователь `postgres`).
  Отдельная база выбрана, чтобы таблицы Multica не пересекались с таблицами n8n.
- **Redis:** общий Valkey (`redis`), логическая БД `5` (`redis://redis:6379/5`) — rate limiting входа и realtime relay.
- **Файлы/вложения:** Docker volume `localai_multica_uploads` → `/app/data/uploads`.
- **Схема «один origin»:** фронтенд, `/api` и `/ws` обслуживаются с одного домена, поэтому `COOKIE_DOMAIN`
  не нужен, а `NEXT_PUBLIC_API_URL` / `NEXT_PUBLIC_WS_URL` оставлены пустыми.
- **Порты наружу не публикуются** — доступ только через Caddy.
- **Caddy basic auth не используется** — у Multica своя авторизация, а basic auth сломал бы подключение
  CLI/daemon (они ходят с `Authorization: Bearer`).

---

## Вход в веб-интерфейс

Вход — по коду подтверждения, отправляемому на email. **SMTP не настроен**, поэтому код печатается в логи backend:

1. Откройте https://multica.borodoy.com и введите свой email.
2. Получите код:
   ```bash
   ssh borodoy@109.172.9.44 "docker logs multica-backend 2>&1 | grep 'Verification code' | tail -1"
   ```
3. Введите код. Аккаунт `denisborodoy@gmail.com` создан 2026-10-19, workspace создан.

---

## Подключение AI-агентов (daemon на машине разработчика)

Агенты запускаются **не на сервере**, а локально на машине разработчика через CLI `multica` и daemon.

1. Установить CLI:
   ```bash
   # Linux / macOS
   curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash
   ```
   Для Windows — PowerShell-установщик из репозитория (см. README проекта).
2. Подключить к нашему серверу:
   ```bash
   multica setup self-host --server-url https://multica.borodoy.com --app-url https://multica.borodoy.com
   ```
   Альтернатива — вручную:
   ```bash
   multica config set server_url https://multica.borodoy.com
   ```
3. Заранее авторизовать нужные CLI агентов (Claude Code, Codex, Cursor Agent и т.д.) — Multica использует их как есть.

Daemon подключается к `wss://multica.borodoy.com/ws` и аутентифицируется персональным токеном `mul_...`.

---

## Переменные окружения (`.env` на сервере)

Секреты хранятся **только** в `/home/borodoy/n8n-install/.env` на сервере — сюда не копируются.

| Переменная                           | Текущее значение          | Описание |
|--------------------------------------|---------------------------|----------|
| `MULTICA_HOSTNAME`                   | `multica.borodoy.com`     | Домен (Caddy + все публичные URL backend) |
| `MULTICA_JWT_SECRET`                 | *сгенерирован (hex 64)*   | Ключ подписи JWT. **Не менять** — разлогинит всех и сломает подписанные ссылки |
| `MULTICA_IMAGE_TAG`                  | `latest`                  | Тег образов backend/web |
| `MULTICA_SMTP_HOST`                  | —                         | SMTP-сервер для кодов входа |
| `MULTICA_SMTP_PORT`                  | `587`                     | |
| `MULTICA_SMTP_USERNAME`              | —                         | |
| `MULTICA_SMTP_PASSWORD`              | —                         | |
| `MULTICA_SMTP_FROM_EMAIL`            | —                         | Отправитель |
| `MULTICA_SMTP_TLS`                   | —                         | пусто/`starttls` (по умолчанию) или `implicit` (порт 465) |
| `MULTICA_GOOGLE_CLIENT_ID`           | —                         | Вход через Google (redirect: `https://multica.borodoy.com/auth/callback`) |
| `MULTICA_GOOGLE_CLIENT_SECRET`       | —                         | |
| `MULTICA_ALLOW_SIGNUP`               | `false`                   | `false` — регистрация только по приглашению/allowlist |
| `MULTICA_ALLOWED_EMAILS`             | `denisborodoy@gmail.com`  | Разрешённые email (через запятую) |
| `MULTICA_ALLOWED_EMAIL_DOMAINS`      | —                         | Разрешённые домены (через запятую) |
| `MULTICA_DISABLE_WORKSPACE_CREATION` | —                         | `true` — запрет создания новых workspace |
| `MULTICA_DO_NOT_TRACK`               | —                         | `1` — отключить анонимную ежедневную телеметрию |

Также `multica-backend,multica-frontend` добавлены в `GOST_NO_PROXY`, а `multica` — в `COMPOSE_PROFILES`.

Значения, зашитые в `docker-compose.yml`: `APP_ENV=production`, `FRONTEND_ORIGIN` / `CORS_ALLOWED_ORIGINS` /
`MULTICA_APP_URL` / `MULTICA_PUBLIC_URL` = `https://${MULTICA_HOSTNAME}`, `MULTICA_TRUSTED_PROXIES=172.16.0.0/12`,
`RATE_LIMIT_TRUSTED_PROXIES=172.16.0.0/12` (rate limit входа считается по реальному IP клиента, а не по IP Caddy),
backend наследует настройки прокси gost (`x-proxy-env`).

После изменения `.env` пересоздать backend:
```bash
cd ~/n8n-install && docker compose -p localai up -d --no-deps multica-backend
```

---

## Безопасность

Что включено:

- **Регистрация закрыта:** `MULTICA_ALLOW_SIGNUP=false`, `MULTICA_ALLOWED_EMAILS=denisborodoy@gmail.com`.
  Чужой email получает `user registration is disabled on this self-hosted instance`, код даже не генерируется.
  Новых людей добавлять **приглашением в workspace** (приглашённый email сможет зарегистрироваться).
- **Rate limit входа** через Redis: 5 запросов кода/мин и 20 попыток ввода кода/мин на IP.
  `RATE_LIMIT_TRUSTED_PROXIES` настроен, поэтому лимит считается по реальному IP, и боты не могут заблокировать вход всем.
- **Защита от индексации** (Caddy): заголовок `X-Robots-Tag: noindex, nofollow, noarchive` на всех ответах и
  `/robots.txt` с `Disallow: /`. Это работает только для добросовестных поисковиков. Сканеры уязвимостей
  (leakix и т.п.) robots.txt игнорируют, а домен они находят по логам Certificate Transparency при выпуске сертификата.
- Сессии в HttpOnly cookie + CSRF-токен, всё по HTTPS.

Дальнейшие шаги (по желанию):

- `MULTICA_DISABLE_WORKSPACE_CREATION=true` — запрет создания новых workspace (включая владельца).
- Полностью скрыть сайт можно через **Cloudflare Tunnel + Cloudflare Access** (вход через SSO/email-OTP до попадания на сайт).
  Caddy basic auth **не подходит**: браузер шлёт `Authorization: Basic` в том числе на `/api`, а CLI/daemon
  ходят с `Authorization: Bearer`, и подключение агентов сломается.
- **Никогда** не задавать `MULTICA_DEV_VERIFICATION_CODE` — на публичном инстансе это вход для любого по известному email.

---

## Не настроено (опционально)

- **Интеграция с GitLab / Gitea / Forgejo** — backend пишет `vcs integration disabled (MULTICA_VCS_SECRET_KEY not set)`.
  Для включения добавить в compose переменную `MULTICA_VCS_SECRET_KEY` (сгенерировать `openssl rand -hex 32`).
- **GitHub App, Slack, Telegram, Lark, DingTalk, WeCom** — требуют своих `*_SECRET_KEY` / ключей App, см.
  [SELF_HOSTING_ADVANCED.md](https://github.com/multica-ai/multica/blob/main/SELF_HOSTING_ADVANCED.md).
- **Серверный LLM** (`MULTICA_LLM_API_KEY`, `MULTICA_LLM_BASE_URL`) — для генерации заголовков чатов и т.п.
- **S3 для вложений** — сейчас файлы хранятся в volume.

---

## Эксплуатация

```bash
# Статус
ssh borodoy@109.172.9.44 "docker ps --format '{{.Names}} {{.Status}}' | grep multica"

# Логи
ssh borodoy@109.172.9.44 "docker logs multica-backend --tail=100"
ssh borodoy@109.172.9.44 "docker logs multica-frontend --tail=100"

# Перезапуск
ssh borodoy@109.172.9.44 "cd n8n-install && docker compose -p localai restart multica-backend multica-frontend"

# Обновление образов
ssh borodoy@109.172.9.44 "cd n8n-install && docker compose -p localai pull multica-backend multica-frontend && docker compose -p localai up -d --no-deps multica-backend multica-frontend"

# Проверка здоровья backend (изнутри контейнера)
ssh borodoy@109.172.9.44 "docker exec multica-backend wget -qO- http://127.0.0.1:8080/readyz"

# Бэкап базы
ssh borodoy@109.172.9.44 "docker exec postgres pg_dump -U postgres -Fc multica > ~/backups/multica-\$(date +%F).dump"
```

Health-эндпоинты backend: `/health` (liveness), `/readyz` и `/healthz` (БД + миграции).
Снаружи через домен они недоступны (идут во frontend) — проверять изнутри.

### Проверка WebSocket снаружи

```bash
curl -s --http1.1 -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Origin: https://multica.borodoy.com" \
  https://multica.borodoy.com/ws
# Ожидаемо: {"error":"workspace_id or workspace_slug required"} — значит /ws доходит до backend
```

---

## Типичные проблемы

| Симптом | Причина / решение |
|---------|-------------------|
| Обновления в UI приходят только после F5 | WebSocket не проходит: проверить блок `/ws` в Caddyfile и `CORS_ALLOWED_ORIGINS` = `https://multica.borodoy.com` |
| `403 CSRF validation failed` при записи | Устаревшие cookie — удалить `multica_auth` / `multica_csrf` и войти заново |
| Backend не стартует, ошибка БД | `docker logs multica-db-init` — база `multica` должна быть создана (exit code 0) |
| Не приходит код на почту | SMTP не настроен — брать код из логов backend |

---

## Изменения в проекте n8n-install

| Файл | Изменение |
|------|-----------|
| `docker-compose.yml` | Сервисы `multica-db-init`, `multica-backend`, `multica-frontend`; volume `multica_uploads`; `MULTICA_HOSTNAME` в env Caddy |
| `Caddyfile` | Блок `{$MULTICA_HOSTNAME}` с маршрутом `/ws` на backend |
| `.env.example` | `MULTICA_HOSTNAME`, секция Multica, `GOST_NO_PROXY` |
| `scripts/03_generate_secrets.sh` | Генерация `MULTICA_JWT_SECRET` (`hex:64`) |
| `scripts/04_wizard.sh` | Пункт `multica` в мастере |
| `scripts/generate_welcome_page.sh` | Карточка сервиса + шаг Quick Start (подключение daemon) |
| `scripts/07_final_report.sh` | Подсказка про вход по коду |
| `scripts/update_preview.sh` | Проверка обновлений образов |
| `welcome/app.js` | `SERVICE_METADATA` для `multica` |
| `README.md`, `CHANGELOG.md` | Описание сервиса |

> **Важно:** на сервере эти изменения **не закоммичены**. `make update` делает `git reset --hard` и сотрёт их —
> перед обновлением закоммитить изменения в репозиторий.
>
> Бэкап файлов и `.env` до установки: `~/backups/pre-multica-20261019-184137/files.tar` на сервере.

---

## Ссылки

- Репозиторий: https://github.com/multica-ai/multica
- Self-hosting: https://github.com/multica-ai/multica/blob/main/SELF_HOSTING.md
- Расширенная настройка: https://github.com/multica-ai/multica/blob/main/SELF_HOSTING_ADVANCED.md
- Discord: https://discord.gg/W8gYBn226t
