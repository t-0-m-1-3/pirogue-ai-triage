#!/usr/bin/env python3
"""
pirogue-triage-daemon.py
========================
Watches Suricata eve.json for alert events, triages them via the Claude API,
deduplicates, and sends enriched notifications via signal-cli over Signal.

Designed to run as a systemd service on the PiRogue VPS.

Usage:
    python3 pirogue-triage-daemon.py --config /etc/pirogue-triage/config.toml

Or for the demo with all defaults:
    ANTHROPIC_API_KEY=sk-ant-... python3 pirogue-triage-daemon.py

Environment:
    ANTHROPIC_API_KEY  - Required. Your Anthropic API key.
"""

import argparse
import json
import hashlib
import logging
import os
import signal
import subprocess
import sys
import time
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None

try:
    import httpx
except ImportError:
    print("ERROR: httpx not installed. Run: pip install httpx", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

@dataclass
class Config:
    # Paths
    eve_json_path: str = "/var/log/suricata/eve.json"
    log_file: str = "/var/log/pirogue-triage/triage.log"
    state_dir: str = "/var/lib/pirogue-triage"

    # Signal
    signal_account: str = ""          # Your number: +1XXXXXXXXXX
    signal_recipients: list = field(default_factory=list)  # List of numbers to alert

    # Claude API
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-sonnet-4-20250514"
    anthropic_max_tokens: int = 512

    # Triage behavior
    dedup_window_seconds: int = 300   # Suppress same SID for 5 min
    severity_threshold: int = 1       # 1=low, 2=medium, 3=high (alert on all by default)
    batch_window_seconds: float = 2.0 # Wait this long to batch rapid-fire alerts
    max_alerts_per_minute: int = 10   # Rate limit to avoid API cost blowup
    enable_ai_triage: bool = True     # Set False to send raw alerts without AI
    demo_mode: bool = False           # Extra verbose logging for live demo

    @classmethod
    def from_toml(cls, path: str) -> "Config":
        if tomllib is None:
            raise RuntimeError("tomllib/tomli not available for TOML parsing")
        with open(path, "rb") as f:
            data = tomllib.load(f)
        flat = {}
        for section in data.values():
            if isinstance(section, dict):
                flat.update(section)
            else:
                continue
        return cls(**{k: v for k, v in flat.items() if k in cls.__dataclass_fields__})

    def __post_init__(self):
        if not self.anthropic_api_key:
            self.anthropic_api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if not self.signal_recipients and self.signal_account:
            self.signal_recipients = [self.signal_account]


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

def setup_logging(config: Config) -> logging.Logger:
    logger = logging.getLogger("pirogue-triage")
    logger.setLevel(logging.DEBUG if config.demo_mode else logging.INFO)

    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    # Console (always — needed for demo tmux pane)
    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(logging.DEBUG if config.demo_mode else logging.INFO)
    ch.setFormatter(fmt)
    logger.addHandler(ch)

    # File
    log_dir = Path(config.log_file).parent
    log_dir.mkdir(parents=True, exist_ok=True)
    fh = logging.FileHandler(config.log_file)
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    return logger


# ---------------------------------------------------------------------------
# Deduplication
# ---------------------------------------------------------------------------

class DedupTracker:
    """Suppress repeated alerts for the same SID within a time window."""

    def __init__(self, window_seconds: int):
        self.window = timedelta(seconds=window_seconds)
        self._seen: dict[str, datetime] = {}

    def _make_key(self, alert: dict) -> str:
        """Key on SID + source IP to allow same rule from different hosts."""
        sid = alert.get("alert", {}).get("signature_id", "unknown")
        src = alert.get("src_ip", "unknown")
        return f"{sid}:{src}"

    def is_duplicate(self, alert: dict) -> bool:
        key = self._make_key(alert)
        now = datetime.now(timezone.utc)
        last_seen = self._seen.get(key)

        if last_seen and (now - last_seen) < self.window:
            return True

        self._seen[key] = now
        self._cleanup(now)
        return False

    def _cleanup(self, now: datetime):
        """Prune old entries to prevent memory leak."""
        expired = [k for k, v in self._seen.items() if (now - v) > self.window * 2]
        for k in expired:
            del self._seen[k]


# ---------------------------------------------------------------------------
# Rate Limiter
# ---------------------------------------------------------------------------

class RateLimiter:
    def __init__(self, max_per_minute: int):
        self.max = max_per_minute
        self._timestamps: list[float] = []

    def allow(self) -> bool:
        now = time.time()
        self._timestamps = [t for t in self._timestamps if now - t < 60]
        if len(self._timestamps) >= self.max:
            return False
        self._timestamps.append(now)
        return True


# ---------------------------------------------------------------------------
# Eve.json Tailer (handles logrotate)
# ---------------------------------------------------------------------------

class EveTailer:
    """
    Tail eve.json, handling log rotation gracefully.
    Uses inode tracking to detect rotation.
    """

    def __init__(self, path: str, logger: logging.Logger):
        self.path = Path(path)
        self.logger = logger
        self._fh = None
        self._inode = None

    def _open(self):
        if self._fh:
            self._fh.close()
        self._fh = open(self.path, "r")
        self._fh.seek(0, 2)  # Seek to end
        self._inode = self.path.stat().st_ino
        self.logger.info(f"Opened {self.path} (inode {self._inode})")

    def _check_rotation(self) -> bool:
        try:
            current_inode = self.path.stat().st_ino
            if current_inode != self._inode:
                self.logger.warning(f"Log rotation detected (inode {self._inode} -> {current_inode})")
                return True
        except FileNotFoundError:
            return True
        return False

    def lines(self):
        """Generator that yields new lines, handling rotation."""
        if not self._fh:
            while not self.path.exists():
                self.logger.warning(f"Waiting for {self.path} to appear...")
                time.sleep(2)
            self._open()

        while True:
            line = self._fh.readline()
            if line:
                yield line.strip()
            else:
                if self._check_rotation():
                    self._open()
                time.sleep(0.1)


# ---------------------------------------------------------------------------
# Claude API Triage
# ---------------------------------------------------------------------------

TRIAGE_SYSTEM_PROMPT = """You are a security analyst triaging Suricata IDS alerts from a PiRogue mobile traffic monitoring system. All traffic originates from mobile phones tunneled through a WireGuard VPN.

Given a raw Suricata alert JSON event, provide a concise triage summary in this exact format:

SEVERITY: [CRITICAL/HIGH/MEDIUM/LOW]
SUMMARY: [One sentence describing what happened]
CONTEXT: [2-3 sentences with technical context — what this indicator means, known associations with threat actors or malware families if the signature name suggests any, and relevance to mobile device security]
ACTION: [One sentence recommended response]

Be specific and technical. Do not hedge excessively. If the signature name references a known threat (e.g., "BabyShark", "Cobalt Strike", specific APT tooling), mention it by name. If it's a demo/test rule (SID 9999xxx), acknowledge it's a test but still provide useful triage as if it were real.

Keep the total response under 200 words. Do not use markdown formatting. Do not include preamble."""

def triage_with_claude(alert: dict, config: Config, logger: logging.Logger) -> Optional[str]:
    """Send alert to Claude API for enrichment. Returns triage text or None on failure."""
    if not config.anthropic_api_key:
        logger.error("No ANTHROPIC_API_KEY set — skipping AI triage")
        return None

    alert_json = json.dumps(alert, indent=2, default=str)
    prompt = f"Triage this Suricata alert:\n\n{alert_json}"

    try:
        with httpx.Client(timeout=30.0) as client:
            resp = client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": config.anthropic_api_key,
                    "content-type": "application/json",
                    "anthropic-version": "2023-06-01",
                },
                json={
                    "model": config.anthropic_model,
                    "max_tokens": config.anthropic_max_tokens,
                    "system": TRIAGE_SYSTEM_PROMPT,
                    "messages": [{"role": "user", "content": prompt}],
                },
            )
            resp.raise_for_status()
            data = resp.json()

            # Extract text from response
            text_parts = [
                block["text"]
                for block in data.get("content", [])
                if block.get("type") == "text"
            ]
            triage_text = "\n".join(text_parts).strip()

            if triage_text:
                logger.info(f"AI triage complete ({len(triage_text)} chars)")
                return triage_text
            else:
                logger.warning("AI triage returned empty response")
                return None

    except httpx.TimeoutException:
        logger.error("Claude API timeout (30s)")
        return None
    except httpx.HTTPStatusError as e:
        logger.error(f"Claude API error: {e.response.status_code} {e.response.text[:200]}")
        return None
    except Exception as e:
        logger.error(f"Claude API unexpected error: {e}")
        return None


