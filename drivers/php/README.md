# RocheDB PHP Driver

Minimal PHP FFI wrapper over the RocheDB C ABI.

```php
<?php
use RocheDB\RocheDB;

$db = RocheDB::open(8);
$db->setGalaxyDescription("Product and support knowledge");
$db->setRingDescription("docs", "Documentation ring");

$id = $db->putVec("docs", "hello", [1.0, 0.0]);
$value = $db->get($id);
$atlas = $db->atlas([1.0, 0.0], 8);
$db->close();
```

Build the RocheDB shared library first:

```bash
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
drivers/php/docker-test.sh
```

Local PHP must have `ext-ffi` enabled. If it does not, use `drivers/php/docker-test.sh`;
it builds a small `php:8.3-cli` based image with FFI enabled.
