FROM swift:6.0

RUN apt-get update \
  && apt-get install -y --no-install-recommends libsodium23 \
  && rm -rf /var/lib/apt/lists/*
