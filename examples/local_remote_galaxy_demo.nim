import std/[json, os, strformat]
import ../src/koutendb

proc env(name, fallback: string): string =
  result = getEnv(name)
  if result.len == 0:
    result = fallback

proc exercise(label, peers, galaxy, username, password, secretKey, ring: string) =
  var db = connect(peers, username = username, password = password,
                   secretKey = secretKey, galaxy = galaxy)
  let id = db.put(%*{
    "placement": label,
    "galaxy": galaxy,
    "ring": ring,
    "message": "local/remote galaxy routing works"
  }, ring = ring)
  let projected = db.query(id, "{ placement galaxy ring message }")
  echo &"[{label}] peers={peers} galaxy={galaxy} ring={ring}"
  echo "  -> ", projected
  db.close()

when isMainModule:
  exercise("training local",
           env("KOUTEN_TRAINING_LOCAL", "127.0.0.1:18411"),
           "training-data", "train",
           env("KOUTEN_TRAIN_PASSWORD", "train-pass"),
           env("KOUTEN_TRAIN_SECRET_KEY", "train-secret-key"),
           "ai/training/japan")

  exercise("training remote",
           env("KOUTEN_TRAINING_REMOTE", "127.0.0.1:18412"),
           "training-data", "train",
           env("KOUTEN_TRAIN_PASSWORD", "train-pass"),
           env("KOUTEN_TRAIN_SECRET_KEY", "train-secret-key"),
           "ai/training/oregon")

  exercise("prompt-cache local",
           env("KOUTEN_CACHE_LOCAL", "127.0.0.1:18421"),
           "prompt-cache", "cache",
           env("KOUTEN_CACHE_PASSWORD", "cache-pass"),
           env("KOUTEN_CACHE_SECRET_KEY", "cache-secret-key"),
           "app/session/local")

  exercise("prompt-cache remote",
           env("KOUTEN_CACHE_REMOTE", "127.0.0.1:18422"),
           "prompt-cache", "cache",
           env("KOUTEN_CACHE_PASSWORD", "cache-pass"),
           env("KOUTEN_CACHE_SECRET_KEY", "cache-secret-key"),
           "app/session/remote")

  echo ""
  echo "OK: the demo used the same galaxy names through different local/remote endpoints."
