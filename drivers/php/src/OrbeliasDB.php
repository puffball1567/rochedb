<?php
declare(strict_types=1);

namespace OrbeliasDB;

use FFI;
use FFI\CData;
use RuntimeException;

final class OrbeliasId
{
    public function __construct(
        public readonly int|string $parent,
        public readonly int $epoch,
        public readonly int $seq,
        public readonly float $tWrite,
    ) {
    }
}

final class OrbeliasHit
{
    public function __construct(
        public readonly OrbeliasId $id,
        public readonly float $score,
        public readonly string $payload,
    ) {
    }
}

final class RetrieveResult
{
    /** @param list<OrbeliasHit> $hits */
    public function __construct(
        public readonly array $hits,
        public readonly array $stats,
    ) {
    }
}

final class OrbeliasDB
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

    public static function open(int $nodes = 8, string $lib = __DIR__ . '/../../../lib/liborbeliasdb.so'): self
    {
        $ffi = self::ffi($lib);
        $handle = $ffi->orbelias_open($nodes);
        if ($handle === null) {
            throw self::lastError();
        }
        return new self($handle);
    }

    public static function openDir(int $nodes, string $dir, string $lib = __DIR__ . '/../../../lib/liborbeliasdb.so'): self
    {
        $ffi = self::ffi($lib);
        $handle = $ffi->orbelias_open_dir($nodes, $dir);
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
        string $lib = __DIR__ . '/../../../lib/liborbeliasdb.so',
    ): self {
        $ffi = self::ffi($lib);
        $handle = $ffi->orbelias_connect_auth($peers, $username, $password, $authToken, $secretKey, $galaxy);
        if ($handle === null) {
            throw self::lastError();
        }
        return new self($handle);
    }

    public static function connect(string $peers, string $lib = __DIR__ . '/../../../lib/liborbeliasdb.so'): self
    {
        return self::connectAuth($peers, lib: $lib);
    }

    public function close(): void
    {
        if ($this->handle !== null) {
            self::ffi()->orbelias_close($this->handle);
            $this->handle = null;
        }
    }

    public function configureRing(string $ring, float $period): void
    {
        $this->check(self::ffi()->orbelias_ring_configure($this->requireHandle(), $ring, $period));
    }

    public function setGalaxyDescription(string $description): void
    {
        $this->check(self::ffi()->orbelias_set_galaxy_description($this->requireHandle(), $description));
    }

    public function setRingDescription(string $ring, string $description): void
    {
        $this->check(self::ffi()->orbelias_set_ring_description($this->requireHandle(), $ring, $description));
    }

    public function put(string $ring, string $payload): OrbeliasId
    {
        $ffi = self::ffi();
        $id = $ffi->new('orbelias_id');
        $this->check($ffi->orbelias_put($this->requireHandle(), $ring, $payload, strlen($payload), FFI::addr($id)));
        return self::idFromC($id);
    }

    /** @param list<float|int> $vector */
    public function putVec(string $ring, string $payload, array $vector): OrbeliasId
    {
        $ffi = self::ffi();
        $id = $ffi->new('orbelias_id');
        $vec = self::floatArray($vector);
        $vecPtr = count($vector) === 0 ? null : FFI::addr($vec[0]);
        $this->check($ffi->orbelias_put_vec(
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

    public function get(OrbeliasId $id): ?string
    {
        $ffi = self::ffi();
        $len = $ffi->new('size_t[1]');
        $ptr = $ffi->orbelias_get($this->requireHandle(), self::idToC($id), FFI::addr($len[0]));
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
            $ffi->orbelias_free($ptr);
        }
    }

    /** @param list<OrbeliasId> $ids @return list<string> */
    public function batchGet(array $ids): array
    {
        $ffi = self::ffi();
        $arr = $ffi->new('orbelias_id[' . max(1, count($ids)) . ']');
        foreach ($ids as $i => $id) {
            $arr[$i] = self::idToC($id);
        }
        $res = $ffi->orbelias_batch_get($this->requireHandle(), count($ids) === 0 ? null : FFI::addr($arr[0]), count($ids));
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
            $ffi->orbelias_batch_get_free($res);
        }
    }

    public function query(OrbeliasId $id, string $selection): string
    {
        $ffi = self::ffi();
        $len = $ffi->new('size_t[1]');
        $ptr = $ffi->orbelias_query($this->requireHandle(), self::idToC($id), $selection, FFI::addr($len[0]));
        if ($ptr === null) {
            throw self::lastError();
        }
        try {
            return FFI::string($ptr, (int)$len[0]);
        } finally {
            $ffi->orbelias_free($ptr);
        }
    }

    /** @param list<float|int> $vector */
    public function retrieve(array $vector, string $ring = '', int $budget = 8, int $topRings = 0, int $focus = 0): RetrieveResult
    {
        $ffi = self::ffi();
        $vec = self::floatArray($vector);
        $res = $ffi->orbelias_retrieve(
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
                $hits[] = new OrbeliasHit(
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
            $ffi->orbelias_retrieve_free($res);
        }
    }

    /** @param list<float|int> $queryVector */
    public function atlas(array $queryVector = [], int $maxCentroidDims = 8): string
    {
        $ffi = self::ffi();
        $vec = self::floatArray($queryVector);
        $len = $ffi->new('size_t[1]');
        $ptr = $ffi->orbelias_atlas(
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
            $ffi->orbelias_free($ptr);
        }
    }

    public function locate(OrbeliasId $id, float $at = -1.0): int
    {
        $node = self::ffi()->orbelias_locate($this->requireHandle(), self::idToC($id), $at);
        if ($node < 0) {
            throw self::lastError();
        }
        return (int)$node;
    }

    public function nextVisit(OrbeliasId $id, int $node): float
    {
        $time = self::ffi()->orbelias_next_visit($this->requireHandle(), self::idToC($id), $node);
        if ($time < 0) {
            throw self::lastError();
        }
        return (float)$time;
    }

    public function nextJoin(OrbeliasId $a, OrbeliasId $b): ?float
    {
        $time = self::ffi()->orbelias_next_join($this->requireHandle(), self::idToC($a), self::idToC($b));
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
            throw new RuntimeException('OrbeliasDB handle is closed');
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

    private static function idToC(OrbeliasId $id): CData
    {
        $c = self::ffi()->new('orbelias_id');
        $c->parent = $id->parent;
        $c->epoch = $id->epoch;
        $c->seq = $id->seq;
        $c->t_write = $id->tWrite;
        return $c;
    }

    private static function idFromC(CData $id): OrbeliasId
    {
        return new OrbeliasId((string)$id->parent, (int)$id->epoch, (int)$id->seq, (float)$id->t_write);
    }

    private static function lastError(): RuntimeException
    {
        $ptr = self::ffi()->orbelias_last_error();
        $message = $ptr === null ? 'OrbeliasDB C ABI error' : FFI::string($ptr);
        return new RuntimeException($message === '' ? 'OrbeliasDB C ABI error' : $message);
    }

    private static function ffi(string $lib = __DIR__ . '/../../../lib/liborbeliasdb.so'): FFI
    {
        if (!class_exists(FFI::class)) {
            throw new RuntimeException('PHP FFI extension is not enabled');
        }
        if (self::$ffi === null) {
            self::$ffi = FFI::cdef(self::CDEF, $lib);
            self::$ffi->orbelias_init();
            if ((int)self::$ffi->orbelias_abi_version() !== self::ABI_VERSION) {
                throw new RuntimeException('OrbeliasDB ABI version mismatch');
            }
        }
        return self::$ffi;
    }

    private const CDEF = <<<'CDEF'
typedef unsigned long size_t;
typedef unsigned long uint64_t;
typedef unsigned int uint32_t;

typedef struct orbelias_id {
  uint64_t parent;
  uint32_t epoch;
  uint32_t seq;
  double   t_write;
} orbelias_id;

typedef struct orbelias_hit {
  orbelias_id id;
  double   score;
  void    *payload;
  size_t   payload_len;
} orbelias_hit;

typedef struct orbelias_retrieve_result {
  size_t     len;
  orbelias_hit *hits;
  int        total_vectors;
  int        scanned;
  int        skipped_vectors;
  int        returned;
  int        rings_touched;
  int        payload_bytes;
  int        estimated_tokens;
  int        fanout_nodes;
  double     candidate_reduction;
} orbelias_retrieve_result;

typedef struct orbelias_value {
  void  *data;
  size_t len;
} orbelias_value;

typedef struct orbelias_batch_result {
  size_t       len;
  orbelias_value *values;
} orbelias_batch_result;

int         orbelias_abi_version(void);
const char *orbelias_last_error(void);
void        orbelias_init(void);
void       *orbelias_open(int nodes);
void       *orbelias_open_dir(int nodes, const char *dir);
void       *orbelias_connect_auth(const char *peers, const char *username, const char *password, const char *auth_token, const char *secret_key, const char *galaxy);
void        orbelias_close(void *db);
int         orbelias_ring_configure(void *db, const char *ring, double period);
int         orbelias_set_galaxy_description(void *db, const char *description);
int         orbelias_set_ring_description(void *db, const char *ring, const char *description);
int         orbelias_put(void *db, const char *ring, const void *data, size_t len, orbelias_id *out_id);
int         orbelias_put_vec(void *db, const char *ring, const void *data, size_t len, const float *vec, size_t vec_len, orbelias_id *out_id);
void       *orbelias_get(void *db, orbelias_id id, size_t *out_len);
void        orbelias_free(void *p);
orbelias_batch_result *orbelias_batch_get(void *db, const orbelias_id *ids, size_t ids_len);
void        orbelias_batch_get_free(orbelias_batch_result *r);
void       *orbelias_query(void *db, orbelias_id id, const char *selection, size_t *out_len);
orbelias_retrieve_result *orbelias_retrieve(void *db, const float *vec, size_t vec_len, const char *ring, int budget, int top_rings, int focus);
void        orbelias_retrieve_free(orbelias_retrieve_result *r);
void       *orbelias_atlas(void *db, const float *query_vec, size_t query_vec_len, int max_centroid_dims, size_t *out_len);
int         orbelias_locate(void *db, orbelias_id id, double at);
double      orbelias_next_visit(void *db, orbelias_id id, int node);
double      orbelias_next_join(void *db, orbelias_id a, orbelias_id b);
CDEF;
}
