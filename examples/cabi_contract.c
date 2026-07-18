/* RocheDB C ABI contract smoke test
 * build: gcc examples/cabi_contract.c -Iinclude -Llib -lrochedb -Wl,-rpath,'$ORIGIN/../lib' -o bin/cabi_contract
 */
#include <stdio.h>
#include <string.h>
#include "rochedb.h"

static int fail(const char *msg) {
  fprintf(stderr, "FAIL: %s", msg);
  const char *err = roche_last_error();
  if (err && err[0]) fprintf(stderr, " (%s)", err);
  fprintf(stderr, "\n");
  return 1;
}

int main(void) {
  const char *err;

  roche_init();
  roche_init();

  if (roche_abi_version() != ROCHE_ABI_VERSION) return fail("ABI version mismatch");
  if (sizeof(roche_id) != 24) return fail("roche_id must stay 24 bytes");

  void *bad_db = roche_open(0);
  if (bad_db != NULL) return fail("open should reject zero nodes");
  err = roche_last_error();
  if (!err || strstr(err, "nodes") == NULL) return fail("last_error should mention nodes");

  void *db = roche_open(8);
  if (!db) return fail("open failed");

  if (roche_set_galaxy_description(db, "Contract test galaxy") != ROCHE_OK)
    return fail("set galaxy description failed");
  if (roche_set_ring_description(db, "docs/api", "C ABI documentation") != ROCHE_OK)
    return fail("set ring description failed");

  roche_id id;
  const char *payload = "hello from C ABI";
  float vec[2] = {1.0f, 0.0f};
  if (roche_put_vec(db, "docs/api", payload, strlen(payload), vec, 2, &id) != ROCHE_OK)
    return fail("put_vec failed");

  roche_id bif_id;
  const unsigned char bif[] = {1, 0, 0, 0};
  if (roche_put_codec(db, "artifacts/bif", bif, sizeof(bif), ROCHE_CODEC_BIF, &bif_id) != ROCHE_OK)
    return fail("put_codec failed");
  size_t bif_len = 0;
  int bif_codec = -1;
  void *bif_out = roche_get_codec(db, bif_id, &bif_len, &bif_codec);
  if (!bif_out || bif_len != sizeof(bif) || bif_codec != ROCHE_CODEC_BIF)
    return fail("get_codec failed");
  if (memcmp(bif_out, bif, sizeof(bif)) != 0) return fail("get_codec bytes differ");
  roche_free(bif_out);

  roche_id json_id;
  const char *json_payload = "{\"title\":\"C ABI\",\"status\":\"draft\"}";
  if (roche_put_codec(db, "docs/api", json_payload, strlen(json_payload),
                      ROCHE_CODEC_JSON, &json_id) != ROCHE_OK)
    return fail("put_codec json failed");

  size_t read_len = 0;
  char *read_page = roche_read_ring_json(
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
  roche_free(read_page);

  read_page = roche_read_ring_json(
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
  roche_free(read_page);

  roche_id nif_id;
  const char *nif_payload = "(object (title RocheDB))";
  if (roche_put_codec(db, "artifacts/nif", nif_payload, strlen(nif_payload),
                      ROCHE_CODEC_NIF, &nif_id) != ROCHE_OK)
    return fail("put_codec nif failed");
  read_page = roche_read_ring_json(
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
  roche_free(read_page);

  read_page = roche_read_ring_json(
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
  err = roche_last_error();
  if (!err || strstr(err, "filter") == NULL) return fail("last_error should mention filter");

  read_page = roche_read_ring_json(
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
  err = roche_last_error();
  if (!err || strstr(err, "sort field") == NULL) return fail("last_error should mention sort field");

  read_page = roche_read_ring_json(
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
  err = roche_last_error();
  if (!err || strstr(err, "ring") == NULL) return fail("last_error should mention read ring");

  size_t atlas_len = 0;
  char *atlas = roche_atlas(db, vec, 2, 8, &atlas_len);
  if (!atlas || atlas_len == 0) return fail("atlas failed");
  if (strstr(atlas, "Contract test galaxy") == NULL) return fail("atlas misses galaxy description");
  if (strstr(atlas, "C ABI documentation") == NULL) return fail("atlas misses ring description");
  roche_free(atlas);

  roche_id dummy;
  if (roche_put(db, NULL, payload, strlen(payload), &dummy) != ROCHE_ERR)
    return fail("NULL ring should fail");
  err = roche_last_error();
  if (!err || strstr(err, "ring") == NULL) return fail("last_error should mention ring");

  if (roche_put(db, "docs/api", payload, (size_t)-1, &dummy) != ROCHE_ERR)
    return fail("oversized payload length should fail");
  err = roche_last_error();
  if (!err || strstr(err, "length") == NULL) return fail("last_error should mention length");

  roche_close(db);
  if (roche_get(db, id, &read_len) != NULL)
    return fail("closed handle should not read");
  err = roche_last_error();
  if (!err || strstr(err, "closed") == NULL) return fail("last_error should mention closed handle");
  roche_close(db);
  err = roche_last_error();
  if (!err || strstr(err, "closed") == NULL) return fail("double close should stay fail-closed");
  printf("C ABI contract OK\n");
  return 0;
}
