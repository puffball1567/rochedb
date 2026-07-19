#pragma once

#include <cstdint>
#include <cstring>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "orbeliasdb.h"

namespace orbeliasdb {

using Id = orbelias_id;

struct Hit {
  Id id{};
  double score = 0.0;
  std::vector<std::uint8_t> payload;
};

struct RetrieveResult {
  std::vector<Hit> hits;
  int totalVectors = 0;
  int scanned = 0;
  int skippedVectors = 0;
  int returned = 0;
  int ringsTouched = 0;
  int payloadBytes = 0;
  int estimatedTokens = 0;
  int fanoutNodes = 0;
  double candidateReduction = 0.0;
};

class Error : public std::runtime_error {
 public:
  explicit Error(const std::string& message) : std::runtime_error(message) {}
};

inline int abiVersion() { return orbelias_abi_version(); }

inline std::string lastError(const char* fallback) {
  const char* err = orbelias_last_error();
  if (err != nullptr && err[0] != '\0') {
    return std::string(err);
  }
  return std::string(fallback);
}

inline std::vector<std::uint8_t> copyBytes(const void* data, std::size_t len) {
  std::vector<std::uint8_t> out(len);
  if (len > 0 && data != nullptr) {
    std::memcpy(out.data(), data, len);
  }
  return out;
}

class Db {
 public:
  Db() = default;

  static Db open(int nodes = 8) {
    orbelias_init();
    return Db(orbelias_open(nodes));
  }

  static Db openDir(std::string_view dir, int nodes = 8) {
    orbelias_init();
    return Db(orbelias_open_dir(nodes, std::string(dir).c_str()));
  }

  static Db connect(std::string_view peers) {
    orbelias_init();
    return Db(orbelias_connect(std::string(peers).c_str()));
  }

  static Db connectAuth(std::string_view peers,
                        std::string_view username = {},
                        std::string_view password = {},
                        std::string_view authToken = {},
                        std::string_view secretKey = {},
                        std::string_view galaxy = {}) {
    orbelias_init();
    std::string p(peers);
    std::string u(username);
    std::string pw(password);
    std::string token(authToken);
    std::string secret(secretKey);
    std::string g(galaxy);
    return Db(orbelias_connect_auth(p.c_str(), u.c_str(), pw.c_str(), token.c_str(),
                                 secret.c_str(), g.c_str()));
  }

  Db(const Db&) = delete;
  Db& operator=(const Db&) = delete;

  Db(Db&& other) noexcept : handle_(std::exchange(other.handle_, nullptr)) {}

  Db& operator=(Db&& other) noexcept {
    if (this != &other) {
      close();
      handle_ = std::exchange(other.handle_, nullptr);
    }
    return *this;
  }

  ~Db() { close(); }

  void close() noexcept {
    if (handle_ != nullptr) {
      orbelias_close(handle_);
      handle_ = nullptr;
    }
  }

  double now() const { return orbelias_now(checked()); }

  void advance(double dt) { orbelias_advance(checked(), dt); }

  void configureRing(std::string_view ring, double period) {
    std::string r(ring);
    if (orbelias_ring_configure(checked(), r.c_str(), period) != ORBELIAS_OK) {
      throw Error(lastError("failed to configure ring"));
    }
  }

  void setGalaxyDescription(std::string_view description) {
    std::string d(description);
    if (orbelias_set_galaxy_description(checked(), d.c_str()) != ORBELIAS_OK) {
      throw Error(lastError("failed to set galaxy description"));
    }
  }

  void setRingDescription(std::string_view ring, std::string_view description) {
    std::string r(ring);
    std::string d(description);
    if (orbelias_set_ring_description(checked(), r.c_str(), d.c_str()) != ORBELIAS_OK) {
      throw Error(lastError("failed to set ring description"));
    }
  }

  Id put(std::string_view ring, std::string_view payload) {
    return put(ring, reinterpret_cast<const std::uint8_t*>(payload.data()),
               payload.size());
  }

  Id put(std::string_view ring, const std::vector<std::uint8_t>& payload) {
    return put(ring, payload.data(), payload.size());
  }

  Id put(std::string_view ring, const std::uint8_t* data, std::size_t len) {
    Id id{};
    std::string r(ring);
    if (orbelias_put(checked(), r.c_str(), data, len, &id) != ORBELIAS_OK) {
      throw Error(lastError("put failed"));
    }
    return id;
  }

  Id putVec(std::string_view ring, std::string_view payload,
            const std::vector<float>& vec) {
    return putVec(ring, reinterpret_cast<const std::uint8_t*>(payload.data()),
                  payload.size(), vec);
  }

