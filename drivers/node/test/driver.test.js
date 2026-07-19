import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { OrbeliasClient, OrbeliasId } from "../src/index.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "../../..");
const peers = process.env.ORBELIAS_TEST_PEERS || "127.0.0.1:17931,127.0.0.1:17932";

function startNode(id) {
  return spawn(
    path.join(root, "src", "orbeliasd"),
    [`--id=${id}`, `--peers=${peers}`, "--slow-tick=1000"],
    { cwd: root, stdio: "inherit" }
  );
}

async function waitCluster(client) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    try {
      await client.health(0);
      await client.health(1);
      return;
    } catch (_err) {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error("orbeliasd test cluster did not start");
}

test("Node driver roundtrips", async (t) => {
  const procs = [startNode(0), startNode(1)];
  const client = OrbeliasClient.connect(peers, { timeoutMs: 1000 });
  t.after(async () => {
    await client.close();
    for (const proc of procs) {
      proc.kill("SIGTERM");
    }
  });

  await waitCluster(client);

  const id = await client.put(
    "japan/tokyo",
    Buffer.from('{"title":"Shinjuku","country":"JP"}'),
    { vector: [1.0, 0.0] }
  );

  assert.ok(id instanceof OrbeliasId);
  assert.equal(
    (await client.get(id)).toString("utf8"),
    '{"title":"Shinjuku","country":"JP"}'
  );
  assert.equal((await client.query(id, "{ title }")).toString("utf8"), '{"title":"Shinjuku"}');

  const textId = await client.put("tenant/acme/orders", "order-1");
  assert.deepEqual(OrbeliasId.parse(String(textId)), textId);
  assert.equal((await client.get(textId)).toString("utf8"), "order-1");
});
