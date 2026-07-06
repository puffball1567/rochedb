/* RocheDB C ABI demo
 * build: gcc examples/demo.c -Iinclude -Llib -lrochedb -Wl,-rpath,'$ORIGIN/../lib' -o bin/demo
 */
#include <stdio.h>
#include <string.h>
#include "rochedb.h"

int main(void) {
  roche_init();
  void *db = roche_open(8);
  if (!db) { fprintf(stderr, "open failed\n"); return 1; }

  /* Put two rings in a 1:2 resonance for local-join timing. */
  roche_ring_configure(db, "docs", 30.0);
  roche_ring_configure(db, "logs", 60.0);

  roche_id d, l;
  const char *doc = "paper: ephemeris-based placement";
  const char *log = "access log for the paper";
  float doc_vec[2] = {1.0f, 0.0f};
  if (roche_put_vec(db, "docs", doc, strlen(doc), doc_vec, 2, &d) != ROCHE_OK) return 1;
  if (roche_put(db, "logs", log, strlen(log), &l) != ROCHE_OK) return 1;

  size_t len;
  char *p = roche_get(db, d, &len);
  printf("get       : %.*s (%zu bytes)\n", (int)len, p, len);
  roche_free(p);

  roche_id ids[2] = {d, l};
  roche_batch_result *br = roche_batch_get(db, ids, 2);
  if (!br) return 1;
  printf("batch_get : %zu values\n", br->len);
  for (size_t i = 0; i < br->len; i++) {
    printf("  value   : %.*s\n", (int)br->values[i].len, (char *)br->values[i].data);
  }
  roche_batch_get_free(br);

  roche_retrieve_result *rr = roche_retrieve(db, doc_vec, 2, "docs", 4, 0, 0);
  if (!rr) return 1;
  printf("retrieve  : hits=%zu scanned=%d reduction=%.1f%%\n",
         rr->len, rr->scanned, rr->candidate_reduction * 100.0);
  for (size_t i = 0; i < rr->len; i++) {
    printf("  hit     : %.3f %.*s\n", rr->hits[i].score,
           (int)rr->hits[i].payload_len, (char *)rr->hits[i].payload);
  }
  roche_retrieve_free(rr);

  printf("locate now: doc=node%d  log=node%d\n",
         roche_locate(db, d, -1.0), roche_locate(db, l, -1.0));
  printf("locate@120: doc=node%d  log=node%d   (future location computed locally)\n",
         roche_locate(db, d, 120.0), roche_locate(db, l, 120.0));

  double tj = roche_next_join(db, d, l);
  printf("next join : t=%.2fs\n", tj);
  roche_advance(db, tj);
  printf("at join   : doc=node%d  log=node%d   (same node = local join window)\n",
         roche_locate(db, d, -1.0), roche_locate(db, l, -1.0));

  double tv = roche_next_visit(db, d, 0);
  printf("next visit: doc arrives at node0 at t=%.2fs\n", tv);

  roche_close(db);
  printf("OK\n");
  return 0;
}
