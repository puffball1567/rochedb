<?php
declare(strict_types=1);

namespace KoutenDB;

use FFI;
use FFI\CData;
use RuntimeException;

final class KoutenId
{
    public function __construct(
        public readonly int|string $parent,
        public readonly int $epoch,
        public readonly int $seq,
        public readonly float $tWrite,
    ) {
    }
}

final class KoutenHit
{
    public function __construct(
        public readonly KoutenId $id,
        public readonly float $score,
        public readonly string $payload,
    ) {
    }
}

final class RetrieveResult
{
    /** @param list<KoutenHit> $hits */
    public function __construct(
        public readonly array $hits,
        public readonly array $stats,
    ) {
    }
}

final class KoutenDB
{
    private const ABI_VERSION = 2;

    private static ?FFI $ffi = null;
    private ?CData $handle;

    private function __construct(CData $handle)
    {
        $this->handle = $handle;
    }

    public function __destruct()
    {
        $this->close();
    }

    public static function open(int $nodes = 8, string $lib = __DIR__ . '/../../../lib/libkoutendb.so'): self
    {
        $ffi = self::ffi($lib);
        $handle = $ffi->kouten_open($nodes);
        if ($handle === null) {
            throw self::lastError();
        }
        return new self($handle);
    }

    public static function openDir(int $nodes, string $dir, string $lib = __DIR__ . '/../../../lib/libkoutendb.so'): self
    {
        $ffi = self::ffi($lib);
        $handle = $ffi->kouten_open_dir($nodes, $dir);
        if ($handle === null) {
            throw self::lastError();
        }
        return new self($handle);
    }

    public static function connectAuth(
        string $peers,
        string $username = '',
        string $password = '',
        string $authToken = '',
        string $secretKey = '',
        string $galaxy = '',
        string $lib = __DIR__ . '/../../../lib/libkoutendb.so',
    ): self {
        $ffi = self::ffi($lib);
        $handle = $ffi->kouten_connect_auth($peers, $username, $password, $authToken, $secretKey, $galaxy);
        if ($handle === null) {
            throw self::lastError();
        }
        return new self($handle);
    }

    public static function connect(string $peers, string $lib = __DIR__ . '/../../../lib/libkoutendb.so'): self
    {
        return self::connectAuth($peers, lib: $lib);
    }

    public function close(): void
    {
        if ($this->handle !== null) {
            self::ffi()->kouten_close($this->handle);
            $this->handle = null;
        }
    }

    public function configureRing(string $ring, float $period): void
    {
        $this->check(self::ffi()->kouten_ring_configure($this->requireHandle(), $ring, $period));
    }

    public function setGalaxyDescription(string $description): void
    {
        $this->check(self::ffi()->kouten_set_galaxy_description($this->requireHandle(), $description));
    }

    public function setRingDescription(string $ring, string $description): void
    {
        $this->check(self::ffi()->kouten_set_ring_description($this->requireHandle(), $ring, $description));
    }

    public function put(string $ring, string $payload): KoutenId
    {
        $ffi = self::ffi();
        $id = $ffi->new('kouten_id');
        $this->check($ffi->kouten_put($this->requireHandle(), $ring, $payload, strlen($payload), FFI::addr($id)));
        return self::idFromC($id);
    }

    /** @param list<float|int> $vector */
    public function putVec(string $ring, string $payload, array $vector): KoutenId
    {
        $ffi = self::ffi();
        $id = $ffi->new('kouten_id');
        $vec = self::floatArray($vector);
        $vecPtr = count($vector) === 0 ? null : FFI::addr($vec[0]);
        $this->check($ffi->kouten_put_vec(
            $this->requireHandle(),
            $ring,
            $payload,
            strlen($payload),
            $vecPtr,
            count($vector),
            FFI::addr($id),
        ));
        return self::idFromC($id);
    }

    public function get(KoutenId $id): ?string
    {
        $ffi = self::ffi();
        $len = $ffi->new('size_t[1]');
        $ptr = $ffi->kouten_get($this->requireHandle(), self::idToC($id), FFI::addr($len[0]));
        if ($ptr === null) {
            $message = self::lastError()->getMessage();
            if (str_contains($message, 'not found')) {
                return null;
            }
            throw new RuntimeException($message);
        }
        try {
            return FFI::string($ptr, (int)$len[0]);
        } finally {
            $ffi->kouten_free($ptr);
        }
    }

