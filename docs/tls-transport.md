# TLS Transport

OrbeliasDB supports standard TLS for `orbeliasd` TCP connections when the server and
client are built with Nim's SSL support:

```sh
nim c -d:ssl -d:release -o:src/orbeliasd src/orbeliasd.nim
nim c -d:ssl -d:release -o:src/orbeliascli src/orbeliascli.nim
```

TLS is a transport layer. It is separate from OrbeliasDB's username/password
authentication, secret-key challenge response, and libsodium-backed secure frame
mode. They can be combined:

```text
TCP -> TLS -> OrbeliasDB wire protocol -> AUTH / AUTHCHAL -> optional secure frames
```

For public or VPC deployments, prefer TLS plus username/password plus
`--secret-key`.

## Server

Start `orbeliasd` with a certificate and private key:

```sh
src/orbeliasd \
  --id=0 \
  --peers=127.0.0.1:7301 \
  --data=/var/lib/orbeliasdb \
  --user=alice \
  --password-file=/run/secrets/orbelias_password \
  --secret-key-file=/run/secrets/orbelias_secret_key \
  --tls-cert=/etc/orbeliasdb/server.crt \
  --tls-key=/etc/orbeliasdb/server.key \
  --tls-ca=/etc/orbeliasdb/ca.crt
```

`--tls-ca`, `--tls-server-name`, and `--tls-insecure-skip-verify` are used by
the server's own peer client for cluster handoff and maintenance requests. In a
single-node local smoke test they are less important; in a TLS cluster they
should match the peer certificate policy.

## CLI Client

Use `--tls` to connect to a TLS-enabled `orbeliasd`:

```sh
src/orbeliascli health \
  --peers=127.0.0.1:7301 \
  --user=alice \
  --password-file=/run/secrets/orbelias_password \
  --secret-key-file=/run/secrets/orbelias_secret_key \
  --tls \
  --tls-ca=/etc/orbeliasdb/ca.crt
```

For local self-signed experiments only:

```sh
src/orbeliascli health \
  --peers=127.0.0.1:7301 \
  --user=alice \
  --password-file=/run/secrets/orbelias_password \
  --secret-key-file=/run/secrets/orbelias_secret_key \
  --tls \
  --tls-insecure-skip-verify
```

Do not use `--tls-insecure-skip-verify` for production deployments.
For local smoke tests, direct `--password` / `--secret-key` values are accepted.
For shared systems, prefer `--password-file`, `--secret-key-file`, or the
`ORBELIAS_PASSWORD` / `ORBELIAS_SECRET_KEY` environment variables so secrets do not
appear in shell history or process listings.

## C ABI

The C ABI exposes `orbelias_connect_auth_tls` for native drivers and FFI wrappers.
The existing `orbelias_connect` and `orbelias_connect_auth` entry points remain
available for non-TLS and backward-compatible use.

## Smoke Test

The TLS smoke test builds TLS-enabled binaries, generates a short-lived
self-signed certificate, starts `orbeliasd`, verifies authenticated TLS health,
writes and reads JSON over TLS, and confirms that a plain TCP client cannot talk
to the TLS listener:

```sh
scripts/cluster_tls_smoke.sh
```

This test opens a local TCP listener. In restricted sandboxes it may need to run
outside the sandbox.
