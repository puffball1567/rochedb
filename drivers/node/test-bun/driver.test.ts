import { expect, test } from "bun:test";
import { type ChildProcess, spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { KoutenClient, KoutenId } from "../src/index.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "../../..");
const peers = process.env.KOUTEN_TEST_PEERS || "127.0.0.1:17941,127.0.0.1:17942";

function startNode(id: number): ChildProcess {
  return spawn(
    path.join(root, "src", "koutend"),
    [`--id=${id}`, `--peers=${peers}`, "--slow-tick=1000"],
    { cwd: root, stdio: "inherit" }
  );
}

async function waitCluster(client: InstanceType<typeof KoutenClient>): Promise<void> {
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
  throw new Error("koutend test cluster did not start");
}

test("Bun driver roundtrips through the Node-compatible wire driver", async () => {
  const procs = [startNode(0), startNode(1)];
  const client = KoutenClient.connect(peers, { timeoutMs: 1000 });
  try {
    await waitCluster(client);

    const id = await client.put(
      "client/bun/context",
      Buffer.from('{"title":"Bun context"}'),
      { vector: [1.0, 0.0] }
    );

    expect(id).toBeInstanceOf(KoutenId);
    expect((await client.get(id)).toString("utf8")).toBe('{"title":"Bun context"}');
    expect((await client.query(id, "{ title }")).toString("utf8")).toBe(
      '{"title":"Bun context"}'
    );

    const textId = await client.put("client/bun/session", "local context");
    expect(KoutenId.parse(String(textId))).toEqual(textId);
    expect((await client.get(textId)).toString("utf8")).toBe("local context");
  } finally {
    await client.close();
    for (const proc of procs) {
      proc.kill("SIGTERM");
    }
  }
});
