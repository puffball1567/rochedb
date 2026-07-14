---
layout: home
title: RocheDB Documentation
---

# RocheDB Documentation

RocheDB is a ring-oriented NoSQL database prototype. It stores data with a
coordinate-like `ring` and uses that placement at read time to reduce the amount
of data that must be searched, transferred, held in memory, and passed to
downstream AI/RAG or application logic.

## Start Here

- [Concept](rochedb-concept.md)
- [Installation](installation.md)
- [Public API](public-api.md)
- [Configuration Reference](config-reference.md)
- [CLI Reference](cli-reference.md)
- [How RocheDB Differs From Typical NoSQL](nosql-positioning.md)
- [Feature Status / Roadmap](rochedb-status.md)
- [Benchmark Notes](rochedb-bench.md)
- [Benchmark Comparison Tables](benchmark-comparison.md)

## Core Guides

- [Detailed Design](rochedb-design.md)
- [Topology Configuration](topology-config.md)
- [Topology Pattern Catalog](topology-examples.md)
- [Universe Sync](universe-sync.md)
- [Cloud Operations Metrics](cloud-operations.md)
- [Threat Model](threat-model.md)
- [Test Coverage](test-coverage.md)

## Drivers And Protocol

- [Driver Installation](driver-installation.md)
- [Driver / FFI Roadmap](rochedb-driver-roadmap.md)
- [Protocol Compatibility](protocol-compatibility.md)
- [TLS Transport](tls-transport.md)
- [Payload Codecs](payload-codecs.md)
- [Vector Backend Selection](vector-backends.md)
- [FAISS Versioning Policy](faiss-versioning.md)

## Release

- [Release Checklist](release-checklist.md)
- [GitHub Release Draft](github-release-v0.4.0.md)
