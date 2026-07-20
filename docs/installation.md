---
layout: page
title: Installation
---

# Installation

KoutenDB installs command-line binaries named `kouten`, `koutend`, `koutencli`,
`koutenbench`, and `koutensim`.

For normal use, the command should be available as `kouten`, not as
`bin/kouten`. The `bin/` form is only for source-tree development and smoke
tests.

## Prerequisites

- Nim `2.0.0` or newer
- `git`
- `gcc` or another C compiler supported by Nim
- `libsodium` development files for `nimsodium`

## User Install

Install KoutenDB from Nimble:

```sh
nimble install koutendb
```

Use a source checkout when you want to run the full test suite, examples, or
driver smoke tests:

```sh
git clone https://github.com/puffball1567/koutendb.git
cd koutendb
nimble install -y
```

Nimble installs binaries into `~/.nimble/bin` by default. Add it to your shell
PATH if `kouten --help` is not found:

```sh
export PATH="$HOME/.nimble/bin:$PATH"
```

For a persistent shell setup:

```sh
printf '\nexport PATH="$HOME/.nimble/bin:$PATH"\n' >> ~/.profile
```

Then verify:

```sh
kouten --help
koutend --help
```

## System Install

For server-style deployments, use `/usr/local/bin`, matching the usual source
install location for database tools such as MySQL or PostgreSQL client/server
binaries.

Build repo-local binaries:

```sh
nim c -d:release --nimcache:/tmp/nimcache_kouten -o:bin/kouten src/koutencli.nim
nim c -d:release --nimcache:/tmp/nimcache_koutend -o:bin/koutend src/koutend.nim
```

Install them onto the system PATH:

```sh
sudo install -m 0755 bin/kouten /usr/local/bin/kouten
sudo install -m 0755 bin/koutend /usr/local/bin/koutend
```

Optional development and benchmark tools:

```sh
nim c -d:release --nimcache:/tmp/nimcache_koutenbench -o:bin/koutenbench src/koutenbench.nim
nim c -d:release --nimcache:/tmp/nimcache_koutensim -o:bin/koutensim src/koutensim.nim
sudo install -m 0755 bin/koutenbench /usr/local/bin/koutenbench
sudo install -m 0755 bin/koutensim /usr/local/bin/koutensim
```

Verify:

```sh
command -v kouten
command -v koutend
kouten --help
```

## Source-Tree Development

Use repo-local binaries only when you explicitly want to test the current
checkout without installing it:

```sh
nim c -d:release --nimcache:/tmp/nimcache_kouten -o:bin/kouten src/koutencli.nim
bin/kouten --help
```

Documentation and examples use `kouten` for installed usage. Test scripts may use
`bin/kouten` to avoid depending on the user's PATH.
