# OrbeliasDB PHP Driver

Minimal PHP FFI wrapper over the OrbeliasDB C ABI.

```php
<?php
use OrbeliasDB\OrbeliasDB;

$db = OrbeliasDB::open(8);
$db->setGalaxyDescription("Product and support knowledge");
$db->setRingDescription("docs", "Documentation ring");

$id = $db->putVec("docs", "hello", [1.0, 0.0]);
$value = $db->get($id);
$atlas = $db->atlas([1.0, 0.0], 8);
$db->close();
```

Build the OrbeliasDB shared library first:

```bash
scripts/build_capi.sh
drivers/php/docker-test.sh
```

The build script enables TLS support in `lib/liborbeliasdb.so`, which is required
for `orbelias_connect_auth_tls`-based drivers.

Local PHP must have `ext-ffi` enabled. If it does not, use `drivers/php/docker-test.sh`;
it builds a small `php:8.3-cli` based image with FFI enabled.
