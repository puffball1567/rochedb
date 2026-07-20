using System.Runtime.InteropServices;
using System.Text;

namespace KoutenDB;

[StructLayout(LayoutKind.Sequential)]
public readonly struct KoutenId
{
    public readonly ulong Parent;
    public readonly uint Epoch;
    public readonly uint Seq;
    public readonly double TWrite;

    public KoutenId(ulong parent, uint epoch, uint seq, double tWrite)
    {
        Parent = parent;
        Epoch = epoch;
        Seq = seq;
        TWrite = tWrite;
    }
}

public readonly record struct KoutenHit(KoutenId Id, double Score, byte[] Payload);

public sealed class KoutenRetrieveResult
{
    public required IReadOnlyList<KoutenHit> Hits { get; init; }
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

public sealed class KoutenDbException : Exception
{
    public KoutenDbException(string message) : base(message) { }
}

public sealed unsafe class KoutenDb : IDisposable
{
    private IntPtr _handle;
    private bool _disposed;

    private KoutenDb(IntPtr handle)
    {
        _handle = handle == IntPtr.Zero ? throw LastError("failed to open KoutenDB") : handle;
    }

    public static int AbiVersion => Native.kouten_abi_version();

    public static KoutenDb Open(int nodes = 8)
    {
        Native.kouten_init();
        return new KoutenDb(Native.kouten_open(nodes));
    }

    public static KoutenDb OpenDir(string dir, int nodes = 8)
    {
        Native.kouten_init();
        return new KoutenDb(Native.kouten_open_dir(nodes, dir));
    }

    public static KoutenDb Connect(string peers)
    {
        Native.kouten_init();
        return new KoutenDb(Native.kouten_connect(peers));
    }

    public static KoutenDb ConnectAuth(
        string peers,
        string? username = null,
        string? password = null,
        string? authToken = null,
        string? secretKey = null,
        string? galaxy = null)
    {
        Native.kouten_init();
        return new KoutenDb(Native.kouten_connect_auth(peers, username, password, authToken, secretKey, galaxy));
    }

    public double Now => Native.kouten_now(CheckedHandle);

    public void Advance(double dt) => Native.kouten_advance(CheckedHandle, dt);

    public void ConfigureRing(string ring, double period)
    {
        if (Native.kouten_ring_configure(CheckedHandle, ring, period) != Native.KoutenOk)
            throw LastError("failed to configure ring");
    }

    public void SetGalaxyDescription(string description)
    {
        if (Native.kouten_set_galaxy_description(CheckedHandle, description) != Native.KoutenOk)
            throw LastError("failed to set galaxy description");
    }

    public void SetRingDescription(string ring, string description)
    {
        if (Native.kouten_set_ring_description(CheckedHandle, ring, description) != Native.KoutenOk)
            throw LastError("failed to set ring description");
    }

    public KoutenId Put(string ring, string payload) => Put(ring, Encoding.UTF8.GetBytes(payload));

    public KoutenId Put(string ring, byte[] payload)
    {
        KoutenId id;
        fixed (byte* data = payload)
        {
            if (Native.kouten_put(CheckedHandle, ring, data, (UIntPtr)payload.Length, &id) != Native.KoutenOk)
                throw LastError("put failed");
        }
        return id;
    }

    public KoutenId PutVec(string ring, string payload, ReadOnlySpan<float> vector) =>
        PutVec(ring, Encoding.UTF8.GetBytes(payload), vector);

    public KoutenId PutVec(string ring, byte[] payload, ReadOnlySpan<float> vector)
    {
        KoutenId id;
        fixed (byte* data = payload)
        fixed (float* vec = vector)
        {
            if (Native.kouten_put_vec(CheckedHandle, ring, data, (UIntPtr)payload.Length, vec, (UIntPtr)vector.Length, &id) != Native.KoutenOk)
                throw LastError("putVec failed");
        }
        return id;
    }

    public byte[]? Get(KoutenId id)
    {
        UIntPtr len;
        IntPtr ptr = Native.kouten_get(CheckedHandle, id, &len);
        return TakeBytes(ptr, len);
    }

    public string? GetString(KoutenId id)
    {
        byte[]? bytes = Get(id);
        return bytes is null ? null : Encoding.UTF8.GetString(bytes);
    }

    public IReadOnlyList<byte[]?> BatchGet(IReadOnlyList<KoutenId> ids)
    {
        KoutenId[] rawIds = ids.ToArray();
        fixed (KoutenId* ptr = rawIds)
        {
            IntPtr resultPtr = Native.kouten_batch_get(CheckedHandle, ptr, (UIntPtr)rawIds.Length);
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
                Native.kouten_batch_get_free(resultPtr);
            }
        }
    }

    public byte[]? Query(KoutenId id, string selection)
    {
        UIntPtr len;
        IntPtr ptr = Native.kouten_query(CheckedHandle, id, selection, &len);
        return TakeBytes(ptr, len);
    }

    public string? QueryString(KoutenId id, string selection)
    {
        byte[]? bytes = Query(id, selection);
        return bytes is null ? null : Encoding.UTF8.GetString(bytes);
    }

