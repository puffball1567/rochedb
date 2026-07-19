FROM nimlang/nim:2.2.10

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libsodium-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/orbeliasdb-deps
RUN nimble install -y nimsodium

WORKDIR /src
COPY orbeliasdb.nimble config.nims ./

COPY src ./src
RUN nim c -d:release --nimcache:/tmp/nimcache_orbeliasd -o:/usr/local/bin/orbeliasd src/orbeliasd.nim \
 && nim c -d:release --nimcache:/tmp/nimcache_orbeliascli -o:/usr/local/bin/orbeliascli src/orbeliascli.nim

WORKDIR /data
ENTRYPOINT ["orbeliasd"]
