package koutendb

/*
#cgo CFLAGS: -I${SRCDIR}/../../include
#cgo LDFLAGS: -L${SRCDIR}/../../lib -Wl,-rpath,${SRCDIR}/../../lib -lkoutendb
#include <stdlib.h>
#include "koutendb.h"
*/
import "C"

import (
	"errors"
	"fmt"
	"runtime"
	"sync"
	"unsafe"
)

const ABIVersion = 2

var initOnce sync.Once

type ID struct {
	Parent uint64
	Epoch  uint32
	Seq    uint32
	TWrite float64
}

type DB struct {
	raw unsafe.Pointer
}

type Hit struct {
	ID      ID
	Score   float64
	Payload []byte
}

type RetrieveStats struct {
	TotalVectors       int
	Scanned            int
	SkippedVectors     int
	Returned           int
	RingsTouched       int
	PayloadBytes       int
	EstimatedTokens    int
	FanoutNodes        int
	CandidateReduction float64
}

type RetrieveResult struct {
	Hits  []Hit
	Stats RetrieveStats
}

func initRuntime() error {
	initOnce.Do(func() {
		C.kouten_init()
	})
	if int(C.kouten_abi_version()) != ABIVersion {
		return fmt.Errorf("koutendb ABI version mismatch: expected %d, got %d",
			ABIVersion, int(C.kouten_abi_version()))
	}
	return nil
}

func lastError() error {
	msg := C.kouten_last_error()
	if msg == nil {
		return errors.New("koutendb C ABI error")
	}
	text := C.GoString(msg)
	if text == "" {
		return errors.New("koutendb C ABI error")
	}
	return errors.New(text)
}

func Open(nodes int) (*DB, error) {
	if err := initRuntime(); err != nil {
		return nil, err
	}
	raw := C.kouten_open(C.int(nodes))
	return dbFromRaw(raw)
}

func OpenDir(nodes int, dir string) (*DB, error) {
	if err := initRuntime(); err != nil {
		return nil, err
	}
	cdir := C.CString(dir)
	defer C.free(unsafe.Pointer(cdir))
	raw := C.kouten_open_dir(C.int(nodes), cdir)
	return dbFromRaw(raw)
}

func Connect(peers string) (*DB, error) {
	return ConnectAuth(peers, "", "", "", "", "")
}

func ConnectAuth(peers, username, password, authToken, secretKey, galaxy string) (*DB, error) {
	if err := initRuntime(); err != nil {
		return nil, err
	}
	cpeers := C.CString(peers)
	cusername := C.CString(username)
	cpassword := C.CString(password)
	cauthToken := C.CString(authToken)
	csecretKey := C.CString(secretKey)
	cgalaxy := C.CString(galaxy)
	defer C.free(unsafe.Pointer(cpeers))
	defer C.free(unsafe.Pointer(cusername))
	defer C.free(unsafe.Pointer(cpassword))
	defer C.free(unsafe.Pointer(cauthToken))
	defer C.free(unsafe.Pointer(csecretKey))
	defer C.free(unsafe.Pointer(cgalaxy))
	raw := C.kouten_connect_auth(cpeers, cusername, cpassword, cauthToken, csecretKey, cgalaxy)
	return dbFromRaw(raw)
}

func dbFromRaw(raw unsafe.Pointer) (*DB, error) {
	if raw == nil {
		return nil, lastError()
	}
	db := &DB{raw: raw}
	runtime.SetFinalizer(db, (*DB).Close)
	return db, nil
}

func (db *DB) Close() {
	if db == nil || db.raw == nil {
		return
	}
	C.kouten_close(db.raw)
	db.raw = nil
	runtime.SetFinalizer(db, nil)
}

func (db *DB) Now() float64 {
	return float64(C.kouten_now(db.raw))
}

func (db *DB) Advance(dt float64) {
	C.kouten_advance(db.raw, C.double(dt))
}

func (db *DB) ConfigureRing(ring string, period float64) error {
	cring := C.CString(ring)
	defer C.free(unsafe.Pointer(cring))
	if C.kouten_ring_configure(db.raw, cring, C.double(period)) != C.KOUTEN_OK {
		return lastError()
	}
	return nil
}

func (db *DB) SetGalaxyDescription(description string) error {
	cdesc := C.CString(description)
	defer C.free(unsafe.Pointer(cdesc))
	if C.kouten_set_galaxy_description(db.raw, cdesc) != C.KOUTEN_OK {
		return lastError()
	}
	return nil
}

func (db *DB) SetRingDescription(ring, description string) error {
	cring := C.CString(ring)
	cdesc := C.CString(description)
	defer C.free(unsafe.Pointer(cring))
	defer C.free(unsafe.Pointer(cdesc))
	if C.kouten_set_ring_description(db.raw, cring, cdesc) != C.KOUTEN_OK {
		return lastError()
	}
	return nil
}

func (db *DB) Put(ring string, payload []byte) (ID, error) {
	cring := C.CString(ring)
	defer C.free(unsafe.Pointer(cring))
	var out C.kouten_id
	if C.kouten_put(db.raw, cring, bytesPtr(payload), C.size_t(len(payload)), &out) != C.KOUTEN_OK {
		return ID{}, lastError()
	}
	return idFromC(out), nil
}

