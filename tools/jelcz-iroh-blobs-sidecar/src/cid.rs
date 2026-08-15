// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

//! Garazyk Big-DASL BLAKE3 CID → iroh-blobs `Hash` (phase-35 S2 contract).

use std::fmt;

use iroh_blobs::Hash;

const DASL_CID_BYTE_LENGTH: usize = 36;
const DASL_CID_STRING_LENGTH: usize = 59;
const DASL_CID_VERSION: u8 = 0x01;
const DASL_CODEC_RAW: u8 = 0x55;
const DASL_CODEC_DRISL: u8 = 0x71;
const DASL_MULTIHASH_BLAKE3: u8 = 0x1e;
const DASL_DIGEST_LENGTH: u8 = 0x20;

const BASE32_ALPHABET: &[u8; 32] = b"abcdefghijklmnopqrstuvwxyz234567";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CidMappingError {
    InvalidLength,
    InvalidMultibase,
    InvalidBytes,
    UnsupportedHash,
}

impl fmt::Display for CidMappingError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidLength => write!(f, "Garazyk CA/VOD CID must be 59 characters"),
            Self::InvalidMultibase => write!(f, "Garazyk CA/VOD CID must use base32 multibase `b`"),
            Self::InvalidBytes => write!(f, "invalid DASL CID bytes"),
            Self::UnsupportedHash => {
                write!(f, "Garazyk CA/VOD iroh fetch requires BLAKE3 multihash")
            }
        }
    }
}

impl std::error::Error for CidMappingError {}

fn base32_index(ch: char) -> Option<u8> {
    BASE32_ALPHABET
        .iter()
        .position(|&b| b == ch as u8)
        .map(|idx| idx as u8)
}

fn decode_dasl_base32(input: &str) -> Result<[u8; DASL_CID_BYTE_LENGTH], CidMappingError> {
    let mut out = [0u8; DASL_CID_BYTE_LENGTH];
    let mut buffer: u32 = 0;
    let mut bits: u32 = 0;
    let mut out_len = 0usize;

    for ch in input.chars() {
        let idx = base32_index(ch).ok_or(CidMappingError::InvalidBytes)?;
        buffer = (buffer << 5) | u32::from(idx);
        bits += 5;
        while bits >= 8 {
            bits -= 8;
            if out_len >= DASL_CID_BYTE_LENGTH {
                return Err(CidMappingError::InvalidBytes);
            }
            out[out_len] = ((buffer >> bits) & 0xff) as u8;
            out_len += 1;
        }
    }

    if out_len != DASL_CID_BYTE_LENGTH {
        return Err(CidMappingError::InvalidBytes);
    }
    Ok(out)
}

/// Map a Garazyk CA/VOD CID string to an iroh-blobs fetch root.
pub fn garazyk_ca_vod_cid_to_hash(cid: &str) -> Result<Hash, CidMappingError> {
    if cid.len() != DASL_CID_STRING_LENGTH {
        return Err(CidMappingError::InvalidLength);
    }
    if !cid.starts_with('b') {
        return Err(CidMappingError::InvalidMultibase);
    }

    let bytes = decode_dasl_base32(&cid[1..])?;
    if bytes[0] != DASL_CID_VERSION {
        return Err(CidMappingError::InvalidBytes);
    }
    if bytes[1] != DASL_CODEC_RAW && bytes[1] != DASL_CODEC_DRISL {
        return Err(CidMappingError::InvalidBytes);
    }
    if bytes[2] != DASL_MULTIHASH_BLAKE3 || bytes[3] != DASL_DIGEST_LENGTH {
        return Err(CidMappingError::UnsupportedHash);
    }

    let mut digest = [0u8; 32];
    digest.copy_from_slice(&bytes[4..36]);
    Ok(Hash::from_bytes(digest))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[derive(serde::Deserialize)]
    struct FixtureFile {
        fixtures: Vec<Fixture>,
    }

    #[derive(serde::Deserialize)]
    struct Fixture {
        label: String,
        cid: String,
        payload_utf8: String,
    }

    #[test]
    fn fixture_cids_decode() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/hash_mapping.json");
        let text = std::fs::read_to_string(path).expect("read fixtures");
        let fixtures: FixtureFile = serde_json::from_str(&text).expect("parse fixtures");
        for fixture in fixtures.fixtures {
            let hash = garazyk_ca_vod_cid_to_hash(&fixture.cid)
                .unwrap_or_else(|e| panic!("{}: {e}", fixture.label));
            let payload = fixture.payload_utf8.into_bytes();
            let expected = Hash::new(&payload);
            assert_eq!(hash, expected, "fixture {}", fixture.label);
        }
    }

    #[test]
    fn rejects_sha256_profile() {
        // Base DASL SHA-256 fixture shape (multihash 0x12) — not valid for iroh fetch.
        let err = garazyk_ca_vod_cid_to_hash(
            "bafyreigdyrzt5sfp7udm7rwg6x52vnsjnu5adonpokojpgho4txxywlqji",
        )
        .unwrap_err();
        assert_eq!(err, CidMappingError::UnsupportedHash);
    }
}
