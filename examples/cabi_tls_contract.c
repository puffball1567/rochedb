/* RocheDB C ABI TLS smoke.
 *
 * This verifies the native-driver path:
 *   librochedb.so -> roche_connect_auth_tls -> RocheDB wire TLS -> roched
 */
#include <stdio.h>
#include <stdlib.h>
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
  const char *peers = getenv("ROCHE_TLS_PEERS");
  const char *ca = getenv("ROCHE_TLS_CA");
  const char *insecure_env = getenv("ROCHE_TLS_INSECURE");
  int insecure = insecure_env && strcmp(insecure_env, "0") != 0;
  if (!peers || !peers[0]) peers = "localhost:17651";
  if (!ca) ca = "";

  roche_init();

  void *db = roche_connect_auth_tls(
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

  roche_id id;
  const char *payload = "{\"title\":\"C ABI TLS\",\"ok\":true}";
  if (roche_put_codec(db, "secure/cabi", payload, strlen(payload),
                      ROCHE_CODEC_JSON, &id) != ROCHE_OK)
    return fail("TLS put through C ABI failed");

  size_t len = 0;
  int codec = -1;
  char *got = roche_get_codec(db, id, &len, &codec);
  if (!got || len == 0) return fail("TLS get through C ABI failed");
  if (codec != ROCHE_CODEC_JSON) return fail("TLS get codec mismatch");
  if (strstr(got, "C ABI TLS") == NULL) return fail("TLS payload mismatch");
  roche_free(got);

  roche_close(db);
  printf("C ABI TLS contract OK\n");
  return 0;
}
