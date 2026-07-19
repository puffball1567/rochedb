# OrbeliasDB C# Driver

Minimal C# binding for OrbeliasDB through the stable C ABI.

This package is intentionally generic. Unity-specific lifecycle, editor tooling,
asset packaging, and game-loop integration should live in a separate commercial
Unity asset.

## Requirements

- .NET 8 SDK
- `lib/liborbeliasdb.so` built from `src/orbeliasdb_capi.nim`

Build the native library from the repository root:

```sh
scripts/build_capi.sh
```

Run the smoke test:

```sh
dotnet run --project drivers/csharp/ContractSmoke/ContractSmoke.csproj
```

Set `ORBELIASDB_NATIVE_LIB=/absolute/path/to/liborbeliasdb.so` when the library is not
under the repository `lib/` directory.

## Status

Implemented:

- embedded open / openDir
- authenticated cluster connect
- put / putVec
- get / batchGet
- query / retrieve / atlas
- locate / nextVisit / nextJoin
- ring and galaxy descriptions

Planned:

- native TCP driver
- package publishing workflow
- expanded compatibility suite shared with the other language drivers

