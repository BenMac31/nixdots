use std::time::{Duration, Instant};

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Verify,
    Enroll,
}

pub struct State {
    pub device: String,
    pub message: String,
    pub stages: u32,
    pub total: u32,
    pub matches: u32,
    pub misses: u32,
    pub retries: u32,
    pub present: bool,
    pub needed: bool,
    pub ready: bool,
    pub finished: bool,
    pub success: bool,
    pub last_result: Option<(bool, Instant)>,
    pub last_latency: Option<Duration>,
}

impl State {
    pub fn new() -> Self {
        Self {
            device: String::new(),
            message: "Connecting to the reader…".into(),
            stages: 0,
            total: 0,
            matches: 0,
            misses: 0,
            retries: 0,
            present: false,
            needed: false,
            ready: false,
            finished: false,
            success: false,
            last_result: None,
            last_latency: None,
        }
    }

    pub fn status(&mut self, status: &str, done: bool, elapsed: Duration) {
        self.message = match status {
            "enroll-stage-passed" => {
                self.stages += 1;
                "Lift, then touch at a slightly different angle."
            }
            "enroll-completed" => {
                self.stages = self.total;
                self.success = true;
                "Fingerprint saved."
            }
            "verify-match" => {
                self.matches += 1;
                self.success = true;
                self.last_result = Some((true, Instant::now()));
                "Fingerprint matched."
            }
            "verify-no-match" => {
                self.misses += 1;
                self.success = false;
                self.last_result = Some((false, Instant::now()));
                "No match. Try another angle."
            }
            "verify-finger-not-centered" | "enroll-finger-not-centered" => {
                self.retries += 1;
                "Move your finger toward the center."
            }
            "verify-remove-and-retry" | "enroll-remove-and-retry" => {
                self.retries += 1;
                "Lift your finger, then try again."
            }
            "verify-too-fast" | "enroll-too-fast" => {
                self.retries += 1;
                "Hold your finger a little longer."
            }
            "verify-swipe-too-short" | "enroll-swipe-too-short" => {
                self.retries += 1;
                "Scan was too short. Try again."
            }
            "verify-retry-scan" | "enroll-retry-scan" => {
                self.retries += 1;
                "Scan unclear. Lift and try again."
            }
            "enroll-duplicate" => "This finger is already enrolled.",
            "enroll-data-full" => "Reader storage is full.",
            "verify-disconnected" | "enroll-disconnected" => "Reader disconnected.",
            "verify-unknown-error" | "enroll-unknown-error" | "enroll-failed" => {
                "The reader reported an error."
            }
            _ => status,
        }
        .into();
        if done {
            self.last_latency = Some(elapsed);
        }
    }

    pub fn progress(&self) -> f32 {
        if self.total == 0 {
            0.0
        } else {
            (self.stages as f32 / self.total as f32).min(1.0)
        }
    }
}
