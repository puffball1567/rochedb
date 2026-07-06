FROM php:8.3-cli

RUN apt-get update \
  && apt-get install -y --no-install-recommends libffi-dev \
  && docker-php-ext-configure ffi --with-ffi \
  && docker-php-ext-install ffi \
  && rm -rf /var/lib/apt/lists/*
