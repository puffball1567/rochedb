using System.Runtime.InteropServices;
using System.Text;

namespace OrbeliasDB;

[StructLayout(LayoutKind.Sequential)]
public readonly struct OrbeliasId
{
    public readonly ulong Parent;
    public readonly uint Epoch;
    public readonly uint Seq;
    public readonly double TWrite;

    public OrbeliasId(ulong parent, uint epoch, uint seq, double tWrite)
    {
        Parent = parent;
        Epoch = epoch;
        Seq = seq;
        TWrite = tWrite;
    }
}

public readonly record struct OrbeliasHit(OrbeliasId Id, double Score, byte[] Payload);

public sealed class OrbeliasRetrieveResult
{
    public required IReadOnlyList<OrbeliasHit> Hits { get; init; }
    public int TotalVectors { get; init; }
    public int Scanned { get; init; }
    public int SkippedVectors { get; init; }
    public int Returned { get; init; }
    public int RingsTouched { get; init; }
    public int PayloadBytes { get; init; }
    public int EstimatedTokens { get; init; }
    public int FanoutNodes { get; init; }
    public double CandidateReduction { get; init; }
}

public sealed class OrbeliasDbException : Exception
{
    public OrbeliasDbException(string message) : base(message) { }
}

public sealed unsafe class OrbeliasDb : IDisposable
{
    private IntPtr _handle;
    private bool _disposed;

    private OrbeliasDb(IntPtr handle)
    {
        _handle = handle == IntPtr.Zero ? throw LastError("failed to open OrbeliasDB") : handle;
    }

    public static int AbiVersion => Native.orbelias_abi_version();

    public static OrbeliasDb Open(int nodes = 8)
    {
        Native.orbelias_init();
        return new OrbeliasDb(Native.orbelias_open(nodes));
    }

    public static OrbeliasDb OpenDir(string dir, int nodes = 8)
    {
        Native.orbelias_init();
        return new OrbeliasDb(Native.orbelias_open_dir(nodes, dir));
    }

    public static OrbeliasDb Connect(string peers)
    {
        Native.orbelias_init();
        return new OrbeliasDb(Native.orbelias_connect(peers));
    }

    public static OrbeliasDb ConnectAuth(
        string peers,
        string? username = null,
        string? password = null,
        string? authToken = null,
        string? secretKey = null,
        string? galaxy = null)
    {
        Native.orbelias_init();
        return new OrbeliasDb(Native.orbelias_connect_auth(peers, username, password, authToken, secretKey, galaxy));
    }

    public double Now => Native.orbelias_now(CheckedHandle);

    public void Advance(double dt) => Native.orbelias_advance(CheckedHandle, dt);

    public void ConfigureRing(string ring, double period)
    {
        if (Native.orbelias_ring_configure(CheckedHandle, ring, period) != Native.OrbeliasOk)
            throw LastError("failed to configure ring");
    }

    public void SetGalaxyDescription(string description)
    {
        if (Native.orbelias_set_galaxy_description(CheckedHandle, description) != Native.OrbeliasOk)
            throw LastError("failed to set galaxy description");
    }

    public void SetRingDescription(string ring, string description)
    {
        if (Native.orbelias_set_ring_description(CheckedHandle, ring, description) != Native.OrbeliasOk)
            throw LastError("failed to set ring description");
    }

    public OrbeliasId Put(string ring, string payload) => Put(ring, Encoding.UTF8.GetBytes(payload));

    public OrbeliasId Put(string ring, byte[] payload)
    {
        OrbeliasId id;
        fixed (byte* data = payload)
        {
            if (Native.orbelias_put(CheckedHandle, ring, data, (UIntPtr)payload.Length, &id) != Native.OrbeliasOk)
                throw LastError("put failed");
        }
        return id;
    }

    public OrbeliasId PutVec(string ring, string payload, ReadOnlySpan<float> vector) =>
        PutVec(ring, Encoding.UTF8.GetBytes(payload), vector);

    public OrbeliasId PutVec(string ring, byte[] payload, ReadOnlySpan<float> vector)
    {
        OrbeliasId id;
        fixed (byte* data = payload)
        fixed (float* vec = vector)
        {
            if (Native.orbelias_put_vec(CheckedHandle, ring, data, (UIntPtr)payload.Length, vec, (UIntPtr)vector.Length, &id) != Native.OrbeliasOk)
                throw LastError("putVec failed");
        }
        return id;
    }

    public byte[]? Get(OrbeliasId id)
    {
        UIntPtr len;
        IntPtr ptr = Native.orbelias_get(CheckedHandle, id, &len);
        return TakeBytes(ptr, len);
    }

    public string? GetString(OrbeliasId id)
    {
        byte[]? bytes = Get(id);
        return bytes is null ? null : Encoding.UTF8.GetString(bytes);
    }

