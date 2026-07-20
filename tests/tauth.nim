## kouten/auth の安全比較テスト

import std/unittest
import ../src/kouten/auth

suite "auth helpers":
  test "secureEqual matches equal strings":
    check secureEqual("secret", "secret")
    check secureEqual("", "")

  test "secureEqual rejects unequal strings and length mismatches":
    check not secureEqual("secret", "secreu")
    check not secureEqual("secret", "secret!")
    check not secureEqual("", "x")

  test "secret challenge response verifies only with matching inputs":
    let challenge = newChallengeHex()
    let response = secretResponseHex("alice", "password", challenge, "secret-key")
    check verifySecretResponse("alice", "password", challenge, response, "secret-key")
    check not verifySecretResponse("alice", "wrong", challenge, response, "secret-key")
    check not verifySecretResponse("alice", "password", challenge, response, "wrong-key")
