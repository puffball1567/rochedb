---
layout: page
title: Installation
---

# Installation

RocheDB installs command-line binaries named `roche`, `roched`, `rochecli`,
`rochebench`, and `rochesim`.

For normal use, the command should be available as `roche`, not as
`bin/roche`. The `bin/` form is only for source-tree development and smoke
tests.

## Prerequisites

- Nim `2.0.0` or newer
- `git`
- `gcc` or another C compiler supported by Nim
- `libsodium` development files for `nimsodium`

## User Install

Install RocheDB from Nimble:

```sh
nimble install rochedb
```

Use a source checkout when you want to run the full test suite, examples, or
driver smoke tests:

```sh
git clone https://github.com/puffball1567/rochedb.git
cd rochedb
nimble install -y
```

Nimble installs binaries into `~/.nimble/bin` by default. Add it to your shell
PATH if `roche --help` is not found:

```sh
export PATH="$HOME/.nimble/bin:$PATH"
```

For a persistent shell setup:

```sh
printf '\nexport PATH="$HOME/.nimble/bin:$PATH"\n' >> ~/.profile
```

Then verify:

```sh
roche --help
roched --help
```

## System Install

For server-style deployments, use `/usr/local/bin`, matching the usual source
install location for database tools such as MySQL or PostgreSQL client/server
binaries.

Build repo-local binaries:

```sh
nim c -d:release --nimcache:/tmp/nimcache_roche -o:bin/roche src/rochecli.nim
nim c -d:release --nimcache:/tmp/nimcache_roched -o:bin/roched src/roched.nim
```

Install them onto the system PATH:

```sh
sudo install -m 0755 bin/roche /usr/local/bin/roche
sudo install -m 0755 bin/roched /usr/local/bin/roched
```

Optional development and benchmark tools:

```sh
nim c -d:release --nimcache:/tmp/nimcache_rochebench -o:bin/rochebench src/rochebench.nim
nim c -d:release --nimcache:/tmp/nimcache_rochesim -o:bin/rochesim src/rochesim.nim
sudo install -m 0755 bin/rochebench /usr/local/bin/rochebench
sudo install -m 0755 bin/rochesim /usr/local/bin/rochesim
```

Verify:

```sh
command -v roche
command -v roched
roche --help
```

## Source-Tree Development

Use repo-local binaries only when you explicitly want to test the current
checkout without installing it:

```sh
nim c -d:release --nimcache:/tmp/nimcache_roche -o:bin/roche src/rochecli.nim
bin/roche --help
```

Documentation and examples use `roche` for installed usage. Test scripts may use
`bin/roche` to avoid depending on the user's PATH.
