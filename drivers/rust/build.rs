use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let lib_dir = manifest_dir.join("../../lib");
    let lib_dir = lib_dir.canonicalize().unwrap_or(lib_dir);
    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=dylib=rochedb");
    println!("cargo:rustc-link-arg=-Wl,-rpath,{}", lib_dir.display());
}
