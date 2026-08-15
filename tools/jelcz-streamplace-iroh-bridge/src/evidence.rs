// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

//! Process-persistent, bridge-owned live-session evidence.
//!
//! This module deliberately records only events the bridge itself performs or
//! receives.  It does not infer a firehose source, an AT record, consent, or
//! MUXL validity.  Jelcz may attest the latter after its own validation, but
//! the attestation is bound to the exact bridge session and received bytes.

use std::{
    collections::{BTreeMap, HashMap},
    ffi::{CStr, CString, OsStr},
    fs::{self, File},
    io::{Read, Write},
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::ffi::OsStrExt,
    },
    path::{Component, Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::bridge::{BridgeError, STREAMPLACE_ALPN};

const CONTRACT_VERSION: &str = "jelcz-streamplace-iroh-bridge-evidence/v1";
const MAX_REJECTIONS_PER_SESSION: usize = 16;
static TEMPORARY_FILE_COUNTER: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvidenceReport {
    pub contract_version: String,
    pub process_started_unix_ms: u128,
    pub sessions: BTreeMap<String, SessionEvidence>,
}

impl EvidenceReport {
    fn empty() -> Self {
        Self {
            contract_version: CONTRACT_VERSION.into(),
            process_started_unix_ms: now_unix_ms(),
            sessions: BTreeMap::new(),
        }
    }

    /// A report is complete only for facts this bridge can directly prove.
    pub fn has_complete_bridge_owned_evidence(&self) -> bool {
        self.sessions.values().any(SessionEvidence::is_complete)
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionEvidence {
    pub session_id: String,
    pub requested_streamer: String,
    pub ticket_fingerprint: String,
    pub ticket_node_id: String,
    pub alpn: String,
    pub dial_attempts: u32,
    pub reconnect_attempts: u32,
    pub reconnect_attempt_limit: u8,
    pub subscribe_acknowledged: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub attestation_expires_unix_ms: Option<u128>,
    pub attestation_consumed: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub authenticated_remote_node_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub segment: Option<SegmentEvidence>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub jelcz_attestation: Option<JelczAttestation>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub observed_rejections: Vec<String>,
}

impl SessionEvidence {
    fn new(
        session_id: String,
        streamer: String,
        ticket_fingerprint: String,
        ticket_node_id: String,
        reconnect_attempt_limit: u8,
    ) -> Self {
        Self {
            session_id,
            requested_streamer: streamer,
            ticket_fingerprint,
            ticket_node_id,
            alpn: STREAMPLACE_ALPN.into(),
            dial_attempts: 0,
            reconnect_attempts: 0,
            reconnect_attempt_limit,
            subscribe_acknowledged: false,
            attestation_expires_unix_ms: None,
            attestation_consumed: false,
            authenticated_remote_node_id: None,
            segment: None,
            jelcz_attestation: None,
            observed_rejections: Vec::new(),
        }
    }

    fn is_complete(&self) -> bool {
        let Some(authenticated_peer) = &self.authenticated_remote_node_id else {
            return false;
        };
        let Some(segment) = &self.segment else {
            return false;
        };
        let Some(attestation) = &self.jelcz_attestation else {
            return false;
        };
        let Some(expires_at) = self.attestation_expires_unix_ms else {
            return false;
        };
        self.subscribe_acknowledged
            && self.alpn == STREAMPLACE_ALPN
            && self.dial_attempts > 0
            && authenticated_peer == &self.ticket_node_id
            && segment.bytes > 0
            && segment.from_node_id == self.ticket_node_id
            && attestation.muxl_structural_validation == "valid"
            && attestation.content_bytes == segment.bytes
            && attestation.content_sha256 == segment.content_sha256
            && self.attestation_consumed
            && attestation.attested_unix_ms <= expires_at
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SegmentEvidence {
    pub bytes: usize,
    pub from_node_id: String,
    pub content_sha256: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JelczAttestation {
    pub muxl_structural_validation: String,
    pub content_bytes: usize,
    pub content_sha256: String,
    pub attested_unix_ms: u128,
}

#[derive(Clone, Debug)]
pub struct EvidenceStore {
    path: Arc<PathBuf>,
    state: Arc<Mutex<EvidenceState>>,
}

#[derive(Debug)]
struct EvidenceState {
    report: EvidenceReport,
    attestable_until: HashMap<String, Instant>,
}

impl EvidenceStore {
    /// Start a new bridge process record.  The file is atomically replaced so
    /// an acceptance command cannot treat a prior bridge process as live.
    pub fn start(path: PathBuf) -> Result<Self, BridgeError> {
        validate_path(&path)?;
        let store = Self {
            path: Arc::new(path),
            state: Arc::new(Mutex::new(EvidenceState {
                report: EvidenceReport::empty(),
                attestable_until: HashMap::new(),
            })),
        };
        store.persist()?;
        Ok(store)
    }

    pub fn read(path: &Path) -> Result<EvidenceReport, BridgeError> {
        validate_path(path)?;
        let mut file =
            open_existing_nofollow(path).map_err(|_| BridgeError::EvidenceUnavailable)?;
        let mut bytes = Vec::new();
        file.read_to_end(&mut bytes)
            .map_err(|_| BridgeError::EvidenceUnavailable)?;
        let report: EvidenceReport =
            serde_json::from_slice(&bytes).map_err(|_| BridgeError::EvidenceUnavailable)?;
        if report.contract_version != CONTRACT_VERSION {
            return Err(BridgeError::EvidenceUnavailable);
        }
        Ok(report)
    }

    pub fn ticket_fingerprint(ticket: &str) -> String {
        Self::sha256(ticket.as_bytes())
    }

    pub fn content_sha256(content: &[u8]) -> String {
        Self::sha256(content)
    }

    fn sha256(value: &[u8]) -> String {
        let digest = Sha256::digest(value);
        let mut fingerprint = String::with_capacity("sha256:".len() + digest.len() * 2);
        fingerprint.push_str("sha256:");
        for byte in digest {
            use std::fmt::Write as _;
            write!(&mut fingerprint, "{byte:02x}").expect("writing to String cannot fail");
        }
        fingerprint
    }

    pub fn begin_dial(
        &self,
        session_id: String,
        streamer: String,
        ticket_fingerprint: String,
        ticket_node_id: String,
        reconnect_attempt_limit: u8,
    ) -> Result<(), BridgeError> {
        self.update(|state| {
            let session = state
                .report
                .sessions
                .entry(session_id.clone())
                .or_insert_with(|| {
                    SessionEvidence::new(
                        session_id,
                        streamer,
                        ticket_fingerprint,
                        ticket_node_id,
                        reconnect_attempt_limit,
                    )
                });
            session.dial_attempts = session.dial_attempts.saturating_add(1);
            Ok(())
        })
    }

    pub fn acknowledge_subscribe(&self, session_id: &str) -> Result<(), BridgeError> {
        self.update_session(session_id, |session| {
            session.subscribe_acknowledged = true;
            Ok(())
        })
    }

    pub fn record_reconnect_attempt(&self, session_id: &str) -> Result<(), BridgeError> {
        self.update_session(session_id, |session| {
            session.reconnect_attempts = session.reconnect_attempts.saturating_add(1);
            Ok(())
        })
    }

    pub fn record_segment(
        &self,
        session_id: &str,
        authenticated_peer: String,
        bytes: usize,
        from_node_id: String,
        content_sha256: String,
    ) -> Result<(), BridgeError> {
        self.update_session(session_id, |session| {
            session.authenticated_remote_node_id = Some(authenticated_peer);
            session.segment = Some(SegmentEvidence {
                bytes,
                from_node_id,
                content_sha256,
            });
            session.attestation_expires_unix_ms = None;
            session.attestation_consumed = false;
            session.jelcz_attestation = None;
            Ok(())
        })
    }

    /// Open the one-shot window immediately before IPC returns the candidate.
    pub fn open_attestation_window(
        &self,
        session_id: &str,
        attestation_window: Duration,
    ) -> Result<(), BridgeError> {
        let expires_at_unix_ms = now_unix_ms().saturating_add(attestation_window.as_millis());
        let expires_at = Instant::now() + attestation_window;
        let mut state = self
            .state
            .lock()
            .map_err(|_| BridgeError::EvidencePersistence)?;
        let session = state
            .report
            .sessions
            .get_mut(session_id)
            .filter(|session| {
                session.segment.is_some()
                    && !session.attestation_consumed
                    && session.attestation_expires_unix_ms.is_none()
            })
            .ok_or(BridgeError::EvidenceAttestationMismatch)?;
        session.attestation_expires_unix_ms = Some(expires_at_unix_ms);
        state.attestable_until.insert(session_id.into(), expires_at);
        persist_report(&self.path, &state.report)
    }

    pub fn record_rejection(
        &self,
        session_id: &str,
        code: &'static str,
    ) -> Result<(), BridgeError> {
        self.update_session(session_id, |session| {
            if session.observed_rejections.len() < MAX_REJECTIONS_PER_SESSION
                && !session
                    .observed_rejections
                    .iter()
                    .any(|existing| existing == code)
            {
                session.observed_rejections.push(code.into());
            }
            Ok(())
        })
    }

    pub fn attest_muxl(
        &self,
        session_id: &str,
        ticket_fingerprint: &str,
        content_bytes: usize,
        content_sha256: &str,
    ) -> Result<(), BridgeError> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| BridgeError::EvidencePersistence)?;
        let deadline = state
            .attestable_until
            .remove(session_id)
            .ok_or(BridgeError::EvidenceAttestationMismatch)?;
        if Instant::now() > deadline {
            return Err(BridgeError::EvidenceAttestationMismatch);
        }
        let session = state
            .report
            .sessions
            .get_mut(session_id)
            .ok_or(BridgeError::EvidenceAttestationMismatch)?;
        if session.attestation_consumed {
            return Err(BridgeError::EvidenceAttestationMismatch);
        }
        {
            if session.ticket_fingerprint != ticket_fingerprint {
                return Err(BridgeError::EvidenceAttestationMismatch);
            }
            let Some(segment) = &session.segment else {
                return Err(BridgeError::EvidenceAttestationMismatch);
            };
            if content_bytes == 0
                || segment.bytes != content_bytes
                || segment.content_sha256 != content_sha256
            {
                return Err(BridgeError::EvidenceAttestationMismatch);
            }
            session.jelcz_attestation = Some(JelczAttestation {
                muxl_structural_validation: "valid".into(),
                content_bytes,
                content_sha256: content_sha256.into(),
                attested_unix_ms: now_unix_ms(),
            });
            session.attestation_consumed = true;
        }
        persist_report(&self.path, &state.report)
    }

    fn update_session(
        &self,
        session_id: &str,
        update: impl FnOnce(&mut SessionEvidence) -> Result<(), BridgeError>,
    ) -> Result<(), BridgeError> {
        self.update(|state| {
            let session = state
                .report
                .sessions
                .get_mut(session_id)
                .ok_or(BridgeError::EvidenceAttestationMismatch)?;
            update(session)
        })
    }

    fn update(
        &self,
        update: impl FnOnce(&mut EvidenceState) -> Result<(), BridgeError>,
    ) -> Result<(), BridgeError> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| BridgeError::EvidencePersistence)?;
        update(&mut state)?;
        persist_report(&self.path, &state.report)
    }

    fn persist(&self) -> Result<(), BridgeError> {
        let state = self
            .state
            .lock()
            .map_err(|_| BridgeError::EvidencePersistence)?;
        persist_report(&self.path, &state.report)
    }
}

fn persist_report(path: &Path, report: &EvidenceReport) -> Result<(), BridgeError> {
    let bytes = serde_json::to_vec(report).map_err(|_| BridgeError::EvidencePersistence)?;
    let (parent, destination) = open_secure_parent(path)?;
    reject_unsafe_existing(&parent, &destination)?;
    let temporary = CString::new(format!(
        ".{}.{}.{}.tmp",
        path.file_name()
            .and_then(|name| name.to_str())
            .ok_or(BridgeError::InvalidEvidencePath)?,
        std::process::id(),
        TEMPORARY_FILE_COUNTER.fetch_add(1, Ordering::Relaxed),
    ))
    .map_err(|_| BridgeError::InvalidEvidencePath)?;
    let result = (|| {
        let fd = unsafe {
            libc::openat(
                parent.as_raw_fd(),
                temporary.as_ptr(),
                libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL | libc::O_NOFOLLOW | libc::O_CLOEXEC,
                0o600,
            )
        };
        if fd < 0 {
            return Err(BridgeError::EvidencePersistence);
        }
        let mut file = unsafe { File::from_raw_fd(fd) };
        file.write_all(&bytes)
            .map_err(|_| BridgeError::EvidencePersistence)?;
        file.sync_all()
            .map_err(|_| BridgeError::EvidencePersistence)?;
        let renamed = unsafe {
            libc::renameat(
                parent.as_raw_fd(),
                temporary.as_ptr(),
                parent.as_raw_fd(),
                destination.as_ptr(),
            )
        };
        if renamed != 0 {
            return Err(BridgeError::EvidencePersistence);
        }
        parent
            .sync_all()
            .map_err(|_| BridgeError::EvidencePersistence)
    })();
    if result.is_err() {
        unsafe {
            libc::unlinkat(parent.as_raw_fd(), temporary.as_ptr(), 0);
        }
    }
    result
}

fn validate_path(path: &Path) -> Result<(), BridgeError> {
    let (parent, destination) = open_secure_parent(path)?;
    reject_unsafe_existing(&parent, &destination)?;
    Ok(())
}

fn open_existing_nofollow(path: &Path) -> Result<File, BridgeError> {
    let (parent, name) = open_secure_parent(path)?;
    let fd = unsafe {
        libc::openat(
            parent.as_raw_fd(),
            name.as_ptr(),
            libc::O_RDONLY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };
    if fd < 0 {
        return Err(BridgeError::EvidenceUnavailable);
    }
    let file = unsafe { File::from_raw_fd(fd) };
    require_safe_file(&file)?;
    Ok(file)
}

/// Resolve every directory using `openat(O_NOFOLLOW)` from a trusted `/tmp`
/// descriptor. This keeps validation and later file operations relative to the
/// same directory object even if an attacker races pathname changes.
fn open_secure_parent(path: &Path) -> Result<(File, CString), BridgeError> {
    if !path.is_absolute() || !path.starts_with("/tmp") {
        return Err(BridgeError::InvalidEvidencePath);
    }
    if path
        .components()
        .any(|component| !matches!(component, Component::RootDir | Component::Normal(_)))
    {
        return Err(BridgeError::InvalidEvidencePath);
    }
    let canonical_tmp = fs::canonicalize("/tmp").map_err(|_| BridgeError::InvalidEvidencePath)?;
    let parent_path = path.parent().ok_or(BridgeError::InvalidEvidencePath)?;
    let canonical_parent =
        fs::canonicalize(parent_path).map_err(|_| BridgeError::InvalidEvidencePath)?;
    if !canonical_parent.starts_with(&canonical_tmp) {
        return Err(BridgeError::InvalidEvidencePath);
    }

    let tmp = c_string(canonical_tmp.as_os_str())?;
    let root_fd = unsafe {
        libc::open(
            tmp.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };
    if root_fd < 0 {
        return Err(BridgeError::InvalidEvidencePath);
    }
    let mut directory = unsafe { File::from_raw_fd(root_fd) };
    require_safe_directory(&directory, true)?;

    let relative_parent = parent_path
        .strip_prefix("/tmp")
        .map_err(|_| BridgeError::InvalidEvidencePath)?;
    for component in relative_parent.components() {
        let Component::Normal(name) = component else {
            return Err(BridgeError::InvalidEvidencePath);
        };
        let name = c_string(name)?;
        let fd = unsafe {
            libc::openat(
                directory.as_raw_fd(),
                name.as_ptr(),
                libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
            )
        };
        if fd < 0 {
            return Err(BridgeError::InvalidEvidencePath);
        }
        let next = unsafe { File::from_raw_fd(fd) };
        require_safe_directory(&next, false)?;
        directory = next;
    }
    let destination = c_string(path.file_name().ok_or(BridgeError::InvalidEvidencePath)?)?;
    Ok((directory, destination))
}

fn c_string(value: &OsStr) -> Result<CString, BridgeError> {
    CString::new(value.as_bytes()).map_err(|_| BridgeError::InvalidEvidencePath)
}

fn reject_unsafe_existing(parent: &File, name: &CStr) -> Result<(), BridgeError> {
    let mut status = std::mem::MaybeUninit::<libc::stat>::uninit();
    let result = unsafe {
        libc::fstatat(
            parent.as_raw_fd(),
            name.as_ptr(),
            status.as_mut_ptr(),
            libc::AT_SYMLINK_NOFOLLOW,
        )
    };
    if result != 0 {
        let error = std::io::Error::last_os_error();
        if error.raw_os_error() == Some(libc::ENOENT) {
            return Ok(());
        }
        return Err(BridgeError::InvalidEvidencePath);
    }
    let status = unsafe { status.assume_init() };
    if status.st_uid != unsafe { libc::geteuid() }
        || (status.st_mode & libc::S_IFMT) != libc::S_IFREG
    {
        return Err(BridgeError::InvalidEvidencePath);
    }
    Ok(())
}

fn require_safe_file(file: &File) -> Result<(), BridgeError> {
    let status = file_status(file)?;
    if status.st_uid != unsafe { libc::geteuid() }
        || (status.st_mode & libc::S_IFMT) != libc::S_IFREG
    {
        return Err(BridgeError::InvalidEvidencePath);
    }
    Ok(())
}

fn require_safe_directory(directory: &File, is_tmp: bool) -> Result<(), BridgeError> {
    let status = file_status(directory)?;
    if (status.st_mode & libc::S_IFMT) != libc::S_IFDIR {
        return Err(BridgeError::InvalidEvidencePath);
    }
    let current_uid = unsafe { libc::geteuid() };
    let current_gid = unsafe { libc::getegid() };
    if is_tmp {
        let sticky_world_writable =
            status.st_mode & libc::S_ISVTX != 0 && status.st_mode & libc::S_IWOTH != 0;
        let root_group_writable = status.st_uid == 0
            && status.st_gid == current_gid
            && status.st_mode & libc::S_IWGRP != 0;
        if status.st_uid != current_uid && !sticky_world_writable && !root_group_writable {
            return Err(BridgeError::InvalidEvidencePath);
        }
    } else if status.st_uid != current_uid || status.st_mode & 0o022 != 0 {
        return Err(BridgeError::InvalidEvidencePath);
    }
    Ok(())
}

fn file_status(file: &File) -> Result<libc::stat, BridgeError> {
    let mut status = std::mem::MaybeUninit::<libc::stat>::uninit();
    if unsafe { libc::fstat(file.as_raw_fd(), status.as_mut_ptr()) } != 0 {
        return Err(BridgeError::InvalidEvidencePath);
    }
    Ok(unsafe { status.assume_init() })
}

fn now_unix_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn path(label: &str) -> PathBuf {
        PathBuf::from("/tmp").join(format!(
            "jelcz-bridge-evidence-{label}-{}-{}.json",
            std::process::id(),
            now_unix_ms()
        ))
    }

    fn begin(store: &EvidenceStore) {
        store
            .begin_dial(
                "session-1".into(),
                "did:plc:alice".into(),
                "sha256:ticket".into(),
                "node-1".into(),
                3,
            )
            .unwrap();
        store.acknowledge_subscribe("session-1").unwrap();
        store
            .record_segment(
                "session-1",
                "node-1".into(),
                4,
                "node-1".into(),
                "sha256:segment".into(),
            )
            .unwrap();
        store
            .open_attestation_window("session-1", Duration::from_secs(30))
            .unwrap();
    }

    #[test]
    fn lifecycle_is_incomplete_until_jelcz_attests_real_segment_bytes() {
        let path = path("incomplete");
        let store = EvidenceStore::start(path.clone()).unwrap();
        begin(&store);
        assert!(
            !EvidenceStore::read(&path)
                .unwrap()
                .has_complete_bridge_owned_evidence()
        );
        assert_eq!(
            store
                .open_attestation_window("session-1", Duration::from_secs(30))
                .unwrap_err(),
            BridgeError::EvidenceAttestationMismatch
        );
        store
            .attest_muxl("session-1", "sha256:ticket", 4, "sha256:segment")
            .unwrap();
        assert_eq!(
            store
                .attest_muxl("session-1", "sha256:ticket", 4, "sha256:segment")
                .unwrap_err(),
            BridgeError::EvidenceAttestationMismatch
        );
        assert!(
            EvidenceStore::read(&path)
                .unwrap()
                .has_complete_bridge_owned_evidence()
        );
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn persistence_is_atomic_and_readable() {
        let path = path("atomic");
        let store = EvidenceStore::start(path.clone()).unwrap();
        store
            .begin_dial(
                "session-1".into(),
                "did:plc:alice".into(),
                "sha256:ticket".into(),
                "node-1".into(),
                3,
            )
            .unwrap();
        let report = EvidenceStore::read(&path).unwrap();
        assert_eq!(report.sessions["session-1"].dial_attempts, 1);
        let temporary_prefix = format!(".{}.", path.file_name().unwrap().to_string_lossy());
        assert!(fs::read_dir(path.parent().unwrap()).unwrap().all(|entry| {
            !entry
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(&temporary_prefix)
        }));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn stale_or_mismatched_attestation_is_rejected() {
        let cases = [
            (
                "wrong-ticket",
                "session-1",
                "sha256:other",
                4,
                "sha256:segment",
            ),
            (
                "wrong-bytes",
                "session-1",
                "sha256:ticket",
                5,
                "sha256:segment",
            ),
            (
                "wrong-hash",
                "session-1",
                "sha256:ticket",
                4,
                "sha256:other",
            ),
            (
                "missing-session",
                "missing",
                "sha256:ticket",
                4,
                "sha256:segment",
            ),
        ];
        for (label, session_id, ticket, bytes, content_hash) in cases {
            let path = path(label);
            let store = EvidenceStore::start(path.clone()).unwrap();
            begin(&store);
            assert_eq!(
                store
                    .attest_muxl(session_id, ticket, bytes, content_hash)
                    .unwrap_err(),
                BridgeError::EvidenceAttestationMismatch
            );
            assert!(
                !EvidenceStore::read(&path)
                    .unwrap()
                    .has_complete_bridge_owned_evidence()
            );
            fs::remove_file(path).unwrap();
        }
    }

    #[test]
    fn expired_attestation_window_cannot_upgrade_completeness() {
        let path = path("expired");
        let store = EvidenceStore::start(path.clone()).unwrap();
        begin(&store);
        store
            .state
            .lock()
            .unwrap()
            .attestable_until
            .insert("session-1".into(), Instant::now() - Duration::from_secs(1));
        assert_eq!(
            store
                .attest_muxl("session-1", "sha256:ticket", 4, "sha256:segment")
                .unwrap_err(),
            BridgeError::EvidenceAttestationMismatch
        );
        assert!(
            !EvidenceStore::read(&path)
                .unwrap()
                .has_complete_bridge_owned_evidence()
        );
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn evidence_path_rejects_symlink_parent_and_final_component() {
        use std::os::unix::fs::{PermissionsExt, symlink};

        let root = PathBuf::from("/tmp").join(format!(
            "jelcz-evidence-path-test-{}-{}",
            std::process::id(),
            now_unix_ms()
        ));
        let real = root.join("real");
        fs::create_dir(&root).unwrap();
        fs::create_dir(&real).unwrap();
        symlink(&real, root.join("linked")).unwrap();
        assert_eq!(
            EvidenceStore::start(root.join("linked/evidence.json")).unwrap_err(),
            BridgeError::InvalidEvidencePath
        );
        let target = real.join("target.json");
        fs::write(&target, b"not evidence").unwrap();
        symlink(&target, real.join("final.json")).unwrap();
        assert_eq!(
            EvidenceStore::start(real.join("final.json")).unwrap_err(),
            BridgeError::InvalidEvidencePath
        );
        let unsafe_directory = root.join("world-writable");
        fs::create_dir(&unsafe_directory).unwrap();
        fs::set_permissions(&unsafe_directory, fs::Permissions::from_mode(0o777)).unwrap();
        assert_eq!(
            EvidenceStore::start(unsafe_directory.join("evidence.json")).unwrap_err(),
            BridgeError::InvalidEvidencePath
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn tickets_and_capabilities_are_not_persisted() {
        let path = path("redaction");
        let store = EvidenceStore::start(path.clone()).unwrap();
        let ticket = "secret-ticket-value";
        let capability = "secret-capability-value";
        store
            .begin_dial(
                "session-1".into(),
                "did:plc:alice".into(),
                EvidenceStore::ticket_fingerprint(ticket),
                "node-1".into(),
                3,
            )
            .unwrap();
        let contents = String::from_utf8(fs::read(&path).unwrap()).unwrap();
        assert!(!contents.contains(ticket));
        // The evidence API has no capability argument or field, so a bridge
        // token cannot reach its serialization sink.
        assert!(!contents.contains(capability));
        assert!(contents.contains("sha256:"));
        fs::remove_file(path).unwrap();
    }
}