    /** @param list<KoutenId> $ids @return list<string> */
    public function batchGet(array $ids): array
    {
        $ffi = self::ffi();
        $arr = $ffi->new('kouten_id[' . max(1, count($ids)) . ']');
        foreach ($ids as $i => $id) {
            $arr[$i] = self::idToC($id);
        }
        $res = $ffi->kouten_batch_get($this->requireHandle(), count($ids) === 0 ? null : FFI::addr($arr[0]), count($ids));
        if ($res === null) {
            throw self::lastError();
        }
        try {
            $out = [];
            for ($i = 0; $i < (int)$res->len; $i++) {
                $value = $res->values[$i];
                $out[] = $value->data === null ? '' : FFI::string($value->data, (int)$value->len);
            }
            return $out;
        } finally {
            $ffi->kouten_batch_get_free($res);
        }
    }

    public function query(KoutenId $id, string $selection): string
    {
        $ffi = self::ffi();
        $len = $ffi->new('size_t[1]');
        $ptr = $ffi->kouten_query($this->requireHandle(), self::idToC($id), $selection, FFI::addr($len[0]));
        if ($ptr === null) {
            throw self::lastError();
        }
        try {
            return FFI::string($ptr, (int)$len[0]);
        } finally {
            $ffi->kouten_free($ptr);
        }
    }

    /** @param list<float|int> $vector */
    public function retrieve(array $vector, string $ring = '', int $budget = 8, int $topRings = 0, int $focus = 0): RetrieveResult
    {
        $ffi = self::ffi();
        $vec = self::floatArray($vector);
        $res = $ffi->kouten_retrieve(
            $this->requireHandle(),
            count($vector) === 0 ? null : FFI::addr($vec[0]),
            count($vector),
            $ring,
            $budget,
            $topRings,
            $focus,
        );
        if ($res === null) {
            throw self::lastError();
        }
        try {
            $hits = [];
            for ($i = 0; $i < (int)$res->len; $i++) {
                $hit = $res->hits[$i];
                $hits[] = new KoutenHit(
                    self::idFromC($hit->id),
                    (float)$hit->score,
                    $hit->payload === null ? '' : FFI::string($hit->payload, (int)$hit->payload_len),
                );
            }
            return new RetrieveResult($hits, [
                'totalVectors' => (int)$res->total_vectors,
                'scanned' => (int)$res->scanned,
                'skippedVectors' => (int)$res->skipped_vectors,
                'returned' => (int)$res->returned,
                'ringsTouched' => (int)$res->rings_touched,
                'payloadBytes' => (int)$res->payload_bytes,
                'estimatedTokens' => (int)$res->estimated_tokens,
                'fanoutNodes' => (int)$res->fanout_nodes,
                'candidateReduction' => (float)$res->candidate_reduction,
            ]);
        } finally {
            $ffi->kouten_retrieve_free($res);
        }
    }

    /** @param list<float|int> $queryVector */
    public function atlas(array $queryVector = [], int $maxCentroidDims = 8): string
    {
        $ffi = self::ffi();
        $vec = self::floatArray($queryVector);
        $len = $ffi->new('size_t[1]');
        $ptr = $ffi->kouten_atlas(
            $this->requireHandle(),
            count($queryVector) === 0 ? null : FFI::addr($vec[0]),
            count($queryVector),
            $maxCentroidDims,
            FFI::addr($len[0]),
        );
        if ($ptr === null) {
            throw self::lastError();
        }
        try {
            return FFI::string($ptr, (int)$len[0]);
        } finally {
            $ffi->kouten_free($ptr);
        }
    }

    public function locate(KoutenId $id, float $at = -1.0): int
    {
        $node = self::ffi()->kouten_locate($this->requireHandle(), self::idToC($id), $at);
        if ($node < 0) {
            throw self::lastError();
        }
        return (int)$node;
    }

    public function nextVisit(KoutenId $id, int $node): float
    {
        $time = self::ffi()->kouten_next_visit($this->requireHandle(), self::idToC($id), $node);
        if ($time < 0) {
            throw self::lastError();
        }
        return (float)$time;
    }

    public function nextJoin(KoutenId $a, KoutenId $b): ?float
    {
        $time = self::ffi()->kouten_next_join($this->requireHandle(), self::idToC($a), self::idToC($b));
        return $time < 0 ? null : (float)$time;
    }

    private function check(int $code): void
    {
        if ($code !== 0) {
            throw self::lastError();
        }
    }

