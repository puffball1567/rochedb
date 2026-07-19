/* C ABI overhead benchmark
 * build: gcc -O2 examples/cbench.c -Iinclude -Llib -lorbeliasdb -Wl,-rpath,'$ORIGIN/../lib' -o bin/cbench
 */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "orbeliasdb.h"

#define N 1000000

static double ns_per_op(struct timespec a, struct timespec b, long ops) {
  double ns = (b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec);
  return ns / ops;
}

int main(void) {
  static orbelias_id ids[N];
  char payload[101];
  struct timespec t0, t1;
  for (int i = 0; i < 100; i++) payload[i] = 'a' + i % 26;
  payload[100] = 0;

  orbelias_init();
  void *db = orbelias_open(8);
  if (!db) return 1;

  clock_gettime(CLOCK_MONOTONIC, &t0);
  for (int i = 0; i < N; i++)
    if (orbelias_put(db, "bench", payload, 100, &ids[i]) != ORBELIAS_OK) return 1;
  clock_gettime(CLOCK_MONOTONIC, &t1);
  printf("  orbelias_put   (C ABI, %d records)       %8.1f ns/op\n", N, ns_per_op(t0, t1, N));

  size_t len; long got = 0;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  for (int i = 0; i < N; i++) {
    char *p = orbelias_get(db, ids[i], &len);   /* includes copied, NUL-terminated buffer */
    got += len;
    orbelias_free(p);
  }
  clock_gettime(CLOCK_MONOTONIC, &t1);
  printf("  orbelias_get   (C ABI, copy+free)        %8.1f ns/op\n", ns_per_op(t0, t1, N));
  if (got != (long)N * 100) return 1;

  long acc = 0;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  for (int i = 0; i < N; i++)
    acc += orbelias_locate(db, ids[i], (double)i);
  clock_gettime(CLOCK_MONOTONIC, &t1);
  printf("  orbelias_locate(C ABI, future time)      %8.1f ns/op  (acc=%ld)\n",
         ns_per_op(t0, t1, N), acc);

  orbelias_close(db);
  return 0;
}
