package koutendb

import (
	"strings"
	"testing"
)

func TestEmbeddedRoundtripRetrieveAndAtlas(t *testing.T) {
	db, err := Open(8)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	if err := db.SetGalaxyDescription("Go test galaxy"); err != nil {
		t.Fatal(err)
	}
	if err := db.SetRingDescription("docs/go", "Go driver documents"); err != nil {
		t.Fatal(err)
	}
	if err := db.ConfigureRing("docs/go", 30.0); err != nil {
		t.Fatal(err)
	}

	id, err := db.PutVec("docs/go", []byte("hello go"), []float32{1, 0})
	if err != nil {
		t.Fatal(err)
	}
	value, ok, err := db.Get(id)
	if err != nil {
		t.Fatal(err)
	}
	if !ok || string(value) != "hello go" {
		t.Fatalf("unexpected get value ok=%v value=%q", ok, string(value))
	}

	values, err := db.BatchGet([]ID{id})
	if err != nil {
		t.Fatal(err)
	}
	if len(values) != 1 || string(values[0]) != "hello go" {
		t.Fatalf("unexpected batch values: %#v", values)
	}

	rr, err := db.Retrieve([]float32{1, 0}, "docs/go", 4, 0, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(rr.Hits) != 1 || rr.Stats.Scanned != 1 {
		t.Fatalf("unexpected retrieve result: %#v", rr)
	}

	atlas, err := db.Atlas([]float32{1, 0}, 8)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(atlas, "Go test galaxy") ||
		!strings.Contains(atlas, "Go driver documents") {
		t.Fatalf("atlas misses descriptions: %s", atlas)
	}

	node, err := db.Locate(id, -1)
	if err != nil {
		t.Fatal(err)
	}
	if node < 0 {
		t.Fatalf("invalid node: %d", node)
	}
	if _, err := db.NextVisit(id, node); err != nil {
		t.Fatal(err)
	}
}

func TestErrorFromCABI(t *testing.T) {
	db, err := Open(8)
	if err != nil {
		t.Fatal(err)
	}
	db.Close()

	if _, err := db.Put("docs", []byte("x")); err == nil {
		t.Fatal("expected an error after close")
	}
}
