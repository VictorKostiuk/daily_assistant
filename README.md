# Daily Assistant

## Run with Docker

Build and start the Rails app:

```sh
docker compose up --build
```

The container listens at http://localhost:3000. This app does not define a root
route yet, so use http://localhost:3000/up as the health check until one exists.

The development SQLite database is stored in the `rails_storage` Docker volume at
`/rails/storage/development.sqlite3`, so it stays inside Docker and survives
container rebuilds.

Useful commands:

```sh
bin/drails console
bin/drails db:prepare
bin/drails db:migrate
bin/drails generate model Task title:string
docker compose run --rm web ./bin/rails console
docker compose run --rm web ./bin/rails db:prepare
docker compose run --rm web ./bin/rails db:migrate
docker compose down
docker compose down --volumes
```

`bin/drails` is a shortcut for `docker compose run --rm web ./bin/rails`, so
Rails commands run inside Docker instead of using your local Ruby.

Use `docker compose down --volumes` only when you want to delete the Docker-held
SQLite database too.