    private function requireHandle(): CData
    {
        if ($this->handle === null) {
            throw new RuntimeException('KoutenDB handle is closed');
        }
        return $this->handle;
    }

    /** @param list<float|int> $values */
    private static function floatArray(array $values): CData
    {
        $ffi = self::ffi();
        $arr = $ffi->new('float[' . max(1, count($values)) . ']');
        foreach ($values as $i => $value) {
            $arr[$i] = (float)$value;
        }
        return $arr;
    }

    private static function idToC(KoutenId $id): CData
    {
        $c = self::ffi()->new('kouten_id');
        $c->parent = $id->parent;
        $c->epoch = $id->epoch;
        $c->seq = $id->seq;
        $c->t_write = $id->tWrite;
        return $c;
    }

    private static function idFromC(CData $id): KoutenId
    {
        return new KoutenId((string)$id->parent, (int)$id->epoch, (int)$id->seq, (float)$id->t_write);
    }

    private static function lastError(): RuntimeException
    {
        $ptr = self::ffi()->kouten_last_error();
        $message = $ptr === null ? 'KoutenDB C ABI error' : FFI::string($ptr);
        return new RuntimeException($message === '' ? 'KoutenDB C ABI error' : $message);
    }

    private static function ffi(string $lib = __DIR__ . '/../../../lib/libkoutendb.so'): FFI
    {
        if (!class_exists(FFI::class)) {
            throw new RuntimeException('PHP FFI extension is not enabled');
        }
        if (self::$ffi === null) {
            self::$ffi = FFI::cdef(self::CDEF, $lib);
            self::$ffi->kouten_init();
            if ((int)self::$ffi->kouten_abi_version() !== self::ABI_VERSION) {
                throw new RuntimeException('KoutenDB ABI version mismatch');
            }
        }
        return self::$ffi;
    }

    private const CDEF = <<<'CDEF'
typedef unsigned long size_t;
typedef unsigned long uint64_t;
typedef unsigned int uint32_t;

typedef struct kouten_id {
  uint64_t parent;
  uint32_t epoch;
  uint32_t seq;
  double   t_write;
} kouten_id;

typedef struct kouten_hit {
  kouten_id id;
  double   score;
  void    *payload;
  size_t   payload_len;
} kouten_hit;

typedef struct kouten_retrieve_result {
  size_t     len;
  kouten_hit *hits;
  int        total_vectors;
  int        scanned;
  int        skipped_vectors;
  int        returned;
  int        rings_touched;
  int        payload_bytes;
  int        estimated_tokens;
  int        fanout_nodes;
  double     candidate_reduction;
} kouten_retrieve_result;

typedef struct kouten_value {
  void  *data;
  size_t len;
} kouten_value;

typedef struct kouten_batch_result {
  size_t       len;
  kouten_value *values;
} kouten_batch_result;

int         kouten_abi_version(void);
const char *kouten_last_error(void);
void        kouten_init(void);
void       *kouten_open(int nodes);
void       *kouten_open_dir(int nodes, const char *dir);
void       *kouten_connect_auth(const char *peers, const char *username, const char *password, const char *auth_token, const char *secret_key, const char *galaxy);
void        kouten_close(void *db);
int         kouten_ring_configure(void *db, const char *ring, double period);
int         kouten_set_galaxy_description(void *db, const char *description);
int         kouten_set_ring_description(void *db, const char *ring, const char *description);
int         kouten_put(void *db, const char *ring, const void *data, size_t len, kouten_id *out_id);
int         kouten_put_vec(void *db, const char *ring, const void *data, size_t len, const float *vec, size_t vec_len, kouten_id *out_id);
void       *kouten_get(void *db, kouten_id id, size_t *out_len);
void        kouten_free(void *p);
kouten_batch_result *kouten_batch_get(void *db, const kouten_id *ids, size_t ids_len);
void        kouten_batch_get_free(kouten_batch_result *r);
void       *kouten_query(void *db, kouten_id id, const char *selection, size_t *out_len);
kouten_retrieve_result *kouten_retrieve(void *db, const float *vec, size_t vec_len, const char *ring, int budget, int top_rings, int focus);
void        kouten_retrieve_free(kouten_retrieve_result *r);
void       *kouten_atlas(void *db, const float *query_vec, size_t query_vec_len, int max_centroid_dims, size_t *out_len);
int         kouten_locate(void *db, kouten_id id, double at);
double      kouten_next_visit(void *db, kouten_id id, int node);
double      kouten_next_join(void *db, kouten_id a, kouten_id b);
CDEF;
}