    public IReadOnlyList<byte[]?> BatchGet(IReadOnlyList<OrbeliasId> ids)
    {
        OrbeliasId[] rawIds = ids.ToArray();
        fixed (OrbeliasId* ptr = rawIds)
        {
            IntPtr resultPtr = Native.orbelias_batch_get(CheckedHandle, ptr, (UIntPtr)rawIds.Length);
            if (resultPtr == IntPtr.Zero)
                throw LastError("batchGet failed");

            try
            {
                NativeBatchResult result = Marshal.PtrToStructure<NativeBatchResult>(resultPtr);
                var values = new List<byte[]?>((int)result.Len);
                var current = result.Values;
                int stride = Marshal.SizeOf<NativeValue>();
                for (nuint i = 0; i < result.Len; i++)
                {
                    NativeValue value = Marshal.PtrToStructure<NativeValue>(current);
                    values.Add(CopyBytes(value.Data, value.Len));
                    current += stride;
                }
                return values;
            }
            finally
            {
                Native.orbelias_batch_get_free(resultPtr);
            }
        }
    }

    public byte[]? Query(OrbeliasId id, string selection)
    {
        UIntPtr len;
        IntPtr ptr = Native.orbelias_query(CheckedHandle, id, selection, &len);
        return TakeBytes(ptr, len);
    }

    public string? QueryString(OrbeliasId id, string selection)
    {
        byte[]? bytes = Query(id, selection);
        return bytes is null ? null : Encoding.UTF8.GetString(bytes);
    }

    public OrbeliasRetrieveResult Retrieve(ReadOnlySpan<float> vector, string? ring = null, int budget = 10, int topRings = 50, int focus = 3)
    {
        fixed (float* vec = vector)
        {
            IntPtr resultPtr = Native.orbelias_retrieve(CheckedHandle, vec, (UIntPtr)vector.Length, ring, budget, topRings, focus);
            if (resultPtr == IntPtr.Zero)
                throw LastError("retrieve failed");

            try
            {
                NativeRetrieveResult native = Marshal.PtrToStructure<NativeRetrieveResult>(resultPtr);
                var hits = new List<OrbeliasHit>((int)native.Len);
                int stride = Marshal.SizeOf<NativeHit>();
                IntPtr current = native.Hits;
                for (nuint i = 0; i < native.Len; i++)
                {
                    NativeHit hit = Marshal.PtrToStructure<NativeHit>(current);
                    hits.Add(new OrbeliasHit(hit.Id, hit.Score, CopyBytes(hit.Payload, hit.PayloadLen) ?? Array.Empty<byte>()));
                    current += stride;
                }
                return new OrbeliasRetrieveResult
                {
                    Hits = hits,
                    TotalVectors = native.TotalVectors,
                    Scanned = native.Scanned,
                    SkippedVectors = native.SkippedVectors,
                    Returned = native.Returned,
                    RingsTouched = native.RingsTouched,
                    PayloadBytes = native.PayloadBytes,
                    EstimatedTokens = native.EstimatedTokens,
                    FanoutNodes = native.FanoutNodes,
                    CandidateReduction = native.CandidateReduction
                };
            }
            finally
            {
                Native.orbelias_retrieve_free(resultPtr);
            }
        }
    }

    public string Atlas(ReadOnlySpan<float> queryVector = default, int maxCentroidDims = 8)
    {
        fixed (float* vec = queryVector)
        {
            UIntPtr len;
            IntPtr ptr = Native.orbelias_atlas(CheckedHandle, vec, (UIntPtr)queryVector.Length, maxCentroidDims, &len);
            byte[]? bytes = TakeBytes(ptr, len);
            if (bytes is null)
                throw LastError("atlas failed");
            return Encoding.UTF8.GetString(bytes);
        }
    }

    public int Locate(OrbeliasId id, double at = -1.0) => Native.orbelias_locate(CheckedHandle, id, at);

    public double NextVisit(OrbeliasId id, int node) => Native.orbelias_next_visit(CheckedHandle, id, node);

    public double NextJoin(OrbeliasId a, OrbeliasId b) => Native.orbelias_next_join(CheckedHandle, a, b);

    public void Dispose()
    {
        if (_disposed)
            return;
        if (_handle != IntPtr.Zero)
        {
            Native.orbelias_close(_handle);
            _handle = IntPtr.Zero;
        }
        _disposed = true;
        GC.SuppressFinalize(this);
    }

    ~OrbeliasDb() => Dispose();

