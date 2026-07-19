/* OrbeliasDB C ABI contract smoke test
 * build: gcc examples/cabi_contract.c -Iinclude -Llib -lorbeliasdb -Wl,-rpath,'$ORIGIN/../lib' -o bin/cabi_contract
 */
#include <stdio.h>
#include <string.h>
#include "orbeliasdb.h"

static int fail(const char *msg) {
  fprintf(stderr, "FAIL: %s", msg);
  const char *err = orbelias_last_error();
  if (err && err[0]) fprintf(stderr, " (%s)", err);
  fprintf(stderr, "\n");
  return 1;
}

int main(void) {
  const char *err;

  orbelias_init();
  orbelias_init();

  if (orbelias_abi_version() != ORBELIAS_ABI_VERSION) return fail("ABI version mismatch");
  if (sizeof(orbelias_id) != 24) return fail("orbelias_id must stay 24 bytes");

  void *bad_db = orbelias_open(0);
  if (bad_db != NULL) return fail("open should reject zero nodes");
  err = orbelias_last_error();
  if (!err || strstr(err, "nodes") == NULL) return fail("last_error should mention nodes");

  void *db = orbelias_open(8);
  if (!db) return fail("open failed");

  if (orbelias_set_galaxy_description(db, "Contract test galaxy") != ORBELIAS_OK)
    return fail("set galaxy description failed");
  if (orbelias_set_ring_description(db, "docs/api", "C ABI documentation") != ORBELIAS_OK)
    return fail("set ring description failed");

  orbelias_id id;
  const char *payload = "hello from C ABI";
  float vec[2] = {1.0f, 0.0f};
  if (orbelias_put_vec(db, "docs/api", payload, strlen(payload), vec, 2, &id) != ORBELIAS_OK)
    return fail("put_vec failed");

  orbelias_id bif_id;
  const unsigned char bif[] = {1, 0, 0, 0};
  if (orbelias_put_codec(db, "artifacts/bif", bif, sizeof(bif), ORBELIAS_CODEC_BIF, &bif_id) != ORBELIAS_OK)
    return fail("put_codec failed");
  size_t bif_len = 0;
  int bif_codec = -1;
  void *bif_out = orbelias_get_codec(db, bif_id, &bif_len, &bif_codec);
  if (!bif_out || bif_len != sizeof(bif) || bif_codec != ORBELIAS_CODEC_BIF)
    return fail("get_codec failed");
  if (memcmp(bif_out, bif, sizeof(bif)) != 0) return fail("get_codec bytes differ");
  orbelias_free(bif_out);

  orbelias_id json_id;
  const char *json_payload = "{\"title\":\"C ABI\",\"status\":\"draft\"}";
  if (orbelias_put_codec(db, "docs/api", json_payload, strlen(json_payload),
                      ORBELIAS_CODEC_JSON, &json_id) != ORBELIAS_OK)
    return fail("put_codec json failed");

  size_t read_len = 0;
  char *read_page = orbelias_read_ring_json(
    db,
    "docs/api",
    "{\"status\":\"draft\"}",
    "{ title }",
    1,
    "",
    0,
    1,
    20,
    "time",
    1,
    &read_len);
  if (!read_page || read_len == 0) return fail("read_ring_json failed");
  if (strstr(read_page, "\"items\"") == NULL) return fail("read_ring_json misses items");
  if (strstr(read_page, "\"count\":1") == NULL) return fail("read_ring_json misses count");
  if (strstr(read_page, "\"title\":\"C ABI\"") == NULL)
    return fail("read_ring_json misses selected JSON payload");
  orbelias_free(read_page);

  read_page = orbelias_read_ring_json(
    db,
    "artifacts/bif",
    "",
    "",
    10,
    "",
    0,
    1,
    20,
    "time",
    1,
    &read_len);
  if (!read_page || strstr(read_page, "\"codec\":\"bif\"") == NULL ||
      strstr(read_page, "\"encoding\":\"base64\"") == NULL)
    return fail("read_ring_json should base64 encode binary payloads");
  orbelias_free(read_page);

  orbelias_id nif_id;
  const char *nif_payload = "(object (title OrbeliasDB))";
  if (orbelias_put_codec(db, "artifacts/nif", nif_payload, strlen(nif_payload),
                      ORBELIAS_CODEC_NIF, &nif_id) != ORBELIAS_OK)
    return fail("put_codec nif failed");
  read_page = orbelias_read_ring_json(
    db,
    "artifacts/nif",
    "",
    "",
    10,
    "",
    0,
    1,
    20,
    "time",
    1,
    &read_len);
  if (!read_page || strstr(read_page, "\"codec\":\"nif\"") == NULL ||
      strstr(read_page, "\"encoding\":\"base64\"") == NULL)
    return fail("read_ring_json should preserve NIF metadata");
  orbelias_free(read_page);

  read_page = orbelias_read_ring_json(
    db,
    "docs/api",
    "[]",
    "",
    10,
    "",
    0,
    1,
    20,
    "time",
    1,
    &read_len);
  if (read_page != NULL) return fail("read_ring_json should reject non-object filter");
  err = orbelias_last_error();
  if (!err || strstr(err, "filter") == NULL) return fail("last_error should mention filter");

  read_page = orbelias_read_ring_json(
    db,
    "docs/api",
    "",
    "",
    10,
    "",
    0,
    1,
    20,
    "payload",
    1,
    &read_len);
  if (read_page != NULL) return fail("read_ring_json should reject invalid sort field");
  err = orbelias_last_error();
  if (!err || strstr(err, "sort field") == NULL) return fail("last_error should mention sort field");

  read_page = orbelias_read_ring_json(
    db,
    NULL,
    "",
    "",
    10,
    "",
    0,
    1,
    20,
    "time",
    1,
    &read_len);
  if (read_page != NULL) return fail("read_ring_json should reject NULL ring");
  err = orbelias_last_error();
  if (!err || strstr(err, "ring") == NULL) return fail("last_error should mention read ring");

  size_t atlas_len = 0;
  char *atlas = orbelias_atlas(db, vec, 2, 8, &atlas_len);
  if (!atlas || atlas_len == 0) return fail("atlas failed");
  if (strstr(atlas, "Contract test galaxy") == NULL) return fail("atlas misses galaxy description");
  if (strstr(atlas, "C ABI documentation") == NULL) return fail("atlas misses ring description");
  orbelias_free(atlas);

  orbelias_id dummy;
  if (orbelias_put(db, NULL, payload, strlen(payload), &dummy) != ORBELIAS_ERR)
    return fail("NULL ring should fail");
  err = orbelias_last_error();
  if (!err || strstr(err, "ring") == NULL) return fail("last_error should mention ring");

  if (orbelias_put(db, "docs/api", payload, (size_t)-1, &dummy) != ORBELIAS_ERR)
    return fail("oversized payload length should fail");
  err = orbelias_last_error();
  if (!err || strstr(err, "length") == NULL) return fail("last_error should mention length");

  orbelias_close(db);
  if (orbelias_get(db, id, &read_len) != NULL)
    return fail("closed handle should not read");
  err = orbelias_last_error();
  if (!err || strstr(err, "closed") == NULL) return fail("last_error should mention closed handle");
  orbelias_close(db);
  err = orbelias_last_error();
  if (!err || strstr(err, "closed") == NULL) return fail("double close should stay fail-closed");
  printf("C ABI contract OK\n");
  return 0;
}
