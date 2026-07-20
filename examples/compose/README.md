# KoutenDB Docker Compose Examples

These Compose files are small topology demos for KoutenDB. They are meant to
show how the universe / galaxy model maps to running processes.

## Single Galaxy

```sh
docker compose -f examples/compose/single-galaxy.compose.yml up -d --build
docker compose -f examples/compose/single-galaxy.compose.yml exec -T kouten-main \
  koutencli health --peers=127.0.0.1:7301 \
  --user=app --password=change-me --secret-key=change-me-too
docker compose -f examples/compose/single-galaxy.compose.yml down
```

Use this when you want one KoutenDB galaxy with one data directory and one
credential profile.

## Three-Node Galaxy

```sh
docker compose -f examples/compose/three-node-galaxy.compose.yml up -d --build
docker compose -f examples/compose/three-node-galaxy.compose.yml exec -T kouten-node0 \
  koutencli health --peers=kouten-node0:7301,kouten-node1:7301,kouten-node2:7301 \
  --user=train --password=change-me --secret-key=change-me-too
docker compose -f examples/compose/three-node-galaxy.compose.yml down
```

Use this when you want one galaxy spread across three KoutenDB nodes.

## Local / Remote Universe Shape

```sh
docker compose -f examples/compose/local-remote-universe.compose.yml up -d --build
docker compose -f examples/compose/local-remote-universe.compose.yml exec -T kouten-training-local \
  koutencli health --peers=127.0.0.1:7301 \
  --user=train --password=change-me --secret-key=change-me-too
docker compose -f examples/compose/local-remote-universe.compose.yml exec -T kouten-prompt-cache-local \
  koutencli health --peers=127.0.0.1:7301 \
  --user=cache --password=change-me --secret-key=change-me-too
docker compose -f examples/compose/local-remote-universe.compose.yml down
```

Use this as a concept demo for multiple galaxies across local and remote-style
placements. It runs everything locally; real production remote universes should
be placed on independent infrastructure.

## Credentials

Every example uses `username + password + secret-key` style authentication.
Override the defaults with environment variables before running Compose:

```sh
export KOUTEN_APP_PASSWORD='replace-me'
export KOUTEN_APP_SECRET_KEY='replace-me-too'
docker compose -f examples/compose/single-galaxy.compose.yml up --build
```

Do not use the default values in production.
