using OrbeliasDB;

static void Check(bool condition, string message)
{
    if (!condition)
        throw new Exception(message);
}

using var db = OrbeliasDb.Open(4);
Check(OrbeliasDb.AbiVersion == 2, "unexpected ABI version");

db.ConfigureRing("docs", 45.0);
db.SetGalaxyDescription("Smoke-test galaxy for C# binding.");
db.SetRingDescription("docs", "Documents used by the C# binding smoke test.");

OrbeliasId first = db.Put("docs", "{\"title\":\"alpha\",\"body\":\"hello\"}");
OrbeliasId second = db.PutVec("docs", "{\"title\":\"beta\",\"body\":\"vector\"}", stackalloc float[] { 0.9f, 0.1f, 0.2f });

Check(db.GetString(first)?.Contains("alpha") == true, "get failed");
Check(db.QueryString(first, "{ title }") == "{\"title\":\"alpha\"}", "query failed");

IReadOnlyList<byte[]?> batch = db.BatchGet(new[] { first, second });
Check(batch.Count == 2, "batch count failed");
Check(batch[1] is not null && System.Text.Encoding.UTF8.GetString(batch[1]!).Contains("beta"), "batch value failed");

OrbeliasRetrieveResult result = db.Retrieve(stackalloc float[] { 1.0f, 0.0f, 0.0f }, ring: "docs", budget: 5, topRings: 50, focus: 3);
Check(result.Returned >= 1, "retrieve returned no hits");
Check(result.Scanned >= result.Returned, "retrieve stats inconsistent");

string atlas = db.Atlas(stackalloc float[] { 1.0f, 0.0f, 0.0f });
Check(atlas.Contains("galaxyMap"), "atlas missing galaxyMap");
Check(atlas.Contains("Documents used by the C# binding smoke test."), "atlas missing ring description");

int located = db.Locate(first);
Check(located >= 0, "locate failed");
Check(db.NextVisit(first, located) >= 0.0, "nextVisit failed");
Check(db.NextJoin(first, second) >= -1.0, "nextJoin failed");

Console.WriteLine("C# driver OK");
