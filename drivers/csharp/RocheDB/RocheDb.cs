using System.Runtime.InteropServices;
using System.Text;

namespace RocheDB;

[StructLayout(LayoutKind.Sequential)]
public readonly struct RocheId
{
    public readonly ulong Parent;
    public readonly uint Epoch;
    public readonly uint Seq;
    public readonly double TWrite;

    public RocheId(ulong parent, uint epoch, uint seq, double tWrite)
    {
        Parent = parent;
        Epoch = epoch;
        Seq = seq;
        TWrite = tWrite;
    }
}

public readonly record struct RocheHit(RocheId Id, double Score, byte[] Payload);

public sealed class RocheRetrieveResult
{
    public required IReadOnlyList<RocheHit> Hits { get; init; }
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

public sealed class RocheDbException : Exception
{
    public RocheDbException(string message) : base(message) { }
}

public sealed unsafe class RocheDb : IDisposable
{
    private IntPtr _handle;
    private bool _disposed;

    private RocheDb(IntPtr handle)
    {
        _handle = handle == IntPtr.Zero ? throw LastError("failed to open RocheDB") : handle;
    }

    public static int AbiVersion => Native.roche_abi_version();

    public static RocheDb Open(int nodes = 8)
    {
        Native.roche_init();
        return new RocheDb(Native.roche_open(nodes));
    }

    public static RocheDb OpenDir(string dir, int nodes = 8)
    {
        Native.roche_init();
        return new RocheDb(Native.roche_open_dir(nodes, dir));
    }

    public static RocheDb Connect(string peers)
    {
        Native.roche_init();
        return new RocheDb(Native.roche_connect(peers));
    }

    public static RocheDb ConnectAuth(
        string peers,
        string? username = null,
        string? password = null,
        string? authToken = null,
        string? secretKey = null,
        string? galaxy = null)
    {
        Native.roche_init();
        return new RocheDb(Native.roche_connect_auth(peers, username, password, authToken, secretKey, galaxy));
    }

    public double Now => Native.roche_now(CheckedHandle);

    public void Advance(double dt) => Native.roche_advance(CheckedHandle, dt);

    public void ConfigureRing(string ring, double period)
    {
        if (Native.roche_ring_configure(CheckedHandle, ring, period) != Native.RocheOk)
            throw LastError("failed to configure ring");
    }

    public void SetGalaxyDescription(string description)
    {
        if (Native.roche_set_galaxy_description(CheckedHandle, description) != Native.RocheOk)
            throw LastError("failed to set galaxy description");
    }

    public void SetRingDescription(string ring, string description)
    {
        if (Native.roche_set_ring_description(CheckedHandle, ring, description) != Native.RocheOk)
            throw LastError("failed to set ring description");
    }

    public RocheId Put(string ring, string payload) => Put(ring, Encoding.UTF8.GetBytes(payload));

    public RocheId Put(string ring, byte[] payload)
    {
        RocheId id;
        fixed (byte* data = payload)
        {
            if (Native.roche_put(CheckedHandle, ring, data, (UIntPtr)payload.Length, &id) != Native.RocheOk)
                throw LastError("put failed");
        }
        return id;
    }

    public RocheId PutVec(string ring, string payload, ReadOnlySpan<float> vector) =>
        PutVec(ring, Encoding.UTF8.GetBytes(payload), vector);

    public RocheId PutVec(string ring, byte[] payload, ReadOnlySpan<float> vector)
    {
        RocheId id;
        fixed (byte* data = payload)
        fixed (float* vec = vector)
        {
            if (Native.roche_put_vec(CheckedHandle, ring, data, (UIntPtr)payload.Length, vec, (UIntPtr)vector.Length, &id) != Native.RocheOk)
                throw LastError("putVec failed");
        }
        return id;
    }

    public byte[]? Get(RocheId id)
    {
        UIntPtr len;
        IntPtr ptr = Native.roche_get(CheckedHandle, id, &len);
        return TakeBytes(ptr, len);
    }

    public string? GetString(RocheId id)
    {
        byte[]? bytes = Get(id);
        return bytes is null ? null : Encoding.UTF8.GetString(bytes);
    }

    public IReadOnlyList<byte[]?> BatchGet(IReadOnlyList<RocheId> ids)
    {
        RocheId[] rawIds = ids.ToArray();
        fixed (RocheId* ptr = rawIds)
        {
            IntPtr resultPtr = Native.roche_batch_get(CheckedHandle, ptr, (UIntPtr)rawIds.Length);
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
                Native.roche_batch_get_free(resultPtr);
            }
        }
    }

    public byte[]? Query(RocheId id, string selection)
    {
        UIntPtr len;
        IntPtr ptr = Native.roche_query(CheckedHandle, id, selection, &len);
        return TakeBytes(ptr, len);
    }

    public string? QueryString(RocheId id, string selection)
    {
        byte[]? bytes = Query(id, selection);
        return bytes is null ? null : Encoding.UTF8.GetString(bytes);
    }