  Id putVec(std::string_view ring, const std::uint8_t* data, std::size_t len,
            const std::vector<float>& vec) {
    Id id{};
    std::string r(ring);
    if (orbelias_put_vec(checked(), r.c_str(), data, len, vec.data(), vec.size(),
                      &id) != ORBELIAS_OK) {
      throw Error(lastError("putVec failed"));
    }
    return id;
  }

  std::optional<std::vector<std::uint8_t>> get(Id id) const {
    std::size_t len = 0;
    void* ptr = orbelias_get(checked(), id, &len);
    if (ptr == nullptr) {
      return std::nullopt;
    }
    std::vector<std::uint8_t> out = copyBytes(ptr, len);
    orbelias_free(ptr);
    return out;
  }

  std::optional<std::string> getString(Id id) const {
    auto bytes = get(id);
    if (!bytes.has_value()) {
      return std::nullopt;
    }
    return std::string(bytes->begin(), bytes->end());
  }

  std::vector<std::optional<std::vector<std::uint8_t>>> batchGet(
      const std::vector<Id>& ids) const {
    orbelias_batch_result* result = orbelias_batch_get(checked(), ids.data(), ids.size());
    if (result == nullptr) {
      throw Error(lastError("batchGet failed"));
    }
    std::unique_ptr<orbelias_batch_result, decltype(&orbelias_batch_get_free)> guard(
        result, orbelias_batch_get_free);

    std::vector<std::optional<std::vector<std::uint8_t>>> out;
    out.reserve(result->len);
    for (std::size_t i = 0; i < result->len; ++i) {
      const orbelias_value& value = result->values[i];
      if (value.data == nullptr) {
        out.push_back(std::nullopt);
      } else {
        out.push_back(copyBytes(value.data, value.len));
      }
    }
    return out;
  }

  std::optional<std::vector<std::uint8_t>> query(Id id,
                                                std::string_view selection) const {
    std::string s(selection);
    std::size_t len = 0;
    void* ptr = orbelias_query(checked(), id, s.c_str(), &len);
    if (ptr == nullptr) {
      return std::nullopt;
    }
    std::vector<std::uint8_t> out = copyBytes(ptr, len);
    orbelias_free(ptr);
    return out;
  }

  std::optional<std::string> queryString(Id id, std::string_view selection) const {
    auto bytes = query(id, selection);
    if (!bytes.has_value()) {
      return std::nullopt;
    }
    return std::string(bytes->begin(), bytes->end());
  }

  RetrieveResult retrieve(const std::vector<float>& vec,
                          std::string_view ring = {},
                          int budget = 10,
                          int topRings = 50,
                          int focus = 3) const {
    std::string r(ring);
    orbelias_retrieve_result* result =
        orbelias_retrieve(checked(), vec.data(), vec.size(), r.c_str(), budget,
                       topRings, focus);
    if (result == nullptr) {
      throw Error(lastError("retrieve failed"));
    }
    std::unique_ptr<orbelias_retrieve_result, decltype(&orbelias_retrieve_free)> guard(
        result, orbelias_retrieve_free);

    RetrieveResult out;
    out.totalVectors = result->total_vectors;
    out.scanned = result->scanned;
    out.skippedVectors = result->skipped_vectors;
    out.returned = result->returned;
    out.ringsTouched = result->rings_touched;
    out.payloadBytes = result->payload_bytes;
    out.estimatedTokens = result->estimated_tokens;
    out.fanoutNodes = result->fanout_nodes;
    out.candidateReduction = result->candidate_reduction;
    out.hits.reserve(result->len);
    for (std::size_t i = 0; i < result->len; ++i) {
      const orbelias_hit& hit = result->hits[i];
      out.hits.push_back(Hit{hit.id, hit.score,
                             copyBytes(hit.payload, hit.payload_len)});
    }
    return out;
  }

  std::string atlas(const std::vector<float>& queryVec = {},
                    int maxCentroidDims = 8) const {
    std::size_t len = 0;
    void* ptr = orbelias_atlas(checked(), queryVec.data(), queryVec.size(),
                            maxCentroidDims, &len);
    if (ptr == nullptr) {
      throw Error(lastError("atlas failed"));
    }
    std::string out(static_cast<char*>(ptr), len);
    orbelias_free(ptr);
    return out;
  }

  int locate(Id id, double at = -1.0) const {
    return orbelias_locate(checked(), id, at);
  }

  double nextVisit(Id id, int node) const {
    return orbelias_next_visit(checked(), id, node);
  }

  double nextJoin(Id a, Id b) const {
    return orbelias_next_join(checked(), a, b);
  }

 private:
  explicit Db(void* handle) : handle_(handle) {
    if (handle_ == nullptr) {
      throw Error(lastError("failed to open OrbeliasDB"));
    }
  }

  void* checked() const {
    if (handle_ == nullptr) {
      throw Error("OrbeliasDB handle is closed");
    }
    return handle_;
  }

  void* handle_ = nullptr;
};

}  // namespace orbeliasdb

