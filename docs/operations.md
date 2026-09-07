# Operations

Runtime configuration for a production Core API process, plus the build and boot commands that have been run against this tree. A local asset build, a container build, a container boot, and a rendered message each prove only themselves. **Actual mail delivery is unverified.**

The Dockerfile comment that passes `RAILS_MASTER_KEY` is leftover. This app boots on `SECRET_KEY_BASE` alone; `config/master.key` is not in the repository and encrypted credentials are not read.

## Runtime configuration by capability

Classify by what stops working when the settings are absent — not by whether an initializer reads them, and not by `ENV[]` vs `ENV.fetch`. Required/optional follows this table, not "needed to boot".

| Capability | Settings | If absent |
| --- | --- | --- |
| **Boot** | `SECRET_KEY_BASE` | Process will not boot. |
| **SQLite files** | `SQLITE_DATABASE_PATH`, `SQLITE_CACHE_DATABASE_PATH`, `SQLITE_QUEUE_DATABASE_PATH`, `SQLITE_CABLE_DATABASE_PATH` | The env vars have `storage/production*.sqlite3` defaults, so leaving them unset does not prevent boot. Production still declares four databases; those four files must be on a writable disk (the image's `/rails/storage` volume). What actually lives in each file is not the name — see the inventory. |
| **Password-recovery mail** | `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAILER_HOST`, `MAILER_FROM` | The API still returns 202. Nothing is delivered until SMTP is a real MTA. Reset links use `MAILER_HOST`, not `APP_URL`. |
| **Google connect (OmniAuth)** | `GOOGLE_CLIENT_ID` **and** `GOOGLE_CLIENT_SECRET` (paired — one alone does not mount OmniAuth) | Connect initiation is unavailable. |
| **Google connect (CORS and callback)** | `GOOGLE_CONNECT_ORIGINS`, `APP_URL` | Absent `GOOGLE_CONNECT_ORIGINS`, same-origin and missing-`Origin` requests still work; any other origin is 403 `origin_not_allowed`. `APP_URL` pins the OmniAuth callback and must be the same host that set the session cookie. |
| **Telegram delivery and polling** | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME` | The API boots without them. Every Telegram send/poll path raises `KeyError` on `TELEGRAM_BOT_TOKEN`. Without `TELEGRAM_BOT_USERNAME`, `POST /api/v1/integrations/telegram/connect` is 503 `integration_unavailable`. |
| **AI** | `OPEN_ROUTER_KEY`, `OPEN_ROUTER_MODEL` | Boot succeeds. The first OpenRouter call raises `NotConfigured` if the key is blank. The model has a default. |
| **Background jobs** | `SOLID_QUEUE_IN_PUMA`, `JOB_CONCURRENCY` | Reminders and daily digests still need a worker. Password recovery does not (`deliver_now` only). |
| **Optional tuning** | `WEB_CONCURRENCY`, `RAILS_MAX_THREADS`, `RAILS_LOG_LEVEL`, `PORT`, `HTTP_PORT`, `TARGET_PORT`, `PIDFILE`, `REDIS_URL` | Defaults apply. `PORT` is inert under the shipped `CMD` — see inventory. `REDIS_URL` is unused in practice — see Action Cable below. |

## Settings inventory

Placeholders only.

| Setting | Default if unset | Consumer behaviour |
| --- | --- | --- |
| `SECRET_KEY_BASE` | none | Required to boot production. |
| `SQLITE_DATABASE_PATH` | `storage/production.sqlite3` | Primary database. Solid Queue currently lives here: there is no `config.solid_queue.connects_to`, so after `db:prepare` the `solid_queue_*` tables are in this file. Back up this file if you need the reminder and digest queue. |
| `SQLITE_CACHE_DATABASE_PATH` | `storage/production_cache.sqlite3` | Declared in production `database.yml`. Unused as a cache: `production.rb` leaves `cache_store` commented out, so Rails 8.1 uses FileStore at `tmp/cache`. After `db:prepare` the file exists with no application tables. |
| `SQLITE_QUEUE_DATABASE_PATH` | `storage/production_queue.sqlite3` | Declared in production `database.yml`. Unused as the queue: Solid Queue uses the primary database (above). After `db:prepare` the file exists with no application tables. |
| `SQLITE_CABLE_DATABASE_PATH` | `storage/production_cable.sqlite3` | Declared; Cable still cannot run (below). After `db:prepare` the file exists with no application tables. |
| `MAILER_HOST` | `example.com` | Host in password-reset URLs (`https://<MAILER_HOST>/auth/password/edit?...`). Not `APP_URL`. |
| `MAILER_FROM` | ActionMailer `from`: `no-reply@example.com`; Devise sender: `no-reply@daily-assistant.local` | Production `From` comes from ActionMailer `default_options[:from]`. Devise `mailer_sender` still supplies `Reply-To` when this variable is unset, so the two headers differ. Setting `MAILER_FROM` makes **both** headers that value. Development and test set no ActionMailer `default_options`, so `mailer_sender` supplies **both** `From` and `Reply-To` there — do not treat `config/initializers/devise.rb` as dead. |
| `SMTP_ADDRESS` | `localhost` | SMTP host. The image contains no MTA. |
| `SMTP_PORT` | `587` | SMTP port. |
| `SMTP_USERNAME` | unset | Optional SMTP auth. |
| `SMTP_PASSWORD` | unset | Optional SMTP auth. |
| `APP_URL` | `http://localhost:3000` | OmniAuth Google callback and OpenRouter app URL. Does **not** set reset-link hosts. |
| `GOOGLE_CLIENT_ID` | unset | Must be paired with the secret or OmniAuth is not mounted. |
| `GOOGLE_CLIENT_SECRET` | unset | Must be paired with the id. |
| `GOOGLE_CONNECT_ORIGINS` | empty | Comma-separated exact HTTPS origins allowed for Google connect CORS. Same-origin and a missing `Origin` are allowed without it. |
| `TELEGRAM_BOT_TOKEN` | none | No initializer. Defaultless `ENV.fetch` at `ProcessTelegramUpdateJob`, `TelegramBot::Runner`, `DailyDigests::Deliver`, and `Reminders::Deliver`. Raises when those paths run. |
| `TELEGRAM_BOT_USERNAME` | unset | Telegram connect deep link. Blank → 503 `integration_unavailable`. |
| `OPEN_ROUTER_KEY` | unset | Read at boot without raising; the client refuses to call without it. |
| `OPEN_ROUTER_MODEL` | `google/gemma-4-26b-a4b-it:free` | Model id for AI calls. |
| `REDIS_URL` | `redis://localhost:6379/1` | `config/cable.yml` production adapter is `redis`. There is no `redis` gem. Setting this does not make Cable work. |
| `SOLID_QUEUE_IN_PUMA` | unset disables | **Presence test, not a boolean.** `config/puma.rb` is `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]`, so `SOLID_QUEUE_IN_PUMA=false` still enables the plugin. Leave it unset to disable. Supported alternative: `bin/jobs`. |
| `JOB_CONCURRENCY` | `1` | Solid Queue worker processes. |
| `WEB_CONCURRENCY` | Puma default (1 worker) | Puma workers. |
| `RAILS_MAX_THREADS` | `3` (Puma); database.yml fetch default `5` | Puma thread pool. |
| `RAILS_LOG_LEVEL` | `info` | Production log level. |
| `HTTP_PORT` | `80` | Thruster listen port (`EXPOSE 80`). Health-check here, inside the container. |
| `TARGET_PORT` | `3000` | Port Thruster proxies to. Thruster sets the child process's `PORT` to this value, so Puma binds here. |
| `PORT` | Puma `3000` | **Inert under the shipped `CMD`** (`./bin/thrust ./bin/rails server`). Setting `PORT` on the container does not move Puma; Thruster overwrites the child's `PORT` from `TARGET_PORT`. To change Puma's bind, set `TARGET_PORT`. To change the public listen port, set `HTTP_PORT`. Do not point health checks at `PORT`. |
| `PIDFILE` | unset | Written only when set. |

## Password-recovery mail

Configuration already lives in `config/environments/production.rb`. Do not change sender behaviour.

Rendered `Devise::Mailer.reset_password_instructions` in production, no SMTP send (`perform_deliveries = false`):

| Case | `From` | `Reply-To` | Recovery URL |
| --- | --- | --- | --- |
| `MAILER_FROM` and `MAILER_HOST` unset | `no-reply@example.com` | `no-reply@daily-assistant.local` | `https://example.com/auth/password/edit?reset_password_token=…` |
| `MAILER_FROM=ops@slice9.example` `MAILER_HOST=core.slice9.example` | `ops@slice9.example` | `ops@slice9.example` | `https://core.slice9.example/auth/password/edit?reset_password_token=…` |

Delivery method is `:smtp` in both cases. **Rendering is not delivery.**

Operational facts:

- `POST /api/v1/auth/password` returns **202** whether or not mail was sent. The send is wrapped in `rescue StandardError`, which logs only the exception class. That is intended (account-existence must not leak) and must not be "fixed".
- **202 acknowledges the reset request; it does not confirm delivery.**
- **SMTP must be configured.** `SMTP_ADDRESS` defaults to `localhost` and the image contains no MTA.
- Delivery failures are logged without disclosing whether an account exists.
- The reset path is synchronous (`deliver_now`). Password recovery needs no worker. Reminders and daily digests still do.

## Known limitation: Action Cable

Production Cable is `adapter: redis` with no `redis` gem. `/up` does not touch Cable, so a 200 does not mean Cable works. Nothing in this application currently uses it. Do not add Redis as part of a routine deploy.

## Verified build and run

Asset pipeline is Propshaft + `tailwindcss-rails`. There is no Node/Yarn toolchain.

Native asset build (isolated copy; does not prove the image):

```
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile
```

Image build (isolated copy of this tree; `SECRET_KEY_BASE_DUMMY=1` is build-time precompile only and is not a runtime credential):

```
docker build -t daily_assistant .
```

The image `ENTRYPOINT` is `/rails/bin/docker-entrypoint` (runs `db:prepare` when the command ends in `./bin/rails server`). `CMD` is `./bin/thrust ./bin/rails server`. Thruster listens on **port 80** (`HTTP_PORT` default; `EXPOSE 80`). Puma sits behind it on `TARGET_PORT` (default 3000). Health-check **inside** the container:

```
curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:80/up
```

Expect **HTTP 200**. `force_ssl` plus `assume_ssl` must not 301 `/up`. Thruster can return **502** for a moment while Puma is still binding 3000; that is startup, not a passing health check.

Example run — no host ports required for an in-container check. Pass a real `SECRET_KEY_BASE` at **run** time; do not bake it into the image. Named volume for the four SQLite files:

```
docker run -d --name daily_assistant \
  --mount type=volume,source=daily_assistant_storage,target=/rails/storage \
  -e SECRET_KEY_BASE \
  -e SQLITE_DATABASE_PATH=/rails/storage/production.sqlite3 \
  -e SQLITE_CACHE_DATABASE_PATH=/rails/storage/production_cache.sqlite3 \
  -e SQLITE_QUEUE_DATABASE_PATH=/rails/storage/production_queue.sqlite3 \
  -e SQLITE_CABLE_DATABASE_PATH=/rails/storage/production_cable.sqlite3 \
  daily_assistant
```

Do not override `CMD`. That would skip Thruster, which is what production runs.

Measured on `linux/arm64` (Docker Desktop). Rebuild on the deploy architecture.

Workers, if not using `SOLID_QUEUE_IN_PUMA`: `bin/jobs`.

## CI as shipped

Removing `yarn audit` does not make `bin/ci` green. Direct exits on this tree: `bin/rubocop` 1 (204 files, 65 offenses, 34 autocorrectable); `bin/brakeman --no-pager` 5 (`8.0.5 is not the latest version 8.0.6` — `--ensure-latest` stays); `bundle exec brakeman --no-pager --force` 3 (1 Medium at `admin/users_controller.rb:51`, controllers 14); `bin/bundler-audit` 1 (`sqlite3 2.9.5` GHSA-mwm8-39rw-8826; this run also reports `activestorage 8.1.3` and `json 2.21.1`). Version bumps are out of scope. Hosted `scan_ruby` and `lint` are red for those pre-existing reasons. Hosted `test` (`bundle exec rspec`) passes.