    private IntPtr CheckedHandle
    {
        get
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            return _handle;
        }
    }

    private static byte[]? TakeBytes(IntPtr ptr, UIntPtr len)
    {
        try
        {
            return CopyBytes(ptr, len);
        }
        finally
        {
            if (ptr != IntPtr.Zero)
                Native.orbelias_free(ptr);
        }
    }

    private static byte[]? CopyBytes(IntPtr ptr, UIntPtr len)
    {
        if (ptr == IntPtr.Zero)
            return null;
        int count = checked((int)len);
        var bytes = new byte[count];
        Marshal.Copy(ptr, bytes, 0, count);
        return bytes;
    }

    private static OrbeliasDbException LastError(string fallback)
    {
        IntPtr ptr = Native.orbelias_last_error();
        string? message = ptr == IntPtr.Zero ? null : Marshal.PtrToStringAnsi(ptr);
        return new OrbeliasDbException(string.IsNullOrWhiteSpace(message) ? fallback : message!);
    }
}

internal static partial class Native
{
    internal const int OrbeliasOk = 0;

    static Native()
    {
        NativeLibrary.SetDllImportResolver(typeof(Native).Assembly, Resolve);
    }

    private static IntPtr Resolve(string libraryName, System.Reflection.Assembly assembly, DllImportSearchPath? searchPath)
    {
        if (libraryName != "orbeliasdb")
            return IntPtr.Zero;

        string? configured = Environment.GetEnvironmentVariable("ORBELIASDB_NATIVE_LIB");
        if (!string.IsNullOrWhiteSpace(configured) && NativeLibrary.TryLoad(configured, out IntPtr configuredHandle))
            return configuredHandle;

        string? dir = AppContext.BaseDirectory;
        for (int i = 0; i < 10 && dir is not null; i++)
        {
            string candidate = Path.Combine(dir, "lib", "liborbeliasdb.so");
            if (File.Exists(candidate) && NativeLibrary.TryLoad(candidate, out IntPtr handle))
                return handle;

            candidate = Path.Combine(dir, "..", "lib", "liborbeliasdb.so");
            if (File.Exists(candidate) && NativeLibrary.TryLoad(Path.GetFullPath(candidate), out handle))
                return handle;

            dir = Directory.GetParent(dir)?.FullName;
        }

        return IntPtr.Zero;
    }

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int orbelias_abi_version();

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr orbelias_last_error();

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void orbelias_init();

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr orbelias_open(int nodes);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr orbelias_open_dir(int nodes, [MarshalAs(UnmanagedType.LPUTF8Str)] string dir);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr orbelias_connect([MarshalAs(UnmanagedType.LPUTF8Str)] string peers);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr orbelias_connect_auth(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string peers,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? username,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? password,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? authToken,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? secretKey,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? galaxy);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void orbelias_close(IntPtr db);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern double orbelias_now(IntPtr db);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void orbelias_advance(IntPtr db, double dt);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int orbelias_ring_configure(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, double period);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int orbelias_set_galaxy_description(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string description);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int orbelias_set_ring_description(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, [MarshalAs(UnmanagedType.LPUTF8Str)] string description);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe int orbelias_put(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, void* data, UIntPtr len, OrbeliasId* outId);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe int orbelias_put_vec(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, void* data, UIntPtr len, float* vec, UIntPtr vecLen, OrbeliasId* outId);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr orbelias_get(IntPtr db, OrbeliasId id, UIntPtr* outLen);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void orbelias_free(IntPtr p);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr orbelias_batch_get(IntPtr db, OrbeliasId* ids, UIntPtr idsLen);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void orbelias_batch_get_free(IntPtr result);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr orbelias_query(IntPtr db, OrbeliasId id, [MarshalAs(UnmanagedType.LPUTF8Str)] string selection, UIntPtr* outLen);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr orbelias_retrieve(IntPtr db, float* vec, UIntPtr vecLen, [MarshalAs(UnmanagedType.LPUTF8Str)] string? ring, int budget, int topRings, int focus);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void orbelias_retrieve_free(IntPtr result);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr orbelias_atlas(IntPtr db, float* queryVec, UIntPtr queryVecLen, int maxCentroidDims, UIntPtr* outLen);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int orbelias_locate(IntPtr db, OrbeliasId id, double at);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern double orbelias_next_visit(IntPtr db, OrbeliasId id, int node);

    [DllImport("orbeliasdb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern double orbelias_next_join(IntPtr db, OrbeliasId a, OrbeliasId b);
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeValue
{
    public IntPtr Data;
    public UIntPtr Len;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeBatchResult
{
    public UIntPtr Len;
    public IntPtr Values;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeHit
{
    public OrbeliasId Id;
    public double Score;
    public IntPtr Payload;
    public UIntPtr PayloadLen;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRetrieveResult
{
    public UIntPtr Len;
    public IntPtr Hits;
    public int TotalVectors;
    public int Scanned;
    public int SkippedVectors;
    public int Returned;
    public int RingsTouched;
    public int PayloadBytes;
    public int EstimatedTokens;
    public int FanoutNodes;
    public double CandidateReduction;
}

