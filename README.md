# Daily Assistant

## Run with Docker

First build and start the Rails app:

```sh
docker compose up --build
```

After that, day-to-day development usually only needs:

```sh
docker compose up
```

The Rails container listens at http://localhost:3000. `docker compose up` also
starts Redis, Sidekiq, and the Telegram bot so background jobs and bot polling
can run while the app is open.

The project directory is bind-mounted into the container at `/rails`, so changes
to controllers, models, views, routes, locales, CSS, and migrations are visible
inside Docker immediately. You only need to rebuild the image when the dev image
itself changes, such as `Dockerfile.dev`, Ruby version, or system packages.

The development SQLite database is stored in the `rails_storage` Docker volume at
`/rails/storage/development.sqlite3`, so it stays inside Docker and survives
container rebuilds.

Installed gems are stored in the `bundle` Docker volume at `/usr/local/bundle`.
If `Gemfile` changes, the dev entrypoint runs `bundle install` automatically on
startup and the installed gems stay cached between containers.

Active Job uses Sidekiq in development, with Redis at `redis://redis:6379/0`
inside Docker. The `redis` service runs `redis-server --appendonly yes`, and
Sidekiq reads queues from `config/sidekiq.yml`.

The Telegram bot runs as the `telegram_bot` service and reads
`TELEGRAM_BOT_TOKEN` from `.env`.

Useful commands:

```sh
bin/drails console
bin/drails db:prepare
bin/drails db:migrate
bin/drails generate model Task title:string
docker compose logs -f sidekiq
docker compose logs -f telegram_bot
docker compose run --rm web ./bin/rails console
docker compose run --rm web ./bin/rails db:prepare
docker compose run --rm web ./bin/rails db:migrate
docker compose down
docker compose down --volumes
```

`bin/drails` runs Rails commands inside Docker instead of using your local Ruby.
When the `web` container is already running it uses `docker compose exec`; if not,
it falls back to a one-off `docker compose run --rm web` container.

Use `docker compose down --volumes` only when you want to delete the Docker-held
SQLite database and gem cache too.
