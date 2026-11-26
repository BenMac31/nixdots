#!/usr/bin/env python3
"""Persistent Pomodoro clock, controlled by newline-delimited JSON on stdin."""

import datetime as dt
import fcntl
import json
import math
import os
from pathlib import Path
import select
import subprocess
import sys
import time


DEFAULTS = {"focus": 25, "short": 5, "long": 15, "interval": 4, "autoBreak": False, "autoFocus": False}
LABELS = {"focus": "Focus", "short": "Short break", "long": "Long break"}


class Pomodoro:
    def __init__(self, path, notify=lambda message: None):
        self.path = Path(path)
        self.notify = notify
        self.state = {
            "settings": dict(DEFAULTS), "phase": "focus", "remaining": 1500,
            "deadline": None, "round": 0, "task": "", "history": [],
        }
        if self.path.exists():
            saved = json.loads(self.path.read_text())
            self.state.update(saved)
            self.state["settings"] = dict(DEFAULTS, **saved.get("settings", {}))
        self.error = ""

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.state, ensure_ascii=False) + "\n")
        temporary.chmod(0o600)
        temporary.replace(self.path)

    def seconds(self, now):
        deadline = self.state["deadline"]
        return max(0, math.ceil(deadline - now)) if deadline is not None else self.state["remaining"]

    def phase(self, phase, now, running=False):
        self.state["phase"] = phase
        self.state["remaining"] = self.state["settings"][phase] * 60
        self.state["deadline"] = now + self.state["remaining"] if running else None

    def advance(self, now, completed, ended=None):
        state = self.state
        old = state["phase"]
        if old == "focus":
            if completed:
                state["round"] += 1
                state["history"].append({
                    "ended": now if ended is None else ended,
                    "minutes": state["settings"]["focus"], "task": state["task"],
                })
                state["history"] = state["history"][-1000:]
            phase = "long" if state["round"] and state["round"] % state["settings"]["interval"] == 0 else "short"
            running = completed and state["settings"]["autoBreak"]
        else:
            phase, running = "focus", completed and state["settings"]["autoFocus"]
        self.phase(phase, now, running)
        if completed:
            self.notify(f"{LABELS[old]} complete. {LABELS[phase]} is {'starting' if running else 'ready'}.")

    def tick(self, now):
        if self.state["deadline"] is not None and now >= self.state["deadline"]:
            # Resume at the current time: sleep/restarts must not fabricate completed sessions.
            self.advance(now, True, ended=self.state["deadline"])
            self.save()

    def command(self, command, now):
        action = command.get("action")
        if action == "toggle":
            if self.state["deadline"] is None:
                self.state["deadline"] = now + self.state["remaining"]
            else:
                self.state["remaining"] = self.seconds(now)
                self.state["deadline"] = None
        elif action == "reset":
            self.phase(self.state["phase"], now)
        elif action == "skip":
            self.advance(now, False)
        elif action == "phase" and command.get("phase") in LABELS:
            self.phase(command["phase"], now)
        elif action == "task":
            if not isinstance(command.get("task"), str):
                raise ValueError("Enter a focus label.")
            self.state["task"] = command["task"].strip()[:200]
        elif action == "settings":
            settings = dict(self.state["settings"])
            for key, value in command.get("settings", {}).items():
                if key in ("autoBreak", "autoFocus") and isinstance(value, bool):
                    settings[key] = value
                elif key in ("focus", "short", "long", "interval") and type(value) is int and 1 <= value <= (12 if key == "interval" else 180):
                    settings[key] = value
                else:
                    raise ValueError("Durations must be 1–180 minutes; intervals must be 1–12.")
            if self.state["deadline"] is not None:
                raise ValueError("Pause the timer before changing its settings.")
            self.state["settings"] = settings
            self.phase(self.state["phase"], now)
        else:
            raise ValueError("Unknown Pomodoro command.")
        self.save()
        self.error = ""

    def snapshot(self, now):
        today = dt.datetime.fromtimestamp(now).date()
        history = self.state["history"]
        sessions = [entry for entry in history if dt.datetime.fromtimestamp(entry["ended"]).date() == today]
        return dict(self.state, remaining=self.seconds(now), running=self.state["deadline"] is not None,
                    label=LABELS[self.state["phase"]], total=self.state["settings"][self.state["phase"]] * 60,
                    todayCount=len(sessions), todayMinutes=sum(entry["minutes"] for entry in sessions),
                    history=list(reversed(history[-20:])), error=self.error)


def notify(message):
    try:
        subprocess.Popen(["notify-send", "--app-name=Pomodoro", "Pomodoro", message],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def main():
    base = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "graphide-shell"
    base.mkdir(parents=True, exist_ok=True)
    with (base / "pomodoro.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        timer = Pomodoro(base / "pomodoro.json", notify)
        pending, previous = b"", ""
        while True:
            now = time.time()
            try:
                timer.tick(now)
            except OSError as error:
                timer.error = f"Could not save timer: {error}"
            snapshot = json.dumps(timer.snapshot(now), ensure_ascii=False)
            if snapshot != previous:
                print(snapshot, flush=True)
                previous = snapshot
            if select.select([sys.stdin], [], [], 0.25)[0]:
                data = os.read(sys.stdin.fileno(), 65536)
                if not data:
                    break
                pending += data
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    try:
                        command = json.loads(line)
                        if not isinstance(command, dict):
                            raise ValueError("Expected a Pomodoro command.")
                        timer.tick(time.time())
                        timer.command(command, time.time())
                    except (ValueError, TypeError, OSError) as error:
                        timer.error = str(error)


if __name__ == "__main__":
    main()
