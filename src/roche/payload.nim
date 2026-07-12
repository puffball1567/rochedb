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

proc supportsJsonProjection*(codec: PayloadCodec): bool =
  ## Raw remains projection-compatible for records written before codec metadata
  ## existed and for legacy drivers that already send JSON through PUTR.
  codec in {pcRaw, pcJson}