# ---------------------------------------------------------------------------
# Signal Notification
# ---------------------------------------------------------------------------

def format_raw_alert(alert: dict) -> str:
    """Format alert without AI triage — fallback mode."""
    a = alert.get("alert", {})
    sig = a.get("signature", "Unknown Rule")
    sid = a.get("signature_id", "?")
    sev = a.get("severity", "?")
    src = alert.get("src_ip", "?")
    src_port = alert.get("src_port", "?")
    dst = alert.get("dest_ip", "?")
    dst_port = alert.get("dest_port", "?")
    proto = alert.get("proto", "?")
    ts = alert.get("timestamp", "?")

    return (
        f"\U0001F6A8 SURICATA ALERT\n"
        f"\n"
        f"Rule: {sig}\n"
        f"SID: {sid} | Severity: {sev}\n"
        f"Proto: {proto}\n"
        f"Src: {src}:{src_port}\n"
        f"Dst: {dst}:{dst_port}\n"
        f"Time: {ts}"
    )


def format_enriched_alert(alert: dict, triage: str) -> str:
    """Format alert with AI triage enrichment."""
    a = alert.get("alert", {})
    sig = a.get("signature", "Unknown Rule")
    sid = a.get("signature_id", "?")
    src = alert.get("src_ip", "?")
    src_port = alert.get("src_port", "?")
    dst = alert.get("dest_ip", "?")
    dst_port = alert.get("dest_port", "?")
    proto = alert.get("proto", "?")

    return (
        f"\U0001F6A8 PIROGUE ALERT\n"
        f"\n"
        f"Rule: {sig}\n"
        f"SID: {sid} | {proto}\n"
        f"Src: {src}:{src_port}\n"
        f"Dst: {dst}:{dst_port}\n"
        f"\n"
        f"{triage}"
    )


