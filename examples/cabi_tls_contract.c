/* OrbeliasDB C ABI TLS smoke.
 *
 * This verifies the native-driver path:
 *   liborbeliasdb.so -> orbelias_connect_auth_tls -> OrbeliasDB wire TLS -> orbeliasd
 */
#include <stdio.h>
#include <stdlib.h>
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
  const char *peers = getenv("ORBELIAS_TLS_PEERS");
  const char *ca = getenv("ORBELIAS_TLS_CA");
  const char *insecure_env = getenv("ORBELIAS_TLS_INSECURE");
  int insecure = insecure_env && strcmp(insecure_env, "0") != 0;
  if (!peers || !peers[0]) peers = "localhost:17651";
  if (!ca) ca = "";

  orbelias_init();

  void *db = orbelias_connect_auth_tls(
    peers,
    "alice",
    "secret",
    "",
    "shared-secret",
    "",
    1,
    ca,
    "localhost",
    insecure);
  if (!db) return fail("TLS connect through C ABI failed");

  orbelias_id id;
  const char *payload = "{\"title\":\"C ABI TLS\",\"ok\":true}";
  if (orbelias_put_codec(db, "secure/cabi", payload, strlen(payload),
                      ORBELIAS_CODEC_JSON, &id) != ORBELIAS_OK)
    return fail("TLS put through C ABI failed");

  size_t len = 0;
  int codec = -1;
  char *got = orbelias_get_codec(db, id, &len, &codec);
  if (!got || len == 0) return fail("TLS get through C ABI failed");
  if (codec != ORBELIAS_CODEC_JSON) return fail("TLS get codec mismatch");
  if (strstr(got, "C ABI TLS") == NULL) return fail("TLS payload mismatch");
  orbelias_free(got);

  orbelias_close(db);
  printf("C ABI TLS contract OK\n");
  return 0;
}
