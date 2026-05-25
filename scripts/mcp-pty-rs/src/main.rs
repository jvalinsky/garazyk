use anyhow::{anyhow, Context, Result};
use base64::prelude::*;
use portable_pty::{native_pty_system, Child, ChildKiller, CommandBuilder, MasterPty, PtySize};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::{self, BufRead, Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::thread;

#[derive(Debug, Deserialize)]
#[serde(tag = "op")]
enum Command {
    #[serde(rename = "start")]
    Start {
        id: String,
        #[serde(rename = "sessionId")]
        session_id: String,
        command: String,
        #[serde(default)]
        args: Vec<String>,
        cwd: Option<String>,
        env: Option<HashMap<String, String>>,
        cols: Option<u16>,
        rows: Option<u16>,
    },
    #[serde(rename = "write")]
    Write {
        id: String,
        #[serde(rename = "sessionId")]
        session_id: String,
        data: String,
        #[serde(default)]
        base64: bool,
    },
    #[serde(rename = "resize")]
    Resize {
        id: String,
        #[serde(rename = "sessionId")]
        session_id: String,
        cols: u16,
        rows: u16,
    },
    #[serde(rename = "stop")]
    Stop {
        id: String,
        #[serde(rename = "sessionId")]
        session_id: String,
    },
    #[serde(rename = "list")]
    List { id: String },
    #[serde(rename = "shutdown")]
    Shutdown { id: String },
}

#[derive(Debug, Serialize)]
#[serde(untagged)]
enum Outgoing {
    Response(Response),
    Event(Event),
}

#[derive(Debug, Serialize)]
struct Response {
    id: String,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "event")]
enum Event {
    #[serde(rename = "output")]
    Output {
        #[serde(rename = "sessionId")]
        session_id: String,
        data: String,
    },
    #[serde(rename = "exit")]
    Exit {
        #[serde(rename = "sessionId")]
        session_id: String,
        #[serde(rename = "exitCode")]
        exit_code: u32,
        #[serde(skip_serializing_if = "Option::is_none")]
        signal: Option<String>,
    },
    #[serde(rename = "error")]
    Error {
        #[serde(rename = "sessionId")]
        session_id: Option<String>,
        error: String,
    },
}

struct Session {
    id: String,
    command: String,
    cols: u16,
    rows: u16,
    pid: Option<u32>,
    master: Box<dyn MasterPty + Send>,
    writer: Arc<Mutex<Box<dyn Write + Send>>>,
    killer: Arc<Mutex<Box<dyn ChildKiller + Send + Sync>>>,
    running: Arc<AtomicBool>,
    exit_code: Arc<Mutex<Option<u32>>>,
}

impl Session {
    fn summary(&self) -> Value {
        json!({
            "sessionId": self.id,
            "pid": self.pid,
            "command": self.command,
            "cols": self.cols,
            "rows": self.rows,
            "running": self.running.load(Ordering::SeqCst),
            "exitCode": *self.exit_code.lock().expect("exit code mutex poisoned")
        })
    }
}

struct App {
    sessions: HashMap<String, Session>,
    out: mpsc::Sender<Outgoing>,
}

impl App {
    fn new(out: mpsc::Sender<Outgoing>) -> Self {
        Self {
            sessions: HashMap::new(),
            out,
        }
    }

    fn handle(&mut self, command: Command) -> Result<bool> {
        match command {
            Command::Start {
                id,
                session_id,
                command,
                args,
                cwd,
                env,
                cols,
                rows,
            } => {
                let result = self
                    .start_session(session_id, command, args, cwd, env, cols, rows)
                    .map(|session| {
                        let summary = session.summary();
                        self.sessions.insert(session.id.clone(), session);
                        summary
                    });
                self.send_response(id, result);
            }
            Command::Write {
                id,
                session_id,
                data,
                base64,
            } => {
                let result = self
                    .write_session(&session_id, &data, base64)
                    .map(|_| json!({}));
                self.send_response(id, result);
            }
            Command::Resize {
                id,
                session_id,
                cols,
                rows,
            } => {
                let result = self.resize_session(&session_id, cols, rows).map(|session| {
                    json!({
                        "sessionId": session.id,
                        "cols": session.cols,
                        "rows": session.rows
                    })
                });
                self.send_response(id, result);
            }
            Command::Stop { id, session_id } => {
                let result = self
                    .stop_session(&session_id)
                    .map(|_| json!({ "sessionId": session_id }));
                self.send_response(id, result);
            }
            Command::List { id } => {
                let sessions = self
                    .sessions
                    .values()
                    .map(Session::summary)
                    .collect::<Vec<_>>();
                self.send_response(id, Ok(json!({ "sessions": sessions })));
            }
            Command::Shutdown { id } => {
                let session_ids = self.sessions.keys().cloned().collect::<Vec<_>>();
                for session_id in session_ids {
                    let _ = self.stop_session(&session_id);
                }
                self.send_response(id, Ok(json!({})));
                return Ok(false);
            }
        }
        Ok(true)
    }

