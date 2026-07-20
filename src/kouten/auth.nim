## kouten/auth — libsodium-backed shared-secret challenge response.

import nimsodium

const
  AuthDomain = "koutendb-auth-v1"
  ChallengeBytes = 32

proc boxKey(secretKey: string): SecretBoxKey =
  secretBoxKeyFromBytes(genericHash(AuthDomain & "\0box\0" & secretKey,
                                    SecretBoxKeyBytes))

proc transportKey(secretKey, challengeHex: string): SecretBoxKey =
  secretBoxKeyFromBytes(genericHash(AuthDomain & "\0transport\0" &
                                    challengeHex & "\0" & secretKey,
                                    SecretBoxKeyBytes))

proc authMessage(username, password, challengeHex: string): string =
  AuthDomain & "\n" & username & "\n" & password & "\n" & challengeHex

proc secureEqual*(a, b: string): bool =
  ## Compare secret-like values without data-dependent early exit.
  var diff = a.len xor b.len
  let n = max(a.len, b.len)
  for i in 0 ..< n:
    let ca = if i < a.len: ord(a[i]) else: 0
    let cb = if i < b.len: ord(b[i]) else: 0
    diff = diff or (ca xor cb)
  diff == 0

proc newChallengeHex*(): string =
  randomBytes(ChallengeBytes).toHex

proc secretResponseHex*(username, password, challengeHex, secretKey: string): string =
  encryptSecretBox(authMessage(username, password, challengeHex),
                   boxKey(secretKey)).toHex

proc verifySecretResponse*(username, password, challengeHex, responseHex,
                           secretKey: string): bool =
  try:
    secureEqual(decryptSecretBox(fromHex(responseHex), boxKey(secretKey)),
                authMessage(username, password, challengeHex))
  except CatchableError:
    false

proc encryptTransportFrame*(plaintext, secretKey, challengeHex: string): string =
  encryptSecretBox(plaintext, transportKey(secretKey, challengeHex))

proc decryptTransportFrame*(ciphertext, secretKey, challengeHex: string): string =
  decryptSecretBox(ciphertext, transportKey(secretKey, challengeHex))
