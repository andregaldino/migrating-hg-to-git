use sha1::{Digest, Sha1};

#[derive(PartialEq, Debug)]
#[allow(non_camel_case_types)]
enum path_state {
    START, /* first byte of a path component */
    A,     /* "AUX" */
    AU,
    THIRD, /* third of a 3-byte sequence, e.g. "AUX", "NUL" */
    C,     /* "CON" or "COMn" */
    CO,
    COMLPT, /* "COM" or "LPT" */
    COMLPTn,
    L,
    LP,
    N,
    NU,
    P, /* "PRN" */
    PR,
    LDOT, /* leading '.' */
    DOT,  /* '.' in a non-leading position */
    H,    /* ".h" */
    HGDI, /* ".hg", ".d", or ".i" */
    SPACE,
    DEFAULT, /* byte of a path component after the first */
}

/* state machine for dir-encoding */
#[allow(non_camel_case_types)]
enum dir_state {
    DDOT,
    DH,
    DHGDI,
    DDEFAULT,
}

fn inset(bitset: &[u32; 8], c: u8) -> bool {
    bitset[(c as usize) >> 5] & (1 << (c & 31)) != 0
}

fn charcopy(dest: Option<&mut [u8]>, destlen: &mut usize, c: u8) {
    if let Some(slice) = dest {
        slice[*destlen] = c
    }
    *destlen += 1
}

fn memcopy(dest: Option<&mut [u8]>, destlen: &mut usize, src: &[u8]) {
    if let Some(slice) = dest {
        slice[*destlen..*destlen + src.len()].copy_from_slice(src)
    }
    *destlen += src.len();
}

fn rewrap_option<'a, 'b: 'a>(
    x: &'a mut Option<&'b mut [u8]>,
) -> Option<&'a mut [u8]> {
    match x {
        None => None,
        Some(y) => Some(y),
    }
}

fn hexencode<'a>(mut dest: Option<&'a mut [u8]>, destlen: &mut usize, c: u8) {
    let hexdigit = b"0123456789abcdef";
    charcopy(
        rewrap_option(&mut dest),
        destlen,
        hexdigit[(c as usize) >> 4],
    );
    charcopy(dest, destlen, hexdigit[(c as usize) & 15]);
}

/* 3-byte escape: tilde followed by two hex digits */
fn escape3(mut dest: Option<&mut [u8]>, destlen: &mut usize, c: u8) {
    charcopy(rewrap_option(&mut dest), destlen, b'~');
    hexencode(dest, destlen, c);
}

