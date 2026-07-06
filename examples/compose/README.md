# RocheDB Docker Compose Examples

These Compose files are small topology demos for RocheDB. They are meant to
show how the universe / galaxy model maps to running processes.

## Single Galaxy

```sh
docker compose -f examples/compose/single-galaxy.compose.yml up --build
```

Use this when you want one RocheDB galaxy with one data directory and one
credential profile.

## Three-Node Galaxy

```sh
docker compose -f examples/compose/three-node-galaxy.compose.yml up --build
```

Use this when you want one galaxy spread across three RocheDB nodes.

## Local / Remote Universe Shape

```sh
docker compose -f examples/compose/local-remote-universe.compose.yml up --build
```

Use this as a concept demo for multiple galaxies across local and remote-style
placements. It runs everything locally; real production remote universes should
be placed on independent infrastructure.

## Credentials

Every example uses `username + password + secret-key` style authentication.
Override the defaults with environment variables before running Compose:

```sh
export ROCHE_APP_PASSWORD='replace-me'
export ROCHE_APP_SECRET_KEY='replace-me-too'
docker compose -f examples/compose/single-galaxy.compose.yml up --build
```

Do not use the default values in production.
