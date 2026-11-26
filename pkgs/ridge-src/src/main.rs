mod display;
mod state;

use anyhow::{bail, Context, Result};
use display::Inline;
use state::{Mode, State};
use std::{
    io::{self, Write},
    process::ExitCode,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    thread,
    time::{Duration, Instant},
};
use zbus::{
    blocking::{Connection, Proxy},
    zvariant::OwnedObjectPath,
};

const SERVICE: &str = "net.reactivated.Fprint";
const IFACE: &str = "net.reactivated.Fprint.Device";
const FINGERS: &[&str] = &[
    "left-thumb",
    "left-index-finger",
    "left-middle-finger",
    "left-ring-finger",
    "left-little-finger",
    "right-thumb",
    "right-index-finger",
    "right-middle-finger",
    "right-ring-finger",
    "right-little-finger",
];

enum Update {
    Ready { device: String, stages: u32 },
    Status(String, bool, Duration),
    Error(String),
    Finished,
}

struct Options {
    mode: Mode,
    finger: String,
    watch: bool,
    demo: bool,
    plain: bool,
}

fn device_path(conn: &Connection) -> Result<OwnedObjectPath> {
    let manager = Proxy::new(
        conn,
        SERVICE,
        "/net/reactivated/Fprint/Manager",
        "net.reactivated.Fprint.Manager",
    )?;
    manager
        .call("GetDefaultDevice", &())
        .context("No fingerprint reader found")
}

fn device<'a>(conn: &'a Connection, path: &'a OwnedObjectPath) -> Result<Proxy<'a>> {
    Ok(Proxy::new(conn, SERVICE, path.as_str(), IFACE)?)
}

fn claim(proxy: &Proxy<'_>) -> Result<()> {
    let _: () = proxy
        .call("Claim", &("",))
        .context("Could not claim reader. Close another fingerprint prompt and try again")?;
    Ok(())
}

struct Claimed<'a> {
    proxy: Proxy<'a>,
    stop: &'static str,
    active: bool,
}

impl Drop for Claimed<'_> {
    fn drop(&mut self) {
        if self.active {
            let _: zbus::Result<()> = self.proxy.call(self.stop, &());
        }
        let _: zbus::Result<()> = self.proxy.call("Release", &());
    }
}

fn scan(
    conn: Connection,
    path: OwnedObjectPath,
    mode: Mode,
    finger: String,
    watch: bool,
    tx: &mpsc::Sender<Update>,
    cancel: &AtomicBool,
) -> Result<()> {
    let proxy = device(&conn, &path)?;
    claim(&proxy)?;
    let stop = if mode == Mode::Enroll {
        "EnrollStop"
    } else {
        "VerifyStop"
    };
    let mut reader = Claimed {
        proxy,
        stop,
        active: false,
    };
    let name: String = reader.proxy.get_property("name")?;
    let total: i32 = reader.proxy.get_property("num-enroll-stages").unwrap_or(-1);
    tx.send(Update::Ready {
        device: name,
        stages: total.max(0) as u32,
    })
    .ok();
    if cancel.load(Ordering::Relaxed) {
        return Ok(());
    }
    let signal_name = if mode == Mode::Enroll {
        "EnrollStatus"
    } else {
        "VerifyStatus"
    };
    let mut signals = reader.proxy.receive_signal(signal_name)?;
    let start = if mode == Mode::Enroll {
        "EnrollStart"
    } else {
        "VerifyStart"
    };
    let mut began = Instant::now();
    let _: () = reader.proxy.call(start, &(finger.as_str(),))?;
    reader.active = true;
    for message in &mut signals {
        if cancel.load(Ordering::Relaxed) {
            break;
        }
        let (status, done): (String, bool) = message.body().deserialize()?;
        tx.send(Update::Status(status.clone(), done, began.elapsed()))
            .ok();
        if done {
            let _: () = reader.proxy.call(stop, &())?;
            reader.active = false;
            if !watch
                || mode == Mode::Enroll
                || !matches!(status.as_str(), "verify-match" | "verify-no-match")
            {
                break;
            }
            thread::sleep(Duration::from_millis(450));
            if cancel.load(Ordering::Relaxed) {
                break;
            }
            began = Instant::now();
            let _: () = reader.proxy.call(start, &(finger.as_str(),))?;
            reader.active = true;
        }
    }
    Ok(())
}

