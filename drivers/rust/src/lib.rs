use std::error::Error as StdError;
use std::ffi::{CStr, CString, NulError};
use std::fmt;
use std::os::raw::{c_char, c_double, c_float, c_int, c_void};
use std::ptr;
use std::slice;
use std::sync::Once;

pub const ROCHE_ABI_VERSION: i32 = 1;

const ROCHE_OK: c_int = 0;

static INIT: Once = Once::new();

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RocheId {
    pub parent: u64,
    pub epoch: u32,
    pub seq: u32,
    pub t_write: f64,
}

#[repr(C)]
struct RocheValue {
    data: *mut c_void,
    len: usize,
}

#[repr(C)]
struct RocheBatchResult {
    len: usize,
    values: *mut RocheValue,
}

#[repr(C)]
struct RocheHitRaw {
    id: RocheId,
    score: c_double,
    payload: *mut c_void,
    payload_len: usize,
}

#[repr(C)]
struct RocheRetrieveResultRaw {
    len: usize,
    hits: *mut RocheHitRaw,
    total_vectors: c_int,
    scanned: c_int,
    skipped_vectors: c_int,
    returned: c_int,
    rings_touched: c_int,
    payload_bytes: c_int,
    estimated_tokens: c_int,
    fanout_nodes: c_int,
    candidate_reduction: c_double,
}

