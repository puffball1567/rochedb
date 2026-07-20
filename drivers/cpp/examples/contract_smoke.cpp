#include <cassert>
#include <iostream>
#include <string>
#include <vector>

#include "koutendb/koutendb.hpp"

int main() {
  assert(koutendb::abiVersion() == KOUTEN_ABI_VERSION);

  auto db = koutendb::Db::open(4);
  db.configureRing("docs", 45.0);
  db.setGalaxyDescription("Smoke-test galaxy for C++ binding.");
  db.setRingDescription("docs", "Documents used by the C++ binding smoke test.");

  koutendb::Id first = db.put("docs", R"({"title":"alpha","body":"hello"})");
  koutendb::Id second =
      db.putVec("docs", R"({"title":"beta","body":"vector"})",
                std::vector<float>{0.9f, 0.1f, 0.2f});

  auto got = db.getString(first);
  assert(got.has_value());
  assert(got->find("alpha") != std::string::npos);

  auto projected = db.queryString(first, "{ title }");
  assert(projected.has_value());
  assert(*projected == R"({"title":"alpha"})");

  auto batch = db.batchGet(std::vector<koutendb::Id>{first, second});
  assert(batch.size() == 2);
  assert(batch[1].has_value());

  auto result = db.retrieve(std::vector<float>{1.0f, 0.0f, 0.0f}, "docs", 5, 50, 3);
  assert(result.returned >= 1);
  assert(result.scanned >= result.returned);

  std::string atlas = db.atlas(std::vector<float>{1.0f, 0.0f, 0.0f});
  assert(atlas.find("galaxyMap") != std::string::npos);
  assert(atlas.find("Documents used by the C++ binding smoke test.") !=
         std::string::npos);

  int located = db.locate(first);
  assert(located >= 0);
  assert(db.nextVisit(first, located) >= 0.0);
  assert(db.nextJoin(first, second) >= -1.0);

  std::cout << "C++ driver OK\n";
  return 0;
}