fn run_scan(options: Options, connection: Option<(Connection, OwnedObjectPath)>) -> Result<u8> {
    let cancel = Arc::new(AtomicBool::new(false));
    let signal_cancel = cancel.clone();
    ctrlc::set_handler(move || signal_cancel.store(true, Ordering::Relaxed))?;
    let (tx, rx) = mpsc::channel();
    let control = connection.as_ref().map(|(c, p)| (c.clone(), p.clone()));
    let mut output = Inline::new(options.plain, options.mode, &options.finger, options.demo)?;
    let mut state = State::new();
    if let Some((conn, path)) = connection {
        let worker_cancel = cancel.clone();
        let finger = options.finger.clone();
        let mode = options.mode;
        let watch = options.watch;
        thread::spawn(move || {
            if let Err(error) = scan(conn, path, mode, finger, watch, &tx, &worker_cancel) {
                tx.send(Update::Error(format!("{error:#}"))).ok();
            }
            tx.send(Update::Finished).ok();
        });
    }
    if options.demo {
        state.ready = true;
        state.needed = true;
        state.device = "Preview · simulated reader events".into();
        state.message = "Touch, lift, repeat.".into();
        state.total = 9;
    }
    let began = Instant::now();
    let mut completed_at = None;
    let mut failure = None;
    let mut tick = 0;
    let result = (|| -> Result<()> {
        loop {
            if cancel.load(Ordering::Relaxed) {
                break;
            }
            while let Ok(update) = rx.try_recv() {
                match update {
                    Update::Ready { device, stages } => {
                        state.device = device;
                        state.total = stages;
                        state.ready = true;
                        state.message = "Place your finger on the reader.".into();
                        if !output.is_animated() {
                            output.event(&format!("{} · {}", state.device, state.message))?;
                        }
                    }
                    Update::Status(status, done, elapsed) => {
                        state.status(&status, done, elapsed);
                        if !output.is_animated() || options.watch && done {
                            output.event(&format!(
                                "{}  ({:.1}s)",
                                state.message,
                                elapsed.as_secs_f32()
                            ))?;
                        }
                    }
                    Update::Error(error) => {
                        failure = Some(error.clone());
                        state.message = error;
                        state.success = false;
                    }
                    Update::Finished => {
                        state.finished = true;
                        completed_at = Some(Instant::now());
                    }
                }
            }
            if let Some((ref conn, ref path)) = control {
                if state.ready && !state.finished {
                    if let Ok(proxy) = device(conn, path) {
                        state.present = proxy.get_property("finger-present").unwrap_or(false);
                        state.needed = proxy.get_property("finger-needed").unwrap_or(false);
                    }
                }
            }
            if options.demo && !state.finished {
                let millis = began.elapsed().as_millis();
                let accepted = (millis / 650).min(9) as u32;
                state.present = millis % 650 < 350;
                state.needed = !state.present;
                if accepted > state.stages {
                    state.status("enroll-stage-passed", false, Duration::from_millis(650));
                    if !output.is_animated() {
                        output.event(&format!("{} / 9 touches accepted", state.stages))?;
                    }
                }
                if accepted == 9 {
                    state.status("enroll-completed", true, began.elapsed());
                    state.finished = true;
                    completed_at = Some(Instant::now());
                }
            }
            output.draw(&state, options.mode, tick, options.watch)?;
            if completed_at.is_some_and(|at| at.elapsed() > Duration::from_millis(400)) {
                break;
            }
            tick += 1;
            thread::sleep(Duration::from_millis(65));
        }
        Ok(())
    })();
    cancel.store(true, Ordering::Relaxed);
    if !state.finished {
        if let Some((conn, path)) = control {
            if let Ok(proxy) = device(&conn, &path) {
                let stop = if options.mode == Mode::Enroll {
                    "EnrollStop"
                } else {
                    "VerifyStop"
                };
                let _: zbus::Result<()> = proxy.call(stop, &());
                let _: zbus::Result<()> = proxy.call("Release", &());
            }
        }
    }
    output.finish()?;
    result?;
    if let Some(error) = failure {
        bail!("{error}");
    }
    if !state.finished {
        if options.watch {
            println!(
                "{} matched · {} missed · {} retries",
                state.matches, state.misses, state.retries
            );
            return Ok(0);
        }
        eprintln!("  Cancelled.");
        return Ok(130);
    }
    if options.demo {
        println!("✓ Preview complete. Try ridge enroll <finger> or ridge verify.");
    } else if state.success {
        println!("✓ {}", state.message);
    } else {
        eprintln!("× {}", state.message);
    }
    Ok(if state.success { 0 } else { 1 })
}

