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
  roche_init();

  if (roche_abi_version() != ROCHE_ABI_VERSION) return fail("ABI version mismatch");
  if (sizeof(roche_id) != 24) return fail("roche_id must stay 24 bytes");

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

  size_t atlas_len = 0;
  char *atlas = roche_atlas(db, vec, 2, 8, &atlas_len);
  if (!atlas || atlas_len == 0) return fail("atlas failed");
  if (strstr(atlas, "Contract test galaxy") == NULL) return fail("atlas misses galaxy description");
  if (strstr(atlas, "C ABI documentation") == NULL) return fail("atlas misses ring description");
  roche_free(atlas);

  roche_id dummy;
  if (roche_put(db, NULL, payload, strlen(payload), &dummy) != ROCHE_ERR)
    return fail("NULL ring should fail");
  const char *err = roche_last_error();
  if (!err || strstr(err, "ring") == NULL) return fail("last_error should mention ring");

  roche_close(db);
  printf("C ABI contract OK\n");
  return 0;
}
