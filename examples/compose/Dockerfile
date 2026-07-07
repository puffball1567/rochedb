FROM nimlang/nim:2.2.10

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libsodium-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/rochedb-deps
RUN nimble install -y nimsodium

WORKDIR /src
COPY rochedb.nimble config.nims ./

COPY src ./src
RUN nim c -d:release --nimcache:/tmp/nimcache_roched -o:/usr/local/bin/roched src/roched.nim \
 && nim c -d:release --nimcache:/tmp/nimcache_rochecli -o:/usr/local/bin/rochecli src/rochecli.nim

WORKDIR /data
ENTRYPOINT ["roched"]
