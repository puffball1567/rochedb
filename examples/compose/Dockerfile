FROM nimlang/nim:2.2.10-alpine

WORKDIR /src
COPY . .
RUN nim c -d:release --nimcache:/tmp/nimcache_roched -o:/usr/local/bin/roched src/roched.nim \
 && nim c -d:release --nimcache:/tmp/nimcache_rochecli -o:/usr/local/bin/rochecli src/rochecli.nim

WORKDIR /data
ENTRYPOINT ["roched"]