    public RocheRetrieveResult Retrieve(ReadOnlySpan<float> vector, string? ring = null, int budget = 10, int topRings = 50, int focus = 3)
    {
        fixed (float* vec = vector)
        {
            IntPtr resultPtr = Native.roche_retrieve(CheckedHandle, vec, (UIntPtr)vector.Length, ring, budget, topRings, focus);
            if (resultPtr == IntPtr.Zero)
                throw LastError("retrieve failed");

            try
            {
                NativeRetrieveResult native = Marshal.PtrToStructure<NativeRetrieveResult>(resultPtr);
                var hits = new List<RocheHit>((int)native.Len);
                int stride = Marshal.SizeOf<NativeHit>();
                IntPtr current = native.Hits;
                for (nuint i = 0; i < native.Len; i++)
                {
                    NativeHit hit = Marshal.PtrToStructure<NativeHit>(current);
                    hits.Add(new RocheHit(hit.Id, hit.Score, CopyBytes(hit.Payload, hit.PayloadLen) ?? Array.Empty<byte>()));
                    current += stride;
                }
                return new RocheRetrieveResult
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
                Native.roche_retrieve_free(resultPtr);
            }
        }
    }

    public string Atlas(ReadOnlySpan<float> queryVector = default, int maxCentroidDims = 8)
    {
        fixed (float* vec = queryVector)
        {
            UIntPtr len;
            IntPtr ptr = Native.roche_atlas(CheckedHandle, vec, (UIntPtr)queryVector.Length, maxCentroidDims, &len);
            byte[]? bytes = TakeBytes(ptr, len);
            if (bytes is null)
                throw LastError("atlas failed");
            return Encoding.UTF8.GetString(bytes);
        }
    }

    public int Locate(RocheId id, double at = -1.0) => Native.roche_locate(CheckedHandle, id, at);

    public double NextVisit(RocheId id, int node) => Native.roche_next_visit(CheckedHandle, id, node);

    public double NextJoin(RocheId a, RocheId b) => Native.roche_next_join(CheckedHandle, a, b);

    public void Dispose()
    {
        if (_disposed)
            return;
        if (_handle != IntPtr.Zero)
        {
            Native.roche_close(_handle);
            _handle = IntPtr.Zero;
        }
        _disposed = true;
        GC.SuppressFinalize(this);
    }

    ~RocheDb() => Dispose();

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
                Native.roche_free(ptr);
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

    private static RocheDbException LastError(string fallback)
    {
        IntPtr ptr = Native.roche_last_error();
        string? message = ptr == IntPtr.Zero ? null : Marshal.PtrToStringAnsi(ptr);
        return new RocheDbException(string.IsNullOrWhiteSpace(message) ? fallback : message!);
    }
}

internal static partial class Native
{
    internal const int RocheOk = 0;

    static Native()
    {
        NativeLibrary.SetDllImportResolver(typeof(Native).Assembly, Resolve);
    }

    private static IntPtr Resolve(string libraryName, System.Reflection.Assembly assembly, DllImportSearchPath? searchPath)
    {
        if (libraryName != "rochedb")
            return IntPtr.Zero;

        string? configured = Environment.GetEnvironmentVariable("ROCHEDB_NATIVE_LIB");
        if (!string.IsNullOrWhiteSpace(configured) && NativeLibrary.TryLoad(configured, out IntPtr configuredHandle))
            return configuredHandle;

        string? dir = AppContext.BaseDirectory;
        for (int i = 0; i < 10 && dir is not null; i++)
        {
            string candidate = Path.Combine(dir, "lib", "librochedb.so");
            if (File.Exists(candidate) && NativeLibrary.TryLoad(candidate, out IntPtr handle))
                return handle;

            candidate = Path.Combine(dir, "..", "lib", "librochedb.so");
            if (File.Exists(candidate) && NativeLibrary.TryLoad(Path.GetFullPath(candidate), out handle))
                return handle;

            dir = Directory.GetParent(dir)?.FullName;
        }

        return IntPtr.Zero;
    }

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int roche_abi_version();

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr roche_last_error();

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void roche_init();

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr roche_open(int nodes);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr roche_open_dir(int nodes, [MarshalAs(UnmanagedType.LPUTF8Str)] string dir);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr roche_connect([MarshalAs(UnmanagedType.LPUTF8Str)] string peers);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr roche_connect_auth(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string peers,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? username,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? password,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? authToken,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? secretKey,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? galaxy);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void roche_close(IntPtr db);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern double roche_now(IntPtr db);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void roche_advance(IntPtr db, double dt);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int roche_ring_configure(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, double period);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int roche_set_galaxy_description(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string description);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int roche_set_ring_description(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, [MarshalAs(UnmanagedType.LPUTF8Str)] string description);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe int roche_put(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, void* data, UIntPtr len, RocheId* outId);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe int roche_put_vec(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, void* data, UIntPtr len, float* vec, UIntPtr vecLen, RocheId* outId);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr roche_get(IntPtr db, RocheId id, UIntPtr* outLen);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void roche_free(IntPtr p);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr roche_batch_get(IntPtr db, RocheId* ids, UIntPtr idsLen);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void roche_batch_get_free(IntPtr result);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr roche_query(IntPtr db, RocheId id, [MarshalAs(UnmanagedType.LPUTF8Str)] string selection, UIntPtr* outLen);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr roche_retrieve(IntPtr db, float* vec, UIntPtr vecLen, [MarshalAs(UnmanagedType.LPUTF8Str)] string? ring, int budget, int topRings, int focus);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void roche_retrieve_free(IntPtr result);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr roche_atlas(IntPtr db, float* queryVec, UIntPtr queryVecLen, int maxCentroidDims, UIntPtr* outLen);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int roche_locate(IntPtr db, RocheId id, double at);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern double roche_next_visit(IntPtr db, RocheId id, int node);

    [DllImport("rochedb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern double roche_next_join(IntPtr db, RocheId a, RocheId b);
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
    public RocheId Id;
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

