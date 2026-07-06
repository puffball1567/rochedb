<?php
declare(strict_types=1);

require __DIR__ . '/../src/RocheDB.php';

use RocheDB\RocheDB;

function assert_true(bool $value, string $message): void
{
    if (!$value) {
        fwrite(STDERR, "FAIL: {$message}\n");
        exit(1);
    }
}

$db = RocheDB::open(8);
$db->setGalaxyDescription('PHP test galaxy');
$db->setRingDescription('docs/php', 'PHP driver documents');
$db->configureRing('docs/php', 30.0);

$id = $db->putVec('docs/php', 'hello php', [1.0, 0.0]);
assert_true($db->get($id) === 'hello php', 'get roundtrip');

$batch = $db->batchGet([$id]);
assert_true(count($batch) === 1 && $batch[0] === 'hello php', 'batch get');

$rr = $db->retrieve([1.0, 0.0], 'docs/php', 4);
assert_true(count($rr->hits) === 1, 'retrieve hit count');
assert_true($rr->stats['scanned'] === 1, 'retrieve scanned');

$atlas = $db->atlas([1.0, 0.0], 8);
assert_true(str_contains($atlas, 'PHP test galaxy'), 'atlas galaxy description');
assert_true(str_contains($atlas, 'PHP driver documents'), 'atlas ring description');

$node = $db->locate($id);
assert_true($node >= 0, 'locate');
assert_true($db->nextVisit($id, $node) >= 0.0, 'next visit');

$db->close();
echo "PHP driver OK\n";
