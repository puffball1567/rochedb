## Payload format metadata shared by the embedded store and wire protocol.

import std/strutils

type
  PayloadCodec* = enum
    pcRaw
    pcJson
    pcNif
    pcBif

  EncodedPayload* = object
    data*: string
    codec*: PayloadCodec

  RingPayloadProfile* = object
    ## Ring-scoped declaration for applications and CLI tools. Individual
    ## records retain their own codec and remain authoritative.
    defaultCodec*: PayloadCodec
    charset*: string
    formatVersion*: string

  TimeOrbitProfile* = object
    ## Ring-scoped time-series placement declaration. The target coordinate is
    ## calculated from timestamp_ms, bucketMs, bits, and phase.
    bits*: int
    bucketMs*: int64
    phase*: uint64
    salt*: string

proc payloadCodecName*(codec: PayloadCodec): string =
  case codec
  of pcRaw: "raw"
  of pcJson: "json"
  of pcNif: "nif"
  of pcBif: "bif"

proc parsePayloadCodec*(value: string): PayloadCodec =
  case value.toLowerAscii()
  of "raw", "bytes", "application/octet-stream": pcRaw
  of "json", "application/json": pcJson
  of "nif", "application/nif": pcNif
  of "bif", "application/bif": pcBif
  else:
    raise newException(ValueError, "unsupported payload codec: " & value)

proc encodedPayload*(data: string, codec = pcRaw): EncodedPayload =
  EncodedPayload(data: data, codec: codec)

proc defaultRingPayloadProfile*(): RingPayloadProfile =
  RingPayloadProfile(defaultCodec: pcRaw, charset: "", formatVersion: "")

proc defaultTimeOrbitProfile*(): TimeOrbitProfile =
  TimeOrbitProfile(bits: 60, bucketMs: 60_000'i64, phase: 0'u64, salt: "")

proc supportsJsonProjection*(codec: PayloadCodec): bool =
  ## Raw remains projection-compatible for records written before codec metadata
  ## existed and for legacy drivers that already send JSON through PUTR.
  codec in {pcRaw, pcJson}
