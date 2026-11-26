use crate::state::{Mode, State};
use crossterm::{cursor, queue, terminal};
use std::io::{self, IsTerminal, Write};
use unicode_width::UnicodeWidthChar;

const CYAN: (u8, u8, u8) = (106, 218, 214);
const GREEN: (u8, u8, u8) = (143, 218, 168);
const AMBER: (u8, u8, u8) = (239, 184, 119);
const DIM: (u8, u8, u8) = (106, 117, 136);
const SPIN: &[char] = &['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

fn paint(text: &str, rgb: (u8, u8, u8), color: bool) -> String {
    if color {
        format!("\x1b[38;2;{};{};{}m{text}\x1b[0m", rgb.0, rgb.1, rgb.2)
    } else {
        text.to_owned()
    }
}

fn fit(text: &str, width: usize) -> String {
    let mut used = 0;
    text.chars()
        .filter(|c| !c.is_control())
        .take_while(|c| {
            used += c.width().unwrap_or(0);
            used <= width
        })
        .collect()
}

fn ridge(x: f32, y: f32) -> bool {
    if x * x / 0.83 + (y + 0.02).powi(2) > 0.96 {
        return false;
    }
    let u = x * 1.06 + 0.045 * (y * 5.0).sin();
    let v = (y + 0.12) * 0.78;
    let angle = v.atan2(u);
    let phase = u.hypot(v) * 58.0 - angle + 0.7 * (angle * 2.0).sin();
    phase.sin() > 0.32
}

fn fingerprint(state: &State, mode: Mode, tick: u64, color: bool) -> Vec<String> {
    let columns = 23;
    let rows = 9;
    let dots = [
        (0, 0, 1),
        (0, 1, 2),
        (0, 2, 4),
        (1, 0, 8),
        (1, 1, 16),
        (1, 2, 32),
        (0, 3, 64),
        (1, 3, 128),
    ];
    let recent = state
        .last_result
        .filter(|(_, at)| at.elapsed().as_millis() < 900);
    (0..rows)
        .map(|row| {
            let mut line = String::new();
            for col in 0..columns {
                let mut bits = 0;
                for (dx, dy, bit) in dots {
                    let x = ((col * 2 + dx) as f32 + 0.5) / (columns * 2) as f32 * 2.0 - 1.0;
                    let y = ((row * 4 + dy) as f32 + 0.5) / (rows * 4) as f32 * 2.0 - 1.0;
                    if ridge(x, y) {
                        bits |= bit;
                    }
                }
                let glyph = char::from_u32(0x2800 + bits).unwrap();
                let accepted = mode == Mode::Enroll
                    && (1.0 - (row as f32 + 0.5) / rows as f32) < state.progress();
                let rgb = if state.finished && state.success {
                    GREEN
                } else if let Some((matched, _)) = recent {
                    if matched {
                        GREEN
                    } else {
                        AMBER
                    }
                } else if accepted {
                    CYAN
                } else if state.present && row == (tick / 2 % rows as u64) as usize {
                    (220, 240, 245)
                } else if state.present {
                    (155, 159, 212)
                } else {
                    (65, 76, 96)
                };
                line.push_str(&paint(&glyph.to_string(), rgb, color));
            }
            line
        })
        .collect()
}

pub struct Inline {
    animated: bool,
    color: bool,
    lines: u16,
    width: usize,
}

impl Inline {
    pub fn new(plain: bool, mode: Mode, finger: &str, demo: bool) -> io::Result<Self> {
        let animated = !plain
            && io::stderr().is_terminal()
            && std::env::var("TERM").is_ok_and(|t| t != "dumb");
        let color = animated && std::env::var_os("NO_COLOR").is_none();
        let width = terminal::size()
            .map(|(w, _)| w as usize)
            .unwrap_or(80)
            .saturating_sub(1)
            .max(1);
        let verb = if demo {
            "preview"
        } else if mode == Mode::Enroll {
            "enroll"
        } else {
            "verify"
        };
        let title = format!(
            "  {}  {verb} · {}",
            paint("ridge", CYAN, color),
            finger.replace('-', " ")
        );
        writeln!(io::stderr(), "{title}")?;
        if animated {
            queue!(io::stderr(), cursor::Hide)?;
        }
        Ok(Self {
            animated,
            color,
            lines: 0,
            width,
        })
    }

    pub fn event(&mut self, message: &str) -> io::Result<()> {
        self.clear()?;
        writeln!(
            io::stderr(),
            "  {}",
            fit(message, self.width.saturating_sub(2))
        )
    }

    pub fn is_animated(&self) -> bool {
        self.animated
    }

    fn clear(&mut self) -> io::Result<()> {
        if self.lines == 0 {
            return Ok(());
        }
        let mut out = io::stderr().lock();
        queue!(out, cursor::MoveUp(self.lines), cursor::MoveToColumn(0))?;
        for _ in 0..self.lines {
            queue!(out, terminal::Clear(terminal::ClearType::CurrentLine))?;
            writeln!(out)?;
        }
        queue!(out, cursor::MoveUp(self.lines), cursor::MoveToColumn(0))?;
        self.lines = 0;
        out.flush()
    }

    pub fn draw(&mut self, state: &State, mode: Mode, tick: u64, watch: bool) -> io::Result<()> {
        if !self.animated {
            return Ok(());
        }
        let hint = if state.finished {
            state.message.as_str()
        } else if !state.ready {
            "Connecting…"
        } else if state.present {
            "Reading your fingerprint…"
        } else if state.needed {
            "Touch the reader"
        } else {
            "Lift your finger"
        };
        let marker = if state.finished {
            if state.success {
                '✓'
            } else {
                '×'
            }
        } else {
            SPIN[(tick / 2 % SPIN.len() as u64) as usize]
        };
        let mut panel = vec![
            format!("{marker} {hint}"),
            state.device.clone(),
            String::new(),
        ];
        if mode == Mode::Enroll {
            let filled = (state.progress() * 16.0).floor() as usize;
            panel.push(format!("{}{}", "━".repeat(filled), "─".repeat(16 - filled)));
            panel.push(if state.total == 0 {
                "Waiting for enrollment stages…".into()
            } else {
                format!("{} / {} touches accepted", state.stages, state.total)
            });
        } else {
            panel.push(format!(
                "{} matched · {} missed",
                state.matches, state.misses
            ));
            panel.push(format!("{} scan retries", state.retries));
        }
        panel.extend([
            String::new(),
            state.message.clone(),
            String::new(),
            if state.finished {
                String::new()
            } else if watch {
                "Ctrl+C to finish".into()
            } else {
                "Ctrl+C to cancel".into()
            },
        ]);
        let mut lines = Vec::new();
        if self.width >= 55 {
            let art = fingerprint(state, mode, tick, self.color);
            let panel_width = self.width - 29;
            for (row, picture) in art.iter().enumerate() {
                let text = fit(&panel[row], panel_width);
                let rgb = if row == 0 {
                    if state.finished && !state.success {
                        AMBER
                    } else {
                        CYAN
                    }
                } else {
                    DIM
                };
                lines.push(format!("  {picture}    {}", paint(&text, rgb, self.color)));
            }
        } else {
            for text in [&panel[0], &panel[3], &panel[4]] {
                lines.push(format!(
                    " {}",
                    paint(&fit(text, self.width.saturating_sub(1)), CYAN, self.color)
                ));
            }
        }
        let mut frame = Vec::new();
        if self.lines > 0 {
            queue!(frame, cursor::MoveUp(self.lines), cursor::MoveToColumn(0))?;
        }
        for line in &lines {
            queue!(frame, terminal::Clear(terminal::ClearType::CurrentLine))?;
            writeln!(frame, "{line}")?;
        }
        self.lines = lines.len() as u16;
        let mut out = io::stderr().lock();
        out.write_all(&frame)?;
        out.flush()
    }

    pub fn finish(&mut self) -> io::Result<()> {
        self.lines = 0;
        if self.animated {
            let mut out = io::stderr().lock();
            queue!(out, crossterm::style::ResetColor, cursor::Show)?;
            out.flush()?;
        }
        Ok(())
    }
}

impl Drop for Inline {
    fn drop(&mut self) {
        let _ = self.finish();
    }
}