fn encode_dir(mut dest: Option<&mut [u8]>, src: &[u8]) -> usize {
    let mut state = dir_state::DDEFAULT;
    let mut i = 0;
    let mut destlen = 0;

    while i < src.len() {
        match state {
            dir_state::DDOT => match src[i] {
                b'd' | b'i' => {
                    state = dir_state::DHGDI;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b'h' => {
                    state = dir_state::DH;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                _ => {
                    state = dir_state::DDEFAULT;
                }
            },
            dir_state::DH => {
                if src[i] == b'g' {
                    state = dir_state::DHGDI;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                } else {
                    state = dir_state::DDEFAULT;
                }
            }
            dir_state::DHGDI => {
                if src[i] == b'/' {
                    memcopy(rewrap_option(&mut dest), &mut destlen, b".hg");
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                state = dir_state::DDEFAULT;
            }
            dir_state::DDEFAULT => {
                if src[i] == b'.' {
                    state = dir_state::DDOT
                }
                charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                i += 1;
            }
        }
    }
    destlen
}

fn _encode(
    twobytes: &[u32; 8],
    onebyte: &[u32; 8],
    mut dest: Option<&mut [u8]>,
    src: &[u8],
    encodedir: bool,
) -> usize {
    let mut state = path_state::START;
    let mut i = 0;
    let mut destlen = 0;
    let len = src.len();

    while i < len {
        match state {
            path_state::START => match src[i] {
                b'/' => {
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b'.' => {
                    state = path_state::LDOT;
                    escape3(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b' ' => {
                    state = path_state::DEFAULT;
                    escape3(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b'a' => {
                    state = path_state::A;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b'c' => {
                    state = path_state::C;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b'l' => {
                    state = path_state::L;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b'n' => {
                    state = path_state::N;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b'p' => {
                    state = path_state::P;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                _ => {
                    state = path_state::DEFAULT;
                }
            },
            path_state::A => {
                if src[i] == b'u' {
                    state = path_state::AU;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::AU => {
                if src[i] == b'x' {
                    state = path_state::THIRD;
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::THIRD => {
                state = path_state::DEFAULT;
                match src[i] {
                    b'.' | b'/' | b'\0' => escape3(
                        rewrap_option(&mut dest),
                        &mut destlen,
                        src[i - 1],
                    ),
                    _ => i -= 1,
                }
            }
            path_state::C => {
                if src[i] == b'o' {
                    state = path_state::CO;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::CO => {
                if src[i] == b'm' {
                    state = path_state::COMLPT;
                    i += 1;
                } else if src[i] == b'n' {
                    state = path_state::THIRD;
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::COMLPT => {
                if src[i] >= b'1' && src[i] <= b'9' {
                    state = path_state::COMLPTn;
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                    charcopy(
                        rewrap_option(&mut dest),
                        &mut destlen,
                        src[i - 1],
                    );
                }
            }
            path_state::COMLPTn => {
                state = path_state::DEFAULT;
                match src[i] {
                    b'.' | b'/' | b'\0' => {
                        escape3(
                            rewrap_option(&mut dest),
                            &mut destlen,
                            src[i - 2],
                        );
                        charcopy(
                            rewrap_option(&mut dest),
                            &mut destlen,
                            src[i - 1],
                        );
                    }
                    _ => {
                        memcopy(
                            rewrap_option(&mut dest),
                            &mut destlen,
                            &src[i - 2..i],
                        );
                    }
                }
            }
            path_state::L => {
                if src[i] == b'p' {
                    state = path_state::LP;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::LP => {
                if src[i] == b't' {
                    state = path_state::COMLPT;
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::N => {
                if src[i] == b'u' {
                    state = path_state::NU;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::NU => {
                if src[i] == b'l' {
                    state = path_state::THIRD;
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::P => {
                if src[i] == b'r' {
                    state = path_state::PR;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::PR => {
                if src[i] == b'n' {
                    state = path_state::THIRD;
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::LDOT => match src[i] {
                b'd' | b'i' => {
                    state = path_state::HGDI;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b'h' => {
                    state = path_state::H;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                _ => {
                    state = path_state::DEFAULT;
                }
            },
            path_state::DOT => match src[i] {
                b'/' | b'\0' => {
                    state = path_state::START;
                    memcopy(rewrap_option(&mut dest), &mut destlen, b"~2e");
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b'd' | b'i' => {
                    state = path_state::HGDI;
                    charcopy(rewrap_option(&mut dest), &mut destlen, b'.');
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                b'h' => {
                    state = path_state::H;
                    memcopy(rewrap_option(&mut dest), &mut destlen, b".h");
                    i += 1;
                }
                _ => {
                    state = path_state::DEFAULT;
                    charcopy(rewrap_option(&mut dest), &mut destlen, b'.');
                }
            },
            path_state::H => {
                if src[i] == b'g' {
                    state = path_state::HGDI;
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::HGDI => {
                if src[i] == b'/' {
                    state = path_state::START;
                    if encodedir {
                        memcopy(
                            rewrap_option(&mut dest),
                            &mut destlen,
                            b".hg",
                        );
                    }
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1
                } else {
                    state = path_state::DEFAULT;
                }
            }
            path_state::SPACE => match src[i] {
                b'/' | b'\0' => {
                    state = path_state::START;
                    memcopy(rewrap_option(&mut dest), &mut destlen, b"~20");
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                _ => {
                    state = path_state::DEFAULT;
                    charcopy(rewrap_option(&mut dest), &mut destlen, b' ');
                }
            },
            path_state::DEFAULT => {
                while i != len && inset(onebyte, src[i]) {
                    charcopy(rewrap_option(&mut dest), &mut destlen, src[i]);
                    i += 1;
                }
                if i == len {
                    break;
                }
                match src[i] {
                    b'.' => {
                        state = path_state::DOT;
                        i += 1
                    }
                    b' ' => {
                        state = path_state::SPACE;
                        i += 1
                    }
                    b'/' => {
                        state = path_state::START;
                        charcopy(rewrap_option(&mut dest), &mut destlen, b'/');
                        i += 1;
                    }
                    _ => {
                        if inset(onebyte, src[i]) {
                            loop {
                                charcopy(
                                    rewrap_option(&mut dest),
                                    &mut destlen,
                                    src[i],
                                );
                                i += 1;
                                if !(i < len && inset(onebyte, src[i])) {
                                    break;
                                }
                            }
                        } else if inset(twobytes, src[i]) {
                            let c = src[i];
                            i += 1;
                            charcopy(
                                rewrap_option(&mut dest),
                                &mut destlen,
                                b'_',
                            );
                            charcopy(
                                rewrap_option(&mut dest),
                                &mut destlen,
                                if c == b'_' { b'_' } else { c + 32 },
                            );
                        } else {
                            escape3(
                                rewrap_option(&mut dest),
                                &mut destlen,
                                src[i],
                            );
                            i += 1;
                        }
                    }
                }
            }
        }
    }
    match state {
        path_state::START => (),
        path_state::A => (),
        path_state::AU => (),
        path_state::THIRD => {
            escape3(rewrap_option(&mut dest), &mut destlen, src[i - 1])
        }
        path_state::C => (),
        path_state::CO => (),
        path_state::COMLPT => {
            charcopy(rewrap_option(&mut dest), &mut destlen, src[i - 1])
        }
        path_state::COMLPTn => {
            escape3(rewrap_option(&mut dest), &mut destlen, src[i - 2]);
            charcopy(rewrap_option(&mut dest), &mut destlen, src[i - 1]);
        }
        path_state::L => (),
        path_state::LP => (),
        path_state::N => (),
        path_state::NU => (),
        path_state::P => (),
        path_state::PR => (),
        path_state::LDOT => (),
        path_state::DOT => {
            memcopy(rewrap_option(&mut dest), &mut destlen, b"~2e");
        }
        path_state::H => (),
        path_state::HGDI => (),
        path_state::SPACE => {
            memcopy(rewrap_option(&mut dest), &mut destlen, b"~20");
        }
        path_state::DEFAULT => (),
    };
    destlen
}

fn basic_encode(dest: Option<&mut [u8]>, src: &[u8]) -> usize {
    let twobytes: [u32; 8] = [0, 0, 0x87ff_fffe, 0, 0, 0, 0, 0];
    let onebyte: [u32; 8] =
        [1, 0x2bff_3bfa, 0x6800_0001, 0x2fff_ffff, 0, 0, 0, 0];
    _encode(&twobytes, &onebyte, dest, src, true)
}

const MAXSTOREPATHLEN: usize = 120;

fn lower_encode(mut dest: Option<&mut [u8]>, src: &[u8]) -> usize {
    let onebyte: [u32; 8] =
        [1, 0x2bff_fbfb, 0xe800_0001, 0x2fff_ffff, 0, 0, 0, 0];
    let lower: [u32; 8] = [0, 0, 0x07ff_fffe, 0, 0, 0, 0, 0];
    let mut destlen = 0;
    for c in src {
        if inset(&onebyte, *c) {
            charcopy(rewrap_option(&mut dest), &mut destlen, *c)
        } else if inset(&lower, *c) {
            charcopy(rewrap_option(&mut dest), &mut destlen, *c + 32)
        } else {
            escape3(rewrap_option(&mut dest), &mut destlen, *c)
        }
    }
    destlen
}

fn aux_encode(dest: Option<&mut [u8]>, src: &[u8]) -> usize {
    let twobytes = [0; 8];
    let onebyte: [u32; 8] = [!0, 0xffff_3ffe, !0, !0, !0, !0, !0, !0];
    _encode(&twobytes, &onebyte, dest, src, false)
}

fn hash_mangle(src: &[u8], sha: &[u8]) -> Vec<u8> {
    let dirprefixlen = 8;
    let maxshortdirslen = 68;
    let mut destlen = 0;

    let last_slash = src.iter().rposition(|b| *b == b'/');
    let last_dot: Option<usize> = {
        let s = last_slash.unwrap_or(0);
        src[s..]
            .iter()
            .rposition(|b| *b == b'.')
            .and_then(|i| Some(i + s))
    };

    let mut dest = vec![0; MAXSTOREPATHLEN];
    memcopy(Some(&mut dest), &mut destlen, b"dh/");

    {
        let mut first = true;
        for slice in src[..last_slash.unwrap_or_else(|| src.len())]
            .split(|b| *b == b'/')
        {
            let slice = &slice[..std::cmp::min(slice.len(), dirprefixlen)];
            if destlen + (slice.len() + if first { 0 } else { 1 })
                > maxshortdirslen + 3
            {
                break;
            } else {
                if !first {
                    charcopy(Some(&mut dest), &mut destlen, b'/')
                };
                memcopy(Some(&mut dest), &mut destlen, slice);
                if dest[destlen - 1] == b'.' || dest[destlen - 1] == b' ' {
                    dest[destlen - 1] = b'_'
                }
            }
            first = false;
        }
        if !first {
            charcopy(Some(&mut dest), &mut destlen, b'/');
        }
    }

    let used = destlen + 40 + {
        if let Some(l) = last_dot {
            src.len() - l
        } else {
            0
        }
    };

    if MAXSTOREPATHLEN > used {
        let slop = MAXSTOREPATHLEN - used;
        let basenamelen = match last_slash {
            Some(l) => src.len() - l - 1,
            None => src.len(),
        };
        let basenamelen = std::cmp::min(basenamelen, slop);
        if basenamelen > 0 {
            let start = match last_slash {
                Some(l) => l + 1,
                None => 0,
            };
            memcopy(
                Some(&mut dest),
                &mut destlen,
                &src[start..][..basenamelen],
            )
        }
    }
    for c in sha {
        hexencode(Some(&mut dest), &mut destlen, *c);
    }
    if let Some(l) = last_dot {
        memcopy(Some(&mut dest), &mut destlen, &src[l..]);
    }
    if destlen == dest.len() {
        dest
    } else {
        // sometimes the path are shorter than MAXSTOREPATHLEN
        dest[..destlen].to_vec()
    }
}

const MAXENCODE: usize = 4096 * 4;
fn hash_encode(src: &[u8]) -> Vec<u8> {
    let dired = &mut [0; MAXENCODE];
    let lowered = &mut [0; MAXENCODE];
    let auxed = &mut [0; MAXENCODE];
    let baselen = (src.len() - 5) * 3;
    if baselen >= MAXENCODE {
        panic!("path_encode::hash_encore: string too long: {}", baselen)
    };
    let dirlen = encode_dir(Some(&mut dired[..]), src);
    let sha = Sha1::digest(&dired[..dirlen]);
    let lowerlen = lower_encode(Some(&mut lowered[..]), &dired[..dirlen][5..]);
    let auxlen = aux_encode(Some(&mut auxed[..]), &lowered[..lowerlen]);
    hash_mangle(&auxed[..auxlen], &sha)
}

pub fn path_encode(path: &[u8]) -> Vec<u8> {
    let newlen = if path.len() <= MAXSTOREPATHLEN {
        basic_encode(None, path)
    } else {
        MAXSTOREPATHLEN + 1
    };
    if newlen <= MAXSTOREPATHLEN {
        if newlen == path.len() {
            path.to_vec()
        } else {
            let mut res = vec![0; newlen];
            basic_encode(Some(&mut res), path);
            res
        }
    } else {
        hash_encode(&path)
    }
}