func (db *DB) PutVec(ring string, payload []byte, vec []float32) (ID, error) {
	cring := C.CString(ring)
	defer C.free(unsafe.Pointer(cring))
	var out C.kouten_id
	if C.kouten_put_vec(db.raw, cring, bytesPtr(payload), C.size_t(len(payload)),
		floatPtr(vec), C.size_t(len(vec)), &out) != C.KOUTEN_OK {
		return ID{}, lastError()
	}
	return idFromC(out), nil
}

func (db *DB) Get(id ID) ([]byte, bool, error) {
	var n C.size_t
	p := C.kouten_get(db.raw, idToC(id), &n)
	if p == nil {
		err := lastError()
		if err != nil && (err.Error() == "key not found" || err.Error() == "not found") {
			return nil, false, nil
		}
		return nil, false, err
	}
	defer C.kouten_free(p)
	return C.GoBytes(p, C.int(n)), true, nil
}

func (db *DB) BatchGet(ids []ID) ([][]byte, error) {
	cids := make([]C.kouten_id, len(ids))
	for i, id := range ids {
		cids[i] = idToC(id)
	}
	var ptr *C.kouten_id
	if len(cids) > 0 {
		ptr = &cids[0]
	}
	r := C.kouten_batch_get(db.raw, ptr, C.size_t(len(cids)))
	if r == nil {
		return nil, lastError()
	}
	defer C.kouten_batch_get_free(r)
	values := unsafe.Slice(r.values, int(r.len))
	out := make([][]byte, len(values))
	for i, value := range values {
		if value.data != nil && value.len > 0 {
			out[i] = C.GoBytes(value.data, C.int(value.len))
		} else {
			out[i] = []byte{}
		}
	}
	return out, nil
}

func (db *DB) Query(id ID, selection string) ([]byte, error) {
	csel := C.CString(selection)
	defer C.free(unsafe.Pointer(csel))
	var n C.size_t
	p := C.kouten_query(db.raw, idToC(id), csel, &n)
	if p == nil {
		return nil, lastError()
	}
	defer C.kouten_free(p)
	return C.GoBytes(p, C.int(n)), nil
}

func (db *DB) Retrieve(vec []float32, ring string, budget, topRings, focus int) (RetrieveResult, error) {
	cring := C.CString(ring)
	defer C.free(unsafe.Pointer(cring))
	r := C.kouten_retrieve(db.raw, floatPtr(vec), C.size_t(len(vec)), cring,
		C.int(budget), C.int(topRings), C.int(focus))
	if r == nil {
		return RetrieveResult{}, lastError()
	}
	defer C.kouten_retrieve_free(r)
	rawHits := unsafe.Slice(r.hits, int(r.len))
	hits := make([]Hit, len(rawHits))
	for i, h := range rawHits {
		hits[i] = Hit{
			ID:      idFromC(h.id),
			Score:   float64(h.score),
			Payload: C.GoBytes(h.payload, C.int(h.payload_len)),
		}
	}
	return RetrieveResult{
		Hits: hits,
		Stats: RetrieveStats{
			TotalVectors:       int(r.total_vectors),
			Scanned:            int(r.scanned),
			SkippedVectors:     int(r.skipped_vectors),
			Returned:           int(r.returned),
			RingsTouched:       int(r.rings_touched),
			PayloadBytes:       int(r.payload_bytes),
			EstimatedTokens:    int(r.estimated_tokens),
			FanoutNodes:        int(r.fanout_nodes),
			CandidateReduction: float64(r.candidate_reduction),
		},
	}, nil
}

func (db *DB) Atlas(queryVec []float32, maxCentroidDims int) (string, error) {
	var n C.size_t
	p := C.kouten_atlas(db.raw, floatPtr(queryVec), C.size_t(len(queryVec)),
		C.int(maxCentroidDims), &n)
	if p == nil {
		return "", lastError()
	}
	defer C.kouten_free(p)
	return string(C.GoBytes(p, C.int(n))), nil
}

func (db *DB) Locate(id ID, at float64) (int, error) {
	node := C.kouten_locate(db.raw, idToC(id), C.double(at))
	if node < 0 {
		return -1, lastError()
	}
	return int(node), nil
}

func (db *DB) NextVisit(id ID, node int) (float64, error) {
	t := C.kouten_next_visit(db.raw, idToC(id), C.int(node))
	if t < 0 {
		return -1, lastError()
	}
	return float64(t), nil
}

func (db *DB) NextJoin(a, b ID) (float64, bool, error) {
	t := C.kouten_next_join(db.raw, idToC(a), idToC(b))
	if t < 0 {
		return -1, false, nil
	}
	return float64(t), true, nil
}

func bytesPtr(b []byte) unsafe.Pointer {
	if len(b) == 0 {
		return nil
	}
	return unsafe.Pointer(&b[0])
}

func floatPtr(v []float32) *C.float {
	if len(v) == 0 {
		return nil
	}
	return (*C.float)(unsafe.Pointer(&v[0]))
}

func idToC(id ID) C.kouten_id {
	return C.kouten_id{
		parent:  C.uint64_t(id.Parent),
		epoch:   C.uint32_t(id.Epoch),
		seq:     C.uint32_t(id.Seq),
		t_write: C.double(id.TWrite),
	}
}

func idFromC(id C.kouten_id) ID {
	return ID{
		Parent: uint64(id.parent),
		Epoch:  uint32(id.epoch),
		Seq:    uint32(id.seq),
		TWrite: float64(id.t_write),
	}
}
