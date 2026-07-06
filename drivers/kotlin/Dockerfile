FROM eclipse-temurin:21-jdk-jammy

ARG KOTLIN_VERSION=2.0.21

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip g++ libsodium23 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/JetBrains/kotlin/releases/download/v${KOTLIN_VERSION}/kotlin-compiler-${KOTLIN_VERSION}.zip" -o /tmp/kotlin.zip \
    && unzip -q /tmp/kotlin.zip -d /opt \
    && rm /tmp/kotlin.zip

ENV PATH="/opt/kotlinc/bin:${PATH}"

WORKDIR /work
