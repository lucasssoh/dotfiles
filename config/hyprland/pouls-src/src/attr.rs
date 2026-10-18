//! A procfs or sysfs file opened once and re-read with pread(2).
//!
//! Both are seq_files: a read at offset 0 makes the kernel generate the
//! contents again, so one open descriptor serves every sample, with one
//! syscall per read and no open/close around it.

use std::fs::File;
use std::os::unix::fs::FileExt;
use std::path::Path;

pub struct Attr {
    file: File,
}

impl Attr {
    pub fn open(path: impl AsRef<Path>) -> Option<Attr> {
        File::open(path).ok().map(|file| Attr { file })
    }

    /// The whole file, into `buf`, which is reused from one read to the next.
    pub fn read<'a>(&self, buf: &'a mut Vec<u8>) -> Option<&'a str> {
        buf.clear();
        let mut chunk = [0u8; 4096];
        loop {
            match self.file.read_at(&mut chunk, buf.len() as u64) {
                Ok(0) => break,
                Ok(n) => {
                    buf.extend_from_slice(&chunk[..n]);
                    // A seq_file hands over everything that fits in one
                    // read: a short read is the end, without a second
                    // syscall to hear it say 0.
                    if n < chunk.len() {
                        break;
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => return None,
            }
        }
        std::str::from_utf8(buf).ok()
    }

    pub fn read_int(&self, buf: &mut Vec<u8>) -> Option<i64> {
        self.read(buf)?.trim().parse().ok()
    }
}

/// The entries of a sysfs directory, sorted like the shell's globs sort them,
/// so "the first one" means the same thing it did in the bash it replaces.
pub fn sorted_dir(dir: &str) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .map(|it| it.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect())
        .unwrap_or_default();
    names.sort();
    names.into_iter().map(|n| format!("{dir}/{n}")).collect()
}

pub fn read_trimmed(path: impl AsRef<Path>) -> Option<String> {
    std::fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}
