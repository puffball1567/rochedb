/* RocheDB C ABI — src/rochedb_capi.nim と 1:1 対応（設計書 §13）
 *
 * 最小の使い方:
 *   roche_init();
 *   void *db = roche_open(8);
 *   roche_id id;
 *   roche_put(db, "default", "hello", 5, &id);
 *   size_t len; char *p = roche_get(db, id, &len);   // 使い終わったら roche_free(p)
 *   int node = roche_locate(db, id, -1.0);           // 今どのノードか（問い合わせゼロ）
 *   roche_close(db);
 */
#ifndef ROCHEDB_H
#define ROCHEDB_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 不透明ID（24バイト・値渡し）。中身に触る必要はない。 */
typedef struct roche_id {
  uint64_t parent;
  uint32_t epoch;
  uint32_t seq;
  double   t_write;
} roche_id;

typedef struct roche_hit {
  roche_id id;
  double   score;
  void    *payload;
  size_t   payload_len;
} roche_hit;

typedef struct roche_retrieve_result {
  size_t     len;
  roche_hit *hits;
  int        total_vectors;
  int        scanned;
  int        skipped_vectors;
  int        returned;
  int        rings_touched;
  int        payload_bytes;
  int        estimated_tokens;
  int        fanout_nodes;
  double     candidate_reduction;
} roche_retrieve_result;

typedef struct roche_value {
  void  *data;
  size_t len;
} roche_value;

typedef struct roche_batch_result {
  size_t       len;
  roche_value *values;
} roche_batch_result;

#define ROCHE_OK   0
#define ROCHE_ERR -1

#define ROCHE_ABI_VERSION 1

/* ABI バージョンと直近エラー。last_error はスレッドローカル相当で、所有権は呼び出し側にない。 */
int         roche_abi_version(void);
const char *roche_last_error(void);

/* Nim ランタイム初期化。プロセスで最初に一度呼ぶ。 */
void   roche_init(void);

/* DB を開く / 閉じる。nodes はノード数（8 が無難な既定）。失敗時 NULL。 */
void  *roche_open(int nodes);
/* 永続化つきで開く。dir の追記ログに書き、再オープンで復元される。 */
void  *roche_open_dir(int nodes, const char *dir);
/* クラスタへ接続。peers = "host:port,host:port,..."（roched の並び順） */
void  *roche_connect(const char *peers);
/* 認証つきクラスタ接続。不要な引数は NULL または空文字でよい。 */
void  *roche_connect_auth(const char *peers,
                          const char *username,
                          const char *password,
                          const char *auth_token,
                          const char *secret_key,
                          const char *galaxy);
void   roche_close(void *db);

/* DB 時計（PoC は決定論のため手動クロック）。 */
double roche_now(void *db);
void   roche_advance(void *db, double dt);

/* 環の公転周期を設定（省略時 60s 相当）。JOIN したい2環は 1:2 等の整数比に。 */
int    roche_ring_configure(void *db, const char *ring, double period);
int    roche_set_galaxy_description(void *db, const char *description);
int    roche_set_ring_description(void *db, const char *ring, const char *description);

/* 書き込み。out_id に不透明IDが入る。以後この ID だけで所在計算が閉じる。 */
int    roche_put(void *db, const char *ring,
                 const void *data, size_t len, roche_id *out_id);
/* vector 付き書き込み。vec は float32 配列、vec_len は要素数。 */
int    roche_put_vec(void *db, const char *ring,
                     const void *data, size_t len,
                     const float *vec, size_t vec_len,
                     roche_id *out_id);

/* 読み出し。NUL 終端付きの複製バッファを返す（roche_free で解放）。
 * 見つからなければ NULL。 */
void  *roche_get(void *db, roche_id id, size_t *out_len);
void   roche_free(void *p);
/* 複数 ID のまとめ読み。戻り値は roche_batch_get_free で解放。 */
roche_batch_result *roche_batch_get(void *db, const roche_id *ids, size_t ids_len);
void   roche_batch_get_free(roche_batch_result *r);

/* 選択取得（GraphQL 風）: selection 例 "{ title author { name } }"。
 * 選択した部分の JSON 文字列を返す（roche_free で解放）。失敗時 NULL。 */
void  *roche_query(void *db, roche_id id, const char *selection, size_t *out_len);

/* vector 近傍検索。ring は NULL/空文字で global。戻り値は roche_retrieve_free で解放。 */
roche_retrieve_result *roche_retrieve(void *db,
                                      const float *vec, size_t vec_len,
                                      const char *ring,
                                      int budget,
                                      int top_rings,
                                      int focus);
void   roche_retrieve_free(roche_retrieve_result *r);

/* Atlas JSON。LLM/agent が最初に読む galaxy/ring map。戻り値は roche_free で解放。 */
void  *roche_atlas(void *db, const float *query_vec, size_t query_vec_len,
                   int max_centroid_dims, size_t *out_len);

/* 所在。at < 0 で「現在」。未来時刻も渡せる（ephemeris）。失敗時 -1。 */
int    roche_locate(void *db, roche_id id, double at);

/* その ID が指定ノードに次に到着する時刻。 */
double roche_next_visit(void *db, roche_id id, int node);

/* 2つの ID が次に同一ノードへ同居する時刻（ローカル JOIN 窓）。会合しなければ -1。 */
double roche_next_join(void *db, roche_id a, roche_id b);

#ifdef __cplusplus
}
#endif

#endif /* ROCHEDB_H */