fn list(conn: &Connection, path: &OwnedObjectPath) -> Result<()> {
    let proxy = device(conn, path)?;
    let name: String = proxy.get_property("name")?;
    let scan_type: String = proxy.get_property("scan-type")?;
    let fingers: Vec<String> = proxy.call("ListEnrolledFingers", &(String::new(),))?;
    println!("{name} ({scan_type})");
    if fingers.is_empty() {
        println!("No enrolled fingers.");
    }
    for finger in fingers {
        println!("  {finger}");
    }
    Ok(())
}

fn delete(conn: &Connection, path: &OwnedObjectPath, finger: &str) -> Result<()> {
    let proxy = device(conn, path)?;
    let fingers: Vec<String> = proxy.call("ListEnrolledFingers", &(String::new(),))?;
    if !fingers.iter().any(|f| f == finger) {
        bail!("{finger} is not enrolled");
    }
    print!("Delete the enrolled {finger}? Type 'delete' to confirm: ");
    io::stdout().flush()?;
    let mut answer = String::new();
    io::stdin().read_line(&mut answer)?;
    if answer.trim() != "delete" {
        println!("Cancelled.");
        return Ok(());
    }
    claim(&proxy)?;
    let _reader = Claimed {
        proxy,
        stop: "VerifyStop",
        active: false,
    };
    let _: () = _reader.proxy.call("DeleteEnrolledFinger", &(finger,))?;
    println!("Deleted {finger}.");
    Ok(())
}

fn usage() {
    println!("ridge — fingerprints, in your shell\n\nUsage:\n  ridge [verify [finger]] [--watch] [--plain]\n  ridge enroll <finger> [--plain]\n  ridge list\n  ridge delete <finger>\n  ridge --demo [--plain]\n\nVerification exits after one result; --watch repeats and keeps scan statistics.\nCtrl+C cancels. --plain disables animation; NO_COLOR disables color.\n\nFingers: {}", FINGERS.join(", "));
}

fn run() -> Result<u8> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|a| a == "-h" || a == "--help") {
        usage();
        return Ok(0);
    }
    if args.iter().any(|a| a == "--version") {
        println!("ridge {}", env!("CARGO_PKG_VERSION"));
        return Ok(0);
    }
    for arg in &args {
        if arg.starts_with('-') && !matches!(arg.as_str(), "--watch" | "--plain" | "--demo") {
            bail!("Unknown option: {arg}");
        }
    }
    let positionals: Vec<&str> = args
        .iter()
        .filter(|a| !a.starts_with('-'))
        .map(String::as_str)
        .collect();
    let demo = args.iter().any(|a| a == "--demo");
    let watch = args.iter().any(|a| a == "--watch");
    let command = positionals
        .first()
        .copied()
        .unwrap_or(if demo { "enroll" } else { "verify" });
    let finger = match command {
        "verify" => positionals.get(1).copied().unwrap_or("any"),
        "enroll" if demo => "right-index-finger",
        "enroll" | "delete" => positionals
            .get(1)
            .copied()
            .context("Specify a finger. See ridge --help")?,
        "list" => "",
        _ => bail!("Unknown command: {command}. See ridge --help"),
    };
    if positionals.len() > if command == "list" { 1 } else { 2 } {
        bail!("Too many arguments. See ridge --help");
    }
    if !finger.is_empty() && !FINGERS.contains(&finger) && !(command == "verify" && finger == "any")
    {
        bail!("Unknown finger: {finger}");
    }
    if watch && command != "verify" {
        bail!("--watch applies to verification");
    }
    if demo && (!positionals.is_empty() || watch) {
        bail!("Use ridge --demo to preview enrollment");
    }
    let options = Options {
        mode: if command == "enroll" {
            Mode::Enroll
        } else {
            Mode::Verify
        },
        finger: finger.into(),
        watch,
        demo,
        plain: args.iter().any(|a| a == "--plain"),
    };
    if demo {
        return run_scan(options, None);
    }
    let conn = Connection::system().context("Could not connect to system D-Bus")?;
    let path = device_path(&conn)?;
    match command {
        "list" => {
            list(&conn, &path)?;
            Ok(0)
        }
        "delete" => {
            delete(&conn, &path, finger)?;
            Ok(0)
        }
        _ => run_scan(options, Some((conn, path))),
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("ridge: {error:#}");
            ExitCode::FAILURE
        }
    }
}