#[link(name = "rochedb")]
extern "C" {
    fn roche_init();
    fn roche_abi_version() -> c_int;
    fn roche_last_error() -> *const c_char;
    fn roche_open(nodes: c_int) -> *mut c_void;
    fn roche_open_dir(nodes: c_int, dir: *const c_char) -> *mut c_void;
    fn roche_connect_auth(
        peers: *const c_char,
        username: *const c_char,
        password: *const c_char,
        auth_token: *const c_char,
        secret_key: *const c_char,
        galaxy: *const c_char,
    ) -> *mut c_void;
    fn roche_close(db: *mut c_void);
    fn roche_free(p: *mut c_void);
    fn roche_ring_configure(db: *mut c_void, ring: *const c_char, period: c_double) -> c_int;
    fn roche_set_galaxy_description(db: *mut c_void, description: *const c_char) -> c_int;
    fn roche_set_ring_description(
        db: *mut c_void,
        ring: *const c_char,
        description: *const c_char,
    ) -> c_int;
    fn roche_put(
        db: *mut c_void,
        ring: *const c_char,
        data: *const c_void,
        len: usize,
        out_id: *mut RocheId,
    ) -> c_int;
    fn roche_put_vec(
        db: *mut c_void,
        ring: *const c_char,
        data: *const c_void,
        len: usize,
        vec: *const c_float,
        vec_len: usize,
        out_id: *mut RocheId,
    ) -> c_int;
    fn roche_get(db: *mut c_void, id: RocheId, out_len: *mut usize) -> *mut c_void;
    fn roche_batch_get(
        db: *mut c_void,
        ids: *const RocheId,
        ids_len: usize,
    ) -> *mut RocheBatchResult;
    fn roche_batch_get_free(r: *mut RocheBatchResult);
    fn roche_query(
        db: *mut c_void,
        id: RocheId,
        selection: *const c_char,
        out_len: *mut usize,
    ) -> *mut c_void;
    fn roche_retrieve(
        db: *mut c_void,
        vec: *const c_float,
        vec_len: usize,
        ring: *const c_char,
        budget: c_int,
        top_rings: c_int,
        focus: c_int,
    ) -> *mut RocheRetrieveResultRaw;
    fn roche_retrieve_free(r: *mut RocheRetrieveResultRaw);
    fn roche_atlas(
        db: *mut c_void,
        query_vec: *const c_float,
        query_vec_len: usize,
        max_centroid_dims: c_int,
        out_len: *mut usize,
    ) -> *mut c_void;
    fn roche_locate(db: *mut c_void, id: RocheId, at: c_double) -> c_int;
    fn roche_next_visit(db: *mut c_void, id: RocheId, node: c_int) -> c_double;
    fn roche_next_join(db: *mut c_void, a: RocheId, b: RocheId) -> c_double;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error {
    message: String,
}

impl Error {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }

    fn last() -> Self {
        unsafe {
            let p = roche_last_error();
            if p.is_null() {
                return Self::new("RocheDB C ABI error");
            }
            let s = CStr::from_ptr(p).to_string_lossy();
            if s.is_empty() {
                Self::new("RocheDB C ABI error")
            } else {
                Self::new(s.into_owned())
            }
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.message.fmt(f)
    }
}

impl StdError for Error {}

impl From<NulError> for Error {
    fn from(value: NulError) -> Self {
        Self::new(value.to_string())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Hit {
    pub id: RocheId,
    pub score: f64,
    pub payload: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RetrieveStats {
    pub total_vectors: i32,
    pub scanned: i32,
    pub skipped_vectors: i32,
    pub returned: i32,
    pub rings_touched: i32,
    pub payload_bytes: i32,
    pub estimated_tokens: i32,
    pub fanout_nodes: i32,
    pub candidate_reduction: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RetrieveResult {
    pub hits: Vec<Hit>,
    pub stats: RetrieveStats,
}

pub struct RocheDb {
    raw: *mut c_void,
}

unsafe impl Send for RocheDb {}

impl RocheDb {
    pub fn open(nodes: i32) -> Result<Self, Error> {
        init()?;
        let raw = unsafe { roche_open(nodes as c_int) };
        Self::from_raw(raw)
    }

    pub fn open_dir(nodes: i32, dir: &str) -> Result<Self, Error> {
        init()?;
        let dir = CString::new(dir)?;
        let raw = unsafe { roche_open_dir(nodes as c_int, dir.as_ptr()) };
        Self::from_raw(raw)
    }

    pub fn connect_auth(
        peers: &str,
        username: Option<&str>,
        password: Option<&str>,
        auth_token: Option<&str>,
        secret_key: Option<&str>,
        galaxy: Option<&str>,
    ) -> Result<Self, Error> {
        init()?;
        let peers = CString::new(peers)?;
        let username = opt_cstring(username)?;
        let password = opt_cstring(password)?;
        let auth_token = opt_cstring(auth_token)?;
        let secret_key = opt_cstring(secret_key)?;
        let galaxy = opt_cstring(galaxy)?;
        let raw = unsafe {
            roche_connect_auth(
                peers.as_ptr(),
                opt_ptr(&username),
                opt_ptr(&password),
                opt_ptr(&auth_token),
                opt_ptr(&secret_key),
                opt_ptr(&galaxy),
            )
        };
        Self::from_raw(raw)
    }

    fn from_raw(raw: *mut c_void) -> Result<Self, Error> {
        if raw.is_null() {
            Err(Error::last())
        } else {
            Ok(Self { raw })
        }
    }

    pub fn configure_ring(&self, ring: &str, period: f64) -> Result<(), Error> {
        let ring = CString::new(ring)?;
        self.check(unsafe { roche_ring_configure(self.raw, ring.as_ptr(), period) })
    }

    pub fn set_galaxy_description(&self, description: &str) -> Result<(), Error> {
        let description = CString::new(description)?;
        self.check(unsafe { roche_set_galaxy_description(self.raw, description.as_ptr()) })
    }

    pub fn set_ring_description(&self, ring: &str, description: &str) -> Result<(), Error> {
        let ring = CString::new(ring)?;
        let description = CString::new(description)?;
        self.check(unsafe {
            roche_set_ring_description(self.raw, ring.as_ptr(), description.as_ptr())
        })
    }

    pub fn put(&self, ring: &str, payload: &[u8]) -> Result<RocheId, Error> {
        let ring = CString::new(ring)?;
        let mut id = empty_id();
        let data = if payload.is_empty() {
            ptr::null()
        } else {
            payload.as_ptr() as *const c_void
        };
        self.check(unsafe { roche_put(self.raw, ring.as_ptr(), data, payload.len(), &mut id) })?;
        Ok(id)
    }

    pub fn put_vec(&self, ring: &str, payload: &[u8], vec: &[f32]) -> Result<RocheId, Error> {
        let ring = CString::new(ring)?;
        let mut id = empty_id();
        let data = if payload.is_empty() {
            ptr::null()
        } else {
            payload.as_ptr() as *const c_void
        };
        let vec_ptr = if vec.is_empty() {
            ptr::null()
        } else {
            vec.as_ptr()
        };
        self.check(unsafe {
            roche_put_vec(
                self.raw,
                ring.as_ptr(),
                data,
                payload.len(),
                vec_ptr,
                vec.len(),
                &mut id,
            )
        })?;
        Ok(id)
    }

    pub fn get(&self, id: RocheId) -> Result<Option<Vec<u8>>, Error> {
        let mut len = 0usize;
        let p = unsafe { roche_get(self.raw, id, &mut len) };
        if p.is_null() {
            let err = Error::last();
            if err.message.contains("not found") || err.message.contains("key not found") {
                return Ok(None);
            }
            return Err(err);
        }
        Ok(Some(unsafe { take_buffer(p, len) }))
    }

    pub fn batch_get(&self, ids: &[RocheId]) -> Result<Vec<Vec<u8>>, Error> {
        let ptr = if ids.is_empty() {
            ptr::null()
        } else {
            ids.as_ptr()
        };
        let r = unsafe { roche_batch_get(self.raw, ptr, ids.len()) };
        if r.is_null() {
            return Err(Error::last());
        }
        let result = unsafe {
            let values = slice::from_raw_parts((*r).values, (*r).len);
            let mut out = Vec::with_capacity(values.len());
            for value in values {
                let bytes = if value.data.is_null() {
                    Vec::new()
                } else {
                    slice::from_raw_parts(value.data as *const u8, value.len).to_vec()
                };
                out.push(bytes);
            }
            roche_batch_get_free(r);
            out
        };
        Ok(result)
    }

    pub fn query(&self, id: RocheId, selection: &str) -> Result<Vec<u8>, Error> {
        let selection = CString::new(selection)?;
        let mut len = 0usize;
        let p = unsafe { roche_query(self.raw, id, selection.as_ptr(), &mut len) };
        if p.is_null() {
            return Err(Error::last());
        }
        Ok(unsafe { take_buffer(p, len) })
    }

    pub fn retrieve(
        &self,
        vec: &[f32],
        ring: Option<&str>,
        budget: i32,
        top_rings: i32,
        focus: i32,
    ) -> Result<RetrieveResult, Error> {
        let ring = opt_cstring(ring)?;
        let vec_ptr = if vec.is_empty() {
            ptr::null()
        } else {
            vec.as_ptr()
        };
        let r = unsafe {
            roche_retrieve(
                self.raw,
                vec_ptr,
                vec.len(),
                opt_ptr(&ring),
                budget,
                top_rings,
                focus,
            )
        };
        if r.is_null() {
            return Err(Error::last());
        }
        let result = unsafe {
            let raw = &*r;
            let raw_hits = slice::from_raw_parts(raw.hits, raw.len);
            let hits = raw_hits
                .iter()
                .map(|h| Hit {
                    id: h.id,
                    score: h.score,
                    payload: if h.payload.is_null() {
                        Vec::new()
                    } else {
                        slice::from_raw_parts(h.payload as *const u8, h.payload_len).to_vec()
                    },
                })
                .collect();
            let stats = RetrieveStats {
                total_vectors: raw.total_vectors,
                scanned: raw.scanned,
                skipped_vectors: raw.skipped_vectors,
                returned: raw.returned,
                rings_touched: raw.rings_touched,
                payload_bytes: raw.payload_bytes,
                estimated_tokens: raw.estimated_tokens,
                fanout_nodes: raw.fanout_nodes,
                candidate_reduction: raw.candidate_reduction,
            };
            roche_retrieve_free(r);
            RetrieveResult { hits, stats }
        };
        Ok(result)
    }

    pub fn atlas(
        &self,
        query_vec: Option<&[f32]>,
        max_centroid_dims: i32,
    ) -> Result<String, Error> {
        let vec = query_vec.unwrap_or(&[]);
        let vec_ptr = if vec.is_empty() {
            ptr::null()
        } else {
            vec.as_ptr()
        };
        let mut len = 0usize;
        let p = unsafe { roche_atlas(self.raw, vec_ptr, vec.len(), max_centroid_dims, &mut len) };
        if p.is_null() {
            return Err(Error::last());
        }
        let bytes = unsafe { take_buffer(p, len) };
        String::from_utf8(bytes).map_err(|e| Error::new(e.to_string()))
    }

    pub fn locate(&self, id: RocheId, at: Option<f64>) -> Result<i32, Error> {
        let node = unsafe { roche_locate(self.raw, id, at.unwrap_or(-1.0)) };
        if node < 0 {
            Err(Error::last())
        } else {
            Ok(node)
        }
    }

    pub fn next_visit(&self, id: RocheId, node: i32) -> Result<f64, Error> {
        let t = unsafe { roche_next_visit(self.raw, id, node) };
        if t < 0.0 {
            Err(Error::last())
        } else {
            Ok(t)
        }
    }

    pub fn next_join(&self, a: RocheId, b: RocheId) -> Result<Option<f64>, Error> {
        let t = unsafe { roche_next_join(self.raw, a, b) };
        if t < 0.0 {
            Ok(None)
        } else {
            Ok(Some(t))
        }
    }

    fn check(&self, rc: c_int) -> Result<(), Error> {
        if rc == ROCHE_OK {
            Ok(())
        } else {
            Err(Error::last())
        }
    }
}

impl Drop for RocheDb {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { roche_close(self.raw) };
            self.raw = ptr::null_mut();
        }
    }
}

fn init() -> Result<(), Error> {
    INIT.call_once(|| unsafe { roche_init() });
    let version = unsafe { roche_abi_version() };
    if version != ROCHE_ABI_VERSION {
        Err(Error::new(format!(
            "RocheDB ABI version mismatch: expected {}, got {}",
            ROCHE_ABI_VERSION, version
        )))
    } else {
        Ok(())
    }
}

fn empty_id() -> RocheId {
    RocheId {
        parent: 0,
        epoch: 0,
        seq: 0,
        t_write: 0.0,
    }
}

fn opt_cstring(value: Option<&str>) -> Result<Option<CString>, Error> {
    value.map(CString::new).transpose().map_err(Error::from)
}

fn opt_ptr(value: &Option<CString>) -> *const c_char {
    value.as_ref().map_or(ptr::null(), |s| s.as_ptr())
}

unsafe fn take_buffer(p: *mut c_void, len: usize) -> Vec<u8> {
    let bytes = slice::from_raw_parts(p as *const u8, len).to_vec();
    roche_free(p);
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_roundtrip_retrieve_and_atlas() {
        let db = RocheDb::open(8).unwrap();
        db.set_galaxy_description("Rust test galaxy").unwrap();
        db.set_ring_description("docs/rust", "Rust driver documents")
            .unwrap();
        db.configure_ring("docs/rust", 30.0).unwrap();

        let id = db.put_vec("docs/rust", b"hello rust", &[1.0, 0.0]).unwrap();
        assert_eq!(db.get(id).unwrap().unwrap(), b"hello rust");

        let values = db.batch_get(&[id]).unwrap();
        assert_eq!(values, vec![b"hello rust".to_vec()]);

        let rr = db
            .retrieve(&[1.0, 0.0], Some("docs/rust"), 4, 0, 0)
            .unwrap();
        assert_eq!(rr.hits.len(), 1);
        assert_eq!(rr.stats.scanned, 1);

        let atlas = db.atlas(Some(&[1.0, 0.0]), 8).unwrap();
        assert!(atlas.contains("Rust test galaxy"));
        assert!(atlas.contains("Rust driver documents"));

        let node = db.locate(id, None).unwrap();
        assert!(node >= 0);
        assert!(db.next_visit(id, node).unwrap() >= 0.0);
    }

    #[test]
    fn errors_include_c_abi_message() {
        let db = RocheDb::open(8).unwrap();
        let err = db.put("bad\0ring", b"x").unwrap_err();
        assert!(err.to_string().contains("nul byte"));
    }
}