    fn start_session(
        &mut self,
        session_id: String,
        command: String,
        args: Vec<String>,
        cwd: Option<String>,
        env: Option<HashMap<String, String>>,
        cols: Option<u16>,
        rows: Option<u16>,
    ) -> Result<Session> {
        if self.sessions.contains_key(&session_id) {
            return Err(anyhow!("session already exists: {session_id}"));
        }

        let cols = cols.unwrap_or(80).clamp(1, 400);
        let rows = rows.unwrap_or(24).clamp(1, 200);
        let pty_system = native_pty_system();
        let pair = pty_system
            .openpty(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .context("failed to open PTY")?;

        let mut builder = CommandBuilder::new(&command);
        builder.args(args);
        if let Some(cwd) = cwd {
            builder.cwd(cwd);
        }
        if let Some(env) = env {
            for (key, value) in env {
                builder.env(key, value);
            }
        }

        let mut child = pair
            .slave
            .spawn_command(builder)
            .with_context(|| format!("failed to spawn PTY command: {command}"))?;
        let pid = child.process_id();
        let killer = Arc::new(Mutex::new(child.clone_killer()));
        let running = Arc::new(AtomicBool::new(true));
        let exit_code = Arc::new(Mutex::new(None));
        let mut reader = pair
            .master
            .try_clone_reader()
            .context("failed to clone PTY reader")?;
        let writer = Arc::new(Mutex::new(
            pair.master
                .take_writer()
                .context("failed to take PTY writer")?,
        ));

        drop(pair.slave);

        let read_sender = self.out.clone();
        let read_session_id = session_id.clone();
        thread::spawn(move || read_loop(read_session_id, &mut reader, read_sender));

        let wait_sender = self.out.clone();
        let wait_session_id = session_id.clone();
        let wait_running = Arc::clone(&running);
        let wait_exit_code = Arc::clone(&exit_code);
        thread::spawn(move || {
            wait_loop(
                wait_session_id,
                &mut child,
                wait_running,
                wait_exit_code,
                wait_sender,
            )
        });

        Ok(Session {
            id: session_id.clone(),
            command,
            cols,
            rows,
            pid,
            master: pair.master,
            writer,
            killer,
            running,
            exit_code,
        })
    }

    fn write_session(&mut self, session_id: &str, data: &str, is_base64: bool) -> Result<()> {
        let session = self
            .sessions
            .get(session_id)
            .ok_or_else(|| anyhow!("unknown session: {session_id}"))?;
        let bytes = if is_base64 {
            BASE64_STANDARD
                .decode(data)
                .context("invalid base64 write payload")?
        } else {
            data.as_bytes().to_vec()
        };
        let mut writer = session.writer.lock().expect("PTY writer mutex poisoned");
        writer.write_all(&bytes).context("failed to write to PTY")?;
        writer.flush().context("failed to flush PTY")?;
        Ok(())
    }

    fn resize_session(&mut self, session_id: &str, cols: u16, rows: u16) -> Result<&Session> {
        let session = self
            .sessions
            .get_mut(session_id)
            .ok_or_else(|| anyhow!("unknown session: {session_id}"))?;
        session.cols = cols.clamp(1, 400);
        session.rows = rows.clamp(1, 200);
        session
            .master
            .resize(PtySize {
                rows: session.rows,
                cols: session.cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .context("failed to resize PTY")?;
        Ok(session)
    }

    fn stop_session(&mut self, session_id: &str) -> Result<()> {
        let session = self
            .sessions
            .remove(session_id)
            .ok_or_else(|| anyhow!("unknown session: {session_id}"))?;
        let mut killer = session.killer.lock().expect("PTY killer mutex poisoned");
        killer.kill().context("failed to kill PTY child")?;
        Ok(())
    }

    fn send_response(&self, id: String, result: Result<Value>) {
        let outgoing = match result {
            Ok(result) => Outgoing::Response(Response {
                id,
                ok: true,
                result: Some(result),
                error: None,
            }),
            Err(error) => Outgoing::Response(Response {
                id,
                ok: false,
                result: None,
                error: Some(error.to_string()),
            }),
        };
        let _ = self.out.send(outgoing);
    }
}

fn read_loop(session_id: String, reader: &mut Box<dyn Read + Send>, out: mpsc::Sender<Outgoing>) {
    let mut buf = [0_u8; 8192];
    loop {
        match reader.read(&mut buf) {
            Ok(0) => return,
            Ok(n) => {
                let data = BASE64_STANDARD.encode(&buf[..n]);
                if out
                    .send(Outgoing::Event(Event::Output {
                        session_id: session_id.clone(),
                        data,
                    }))
                    .is_err()
                {
                    return;
                }
            }
            Err(error) => {
                let _ = out.send(Outgoing::Event(Event::Error {
                    session_id: Some(session_id),
                    error: error.to_string(),
                }));
                return;
            }
        }
    }
}

fn wait_loop(
    session_id: String,
    child: &mut Box<dyn Child + Send + Sync>,
    running: Arc<AtomicBool>,
    shared_exit_code: Arc<Mutex<Option<u32>>>,
    out: mpsc::Sender<Outgoing>,
) {
    let (exit_code, signal) = match child.wait() {
        Ok(status) => (status.exit_code(), status.signal().map(str::to_owned)),
        Err(error) => {
            let _ = out.send(Outgoing::Event(Event::Error {
                session_id: Some(session_id.clone()),
                error: error.to_string(),
            }));
            (1, None)
        }
    };
    running.store(false, Ordering::SeqCst);
    *shared_exit_code.lock().expect("exit code mutex poisoned") = Some(exit_code);
    let _ = out.send(Outgoing::Event(Event::Exit {
        session_id,
        exit_code,
        signal,
    }));
}

fn writer_loop(rx: mpsc::Receiver<Outgoing>) {
    let stdout = io::stdout();
    let mut lock = stdout.lock();
    for outgoing in rx {
        match serde_json::to_writer(&mut lock, &outgoing) {
            Ok(()) => {
                let _ = lock.write_all(b"\n");
                let _ = lock.flush();
            }
            Err(error) => {
                let _ = writeln!(io::stderr(), "failed to encode PTY JSON event: {error}");
            }
        }
    }
}

fn main() -> Result<()> {
    let (tx, rx) = mpsc::channel::<Outgoing>();
    let writer = thread::spawn(move || writer_loop(rx));

    let mut app = App::new(tx.clone());
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let line = line.context("failed to read command line")?;
        if line.trim().is_empty() {
            continue;
        }
        let command_id = serde_json::from_str::<Value>(&line)
            .ok()
            .and_then(|value| value.get("id").and_then(Value::as_str).map(str::to_owned))
            .unwrap_or_else(|| "unknown".to_owned());
        match serde_json::from_str::<Command>(&line) {
            Ok(command) => {
                if !app.handle(command)? {
                    break;
                }
            }
            Err(error) => {
                app.send_response(command_id, Err(anyhow!("invalid command: {error}")));
            }
        }
    }

    drop(app);
    drop(tx);
    let _ = writer.join();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_start_command_with_defaults() {
        let command = serde_json::from_str::<Command>(
            r#"{"id":"1","op":"start","sessionId":"s1","command":"/bin/cat"}"#,
        )
        .expect("start command should parse");

        match command {
            Command::Start {
                id,
                session_id,
                command,
                args,
                cwd,
                env,
                cols,
                rows,
            } => {
                assert_eq!(id, "1");
                assert_eq!(session_id, "s1");
                assert_eq!(command, "/bin/cat");
                assert!(args.is_empty());
                assert_eq!(cwd, None);
                assert_eq!(env, None);
                assert_eq!(cols, None);
                assert_eq!(rows, None);
            }
            other => panic!("unexpected command: {other:?}"),
        }
    }

    #[test]
    fn serializes_response_as_json_line_payload() {
        let outgoing = Outgoing::Response(Response {
            id: "42".to_owned(),
            ok: false,
            result: None,
            error: Some("blocked".to_owned()),
        });

        let encoded = serde_json::to_string(&outgoing).expect("response should serialize");
        assert_eq!(encoded, r#"{"id":"42","ok":false,"error":"blocked"}"#);
    }

    #[test]
    fn serializes_output_event_with_base64_data() {
        let outgoing = Outgoing::Event(Event::Output {
            session_id: "s1".to_owned(),
            data: BASE64_STANDARD.encode(b"hello\r\n"),
        });

        let encoded = serde_json::to_string(&outgoing).expect("event should serialize");
        assert_eq!(
            encoded,
            r#"{"event":"output","sessionId":"s1","data":"aGVsbG8NCg=="}"#
        );
    }
}