def send_signal_message(message: str, config: Config, logger: logging.Logger) -> bool:
    """Send a message via signal-cli. Returns True on success."""
    if not config.signal_account:
        logger.error("No signal_account configured — cannot send")
        return False

    for recipient in config.signal_recipients:
        cmd = [
            "signal-cli",
            "-a", config.signal_account,
            "send",
            "-m", message,
            recipient,
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode == 0:
                logger.info(f"Signal message sent to {recipient}")
                return True
            else:
                logger.error(f"signal-cli failed (rc={result.returncode}): {result.stderr[:200]}")
                return False
        except subprocess.TimeoutExpired:
            logger.error("signal-cli timed out (30s)")
            return False
        except FileNotFoundError:
            logger.error("signal-cli not found in PATH")
            return False
        except Exception as e:
            logger.error(f"signal-cli error: {e}")
            return False

    return False


# ---------------------------------------------------------------------------
# Main Processing Loop
# ---------------------------------------------------------------------------

def process_alert(alert: dict, config: Config, logger: logging.Logger,
                  dedup: DedupTracker, limiter: RateLimiter) -> bool:
    """Process a single alert event. Returns True if notification was sent."""

    a = alert.get("alert", {})
    sig = a.get("signature", "unknown")
    sid = a.get("signature_id", 0)
    severity = a.get("severity", 3)

    # Severity filter (Suricata: 1=highest, 3=lowest — inverted from what you'd expect)
    # We invert: config threshold 1=alert on everything, 3=only critical
    # Suricata severity 1 = most severe, so we alert when severity <= threshold
    # But for simplicity, just alert on everything and let AI triage handle priority
    logger.info(f"Alert: [{sid}] {sig} (severity={severity}) "
                f"{alert.get('src_ip', '?')} -> {alert.get('dest_ip', '?')}")

    # Dedup check
    if dedup.is_duplicate(alert):
        logger.info(f"  -> Suppressed (duplicate within {config.dedup_window_seconds}s window)")
        return False

    # Rate limit
    if not limiter.allow():
        logger.warning(f"  -> Rate limited ({config.max_alerts_per_minute}/min exceeded)")
        return False

    # AI triage (if enabled)
    triage_text = None
    if config.enable_ai_triage:
        logger.info("  -> Sending to Claude for triage...")
        t0 = time.time()
        triage_text = triage_with_claude(alert, config, logger)
        elapsed = time.time() - t0
        if triage_text:
            logger.info(f"  -> Triage received in {elapsed:.1f}s")
            if config.demo_mode:
                for line in triage_text.split("\n"):
                    logger.info(f"  >> {line}")
        else:
            logger.warning(f"  -> Triage failed after {elapsed:.1f}s, falling back to raw alert")

    # Format message
    if triage_text:
        message = format_enriched_alert(alert, triage_text)
    else:
        message = format_raw_alert(alert)

    # Send via Signal
    logger.info("  -> Sending Signal notification...")
    t0 = time.time()
    success = send_signal_message(message, config, logger)
    elapsed = time.time() - t0

    if success:
        logger.info(f"  -> Signal notification sent in {elapsed:.1f}s")
    else:
        logger.error(f"  -> Signal notification FAILED after {elapsed:.1f}s")

    return success


def run(config: Config):
    logger = setup_logging(config)

    logger.info("=" * 60)
    logger.info("PiRogue AI Triage Daemon starting")
    logger.info(f"  eve.json:     {config.eve_json_path}")
    logger.info(f"  AI triage:    {'ENABLED' if config.enable_ai_triage else 'DISABLED'}")
    logger.info(f"  Model:        {config.anthropic_model}")
    logger.info(f"  Signal from:  {config.signal_account or '(not set)'}")
    logger.info(f"  Signal to:    {', '.join(config.signal_recipients) or '(not set)'}")
    logger.info(f"  Dedup window: {config.dedup_window_seconds}s")
    logger.info(f"  Rate limit:   {config.max_alerts_per_minute}/min")
    logger.info(f"  Demo mode:    {'ON' if config.demo_mode else 'OFF'}")
    logger.info("=" * 60)

    if not config.anthropic_api_key and config.enable_ai_triage:
        logger.warning("ANTHROPIC_API_KEY not set — AI triage will be skipped")

    if not config.signal_account:
        logger.warning("signal_account not configured — notifications will fail")

    # State dir
    Path(config.state_dir).mkdir(parents=True, exist_ok=True)

    dedup = DedupTracker(config.dedup_window_seconds)
    limiter = RateLimiter(config.max_alerts_per_minute)
    tailer = EveTailer(config.eve_json_path, logger)

    # Stats
    stats = {"processed": 0, "alerted": 0, "deduped": 0, "errors": 0}

    # Graceful shutdown
    running = True
    def handle_signal(signum, frame):
        nonlocal running
        logger.info(f"Received signal {signum}, shutting down...")
        running = False

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    logger.info("Tailing eve.json — waiting for alerts...")

    for line in tailer.lines():
        if not running:
            break

        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        # Only process alert events
        if event.get("event_type") != "alert":
            continue

        stats["processed"] += 1

        try:
            sent = process_alert(event, config, logger, dedup, limiter)
            if sent:
                stats["alerted"] += 1
        except Exception as e:
            stats["errors"] += 1
            logger.error(f"Error processing alert: {e}", exc_info=True)

    # Shutdown summary
    logger.info("=" * 60)
    logger.info(f"Daemon stopped. Stats: {json.dumps(stats)}")
    logger.info("=" * 60)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="PiRogue AI Triage Daemon — Suricata → Claude → Signal"
    )
    parser.add_argument(
        "--config", "-c",
        type=str,
        help="Path to TOML config file",
    )
    parser.add_argument(
        "--eve-json",
        type=str,
        help="Override eve.json path",
    )
    parser.add_argument(
        "--signal-account",
        type=str,
        help="Signal account number (+1XXXXXXXXXX)",
    )
    parser.add_argument(
        "--signal-recipient",
        type=str,
        action="append",
        dest="signal_recipients",
        help="Signal recipient number (repeatable)",
    )
    parser.add_argument(
        "--no-ai",
        action="store_true",
        help="Disable AI triage, send raw alerts only",
    )
    parser.add_argument(
        "--demo",
        action="store_true",
        help="Enable demo mode (extra verbose logging)",
    )
    args = parser.parse_args()

    # Load config
    if args.config:
        config = Config.from_toml(args.config)
    else:
        config = Config()

    # CLI overrides
    if args.eve_json:
        config.eve_json_path = args.eve_json
    if args.signal_account:
        config.signal_account = args.signal_account
    if args.signal_recipients:
        config.signal_recipients = args.signal_recipients
    if args.no_ai:
        config.enable_ai_triage = False
    if args.demo:
        config.demo_mode = True

    # Env override
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if api_key:
        config.anthropic_api_key = api_key

    run(config)


if __name__ == "__main__":
    main()
