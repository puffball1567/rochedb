---
layout: page
title: Installation
---

# Installation

OrbeliasDB installs command-line binaries named `orbelias`, `orbeliasd`, `orbeliascli`,
`orbeliasbench`, and `orbeliassim`.

For normal use, the command should be available as `orbelias`, not as
`bin/orbelias`. The `bin/` form is only for source-tree development and smoke
tests.

## Prerequisites

- Nim `2.0.0` or newer
- `git`
- `gcc` or another C compiler supported by Nim
- `libsodium` development files for `nimsodium`

## User Install

Install OrbeliasDB from Nimble:

```sh
nimble install orbeliasdb
```

Use a source checkout when you want to run the full test suite, examples, or
driver smoke tests:

```sh
git clone https://github.com/puffball1567/orbeliasdb.git
cd orbeliasdb
nimble install -y
```

Nimble installs binaries into `~/.nimble/bin` by default. Add it to your shell
PATH if `orbelias --help` is not found:

```sh
export PATH="$HOME/.nimble/bin:$PATH"
```

For a persistent shell setup:

```sh
printf '\nexport PATH="$HOME/.nimble/bin:$PATH"\n' >> ~/.profile
```

Then verify:

```sh
orbelias --help
orbeliasd --help
```

## System Install

For server-style deployments, use `/usr/local/bin`, matching the usual source
install location for database tools such as MySQL or PostgreSQL client/server
binaries.

Build repo-local binaries:

```sh
nim c -d:release --nimcache:/tmp/nimcache_orbelias -o:bin/orbelias src/orbeliascli.nim
nim c -d:release --nimcache:/tmp/nimcache_orbeliasd -o:bin/orbeliasd src/orbeliasd.nim
```

Install them onto the system PATH:

```sh
sudo install -m 0755 bin/orbelias /usr/local/bin/orbelias
sudo install -m 0755 bin/orbeliasd /usr/local/bin/orbeliasd
```

Optional development and benchmark tools:

```sh
nim c -d:release --nimcache:/tmp/nimcache_orbeliasbench -o:bin/orbeliasbench src/orbeliasbench.nim
nim c -d:release --nimcache:/tmp/nimcache_orbeliassim -o:bin/orbeliassim src/orbeliassim.nim
sudo install -m 0755 bin/orbeliasbench /usr/local/bin/orbeliasbench
sudo install -m 0755 bin/orbeliassim /usr/local/bin/orbeliassim
```

Verify:

```sh
command -v orbelias
command -v orbeliasd
orbelias --help
```

## Source-Tree Development

Use repo-local binaries only when you explicitly want to test the current
checkout without installing it:

```sh
nim c -d:release --nimcache:/tmp/nimcache_orbelias -o:bin/orbelias src/orbeliascli.nim
bin/orbelias --help
```

Documentation and examples use `orbelias` for installed usage. Test scripts may use
`bin/orbelias` to avoid depending on the user's PATH.