    public KoutenRetrieveResult Retrieve(ReadOnlySpan<float> vector, string? ring = null, int budget = 10, int topRings = 50, int focus = 3)
    {
        fixed (float* vec = vector)
        {
            IntPtr resultPtr = Native.kouten_retrieve(CheckedHandle, vec, (UIntPtr)vector.Length, ring, budget, topRings, focus);
            if (resultPtr == IntPtr.Zero)
                throw LastError("retrieve failed");

            try
            {
                NativeRetrieveResult native = Marshal.PtrToStructure<NativeRetrieveResult>(resultPtr);
                var hits = new List<KoutenHit>((int)native.Len);
                int stride = Marshal.SizeOf<NativeHit>();
                IntPtr current = native.Hits;
                for (nuint i = 0; i < native.Len; i++)
                {
                    NativeHit hit = Marshal.PtrToStructure<NativeHit>(current);
                    hits.Add(new KoutenHit(hit.Id, hit.Score, CopyBytes(hit.Payload, hit.PayloadLen) ?? Array.Empty<byte>()));
                    current += stride;
                }
                return new KoutenRetrieveResult
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
                Native.kouten_retrieve_free(resultPtr);
            }
        }
    }

    public string Atlas(ReadOnlySpan<float> queryVector = default, int maxCentroidDims = 8)
    {
        fixed (float* vec = queryVector)
        {
            UIntPtr len;
            IntPtr ptr = Native.kouten_atlas(CheckedHandle, vec, (UIntPtr)queryVector.Length, maxCentroidDims, &len);
            byte[]? bytes = TakeBytes(ptr, len);
            if (bytes is null)
                throw LastError("atlas failed");
            return Encoding.UTF8.GetString(bytes);
        }
    }

    public int Locate(KoutenId id, double at = -1.0) => Native.kouten_locate(CheckedHandle, id, at);

    public double NextVisit(KoutenId id, int node) => Native.kouten_next_visit(CheckedHandle, id, node);

    public double NextJoin(KoutenId a, KoutenId b) => Native.kouten_next_join(CheckedHandle, a, b);

    public void Dispose()
    {
        if (_disposed)
            return;
        if (_handle != IntPtr.Zero)
        {
            Native.kouten_close(_handle);
            _handle = IntPtr.Zero;
        }
        _disposed = true;
        GC.SuppressFinalize(this);
    }

    ~KoutenDb() => Dispose();

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
                Native.kouten_free(ptr);
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

    private static KoutenDbException LastError(string fallback)
    {
        IntPtr ptr = Native.kouten_last_error();
        string? message = ptr == IntPtr.Zero ? null : Marshal.PtrToStringAnsi(ptr);
        return new KoutenDbException(string.IsNullOrWhiteSpace(message) ? fallback : message!);
    }
}

internal static partial class Native
{
    internal const int KoutenOk = 0;

    static Native()
    {
        NativeLibrary.SetDllImportResolver(typeof(Native).Assembly, Resolve);
    }

    private static IntPtr Resolve(string libraryName, System.Reflection.Assembly assembly, DllImportSearchPath? searchPath)
    {
        if (libraryName != "koutendb")
            return IntPtr.Zero;

        string? configured = Environment.GetEnvironmentVariable("KOUTENDB_NATIVE_LIB");
        if (!string.IsNullOrWhiteSpace(configured) && NativeLibrary.TryLoad(configured, out IntPtr configuredHandle))
            return configuredHandle;

        string? dir = AppContext.BaseDirectory;
        for (int i = 0; i < 10 && dir is not null; i++)
        {
            string candidate = Path.Combine(dir, "lib", "libkoutendb.so");
            if (File.Exists(candidate) && NativeLibrary.TryLoad(candidate, out IntPtr handle))
                return handle;

            candidate = Path.Combine(dir, "..", "lib", "libkoutendb.so");
            if (File.Exists(candidate) && NativeLibrary.TryLoad(Path.GetFullPath(candidate), out handle))
                return handle;

            dir = Directory.GetParent(dir)?.FullName;
        }

        return IntPtr.Zero;
    }

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int kouten_abi_version();

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr kouten_last_error();

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void kouten_init();

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr kouten_open(int nodes);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr kouten_open_dir(int nodes, [MarshalAs(UnmanagedType.LPUTF8Str)] string dir);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr kouten_connect([MarshalAs(UnmanagedType.LPUTF8Str)] string peers);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr kouten_connect_auth(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string peers,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? username,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? password,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? authToken,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? secretKey,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? galaxy);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void kouten_close(IntPtr db);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern double kouten_now(IntPtr db);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void kouten_advance(IntPtr db, double dt);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int kouten_ring_configure(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, double period);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int kouten_set_galaxy_description(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string description);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int kouten_set_ring_description(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, [MarshalAs(UnmanagedType.LPUTF8Str)] string description);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe int kouten_put(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, void* data, UIntPtr len, KoutenId* outId);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe int kouten_put_vec(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string ring, void* data, UIntPtr len, float* vec, UIntPtr vecLen, KoutenId* outId);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr kouten_get(IntPtr db, KoutenId id, UIntPtr* outLen);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void kouten_free(IntPtr p);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr kouten_batch_get(IntPtr db, KoutenId* ids, UIntPtr idsLen);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void kouten_batch_get_free(IntPtr result);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr kouten_query(IntPtr db, KoutenId id, [MarshalAs(UnmanagedType.LPUTF8Str)] string selection, UIntPtr* outLen);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr kouten_retrieve(IntPtr db, float* vec, UIntPtr vecLen, [MarshalAs(UnmanagedType.LPUTF8Str)] string? ring, int budget, int topRings, int focus);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void kouten_retrieve_free(IntPtr result);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern unsafe IntPtr kouten_atlas(IntPtr db, float* queryVec, UIntPtr queryVecLen, int maxCentroidDims, UIntPtr* outLen);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int kouten_locate(IntPtr db, KoutenId id, double at);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern double kouten_next_visit(IntPtr db, KoutenId id, int node);

    [DllImport("koutendb", CallingConvention = CallingConvention.Cdecl)]
    internal static extern double kouten_next_join(IntPtr db, KoutenId a, KoutenId b);
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
    public KoutenId Id;
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

