//! Smoke-test harness: boots the engine via the same C-ABI entrypoint Dart will
//! use, then blocks so the HTTP API can be exercised with curl.
//!
//!   cargo run --example serve -- <download_dir> [port]
//!
//! Then, in another shell:
//!   curl -s -X POST "http://127.0.0.1:3030/torrents?overwrite=true" \
//!        --data "magnet:?xt=urn:btih:<infohash>&dn=..."
//!   curl -s "http://127.0.0.1:3030/torrents/0" | jq
//!   curl -s -r 0-1048575 "http://127.0.0.1:3030/torrents/0/stream/0" -o chunk.bin

use std::ffi::CString;

fn main() {
    let dir = std::env::args().nth(1).unwrap_or_else(|| ".".to_string());
    let port: u16 = std::env::args()
        .nth(2)
        .and_then(|s| s.parse().ok())
        .unwrap_or(3030);

    let cdir = CString::new(dir.clone()).expect("dir contains NUL");
    let rc = rqbit_ffi::rqbit_start(port, cdir.as_ptr());
    println!("rqbit_start(port={port}, dir={dir:?}) -> {rc}");
    if rc != 0 {
        std::process::exit(1);
    }

    println!("rqbit HTTP API serving at http://127.0.0.1:{port}");
    println!("press Ctrl+C to stop");
    loop {
        std::thread::sleep(std::time::Duration::from_secs(3600));
    }
}
