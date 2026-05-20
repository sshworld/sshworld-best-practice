#!/usr/bin/env python3
"""Claude Code custom dashboard statusline.

Output format:
🤖 Opus │ ████████░░ 80% │ 160K/200K │ $1.25 │ 5h: 42% (2h30m) │ 7d: 69%
"""
import datetime
import json
import os
import subprocess
import sys
import time
from pathlib import Path

CACHE_DIR = Path.home() / ".claude" / "cache" / "statusline"
CACHE_DIR.mkdir(parents=True, exist_ok=True)

CONFIG_FILE = Path.home() / ".claude" / "dashboard-config.json"
DEFAULT_CONFIG = {
    "plan_5h_limit_usd": 30.0,
    "plan_7d_limit_usd": 200.0,
    "context_window_default": 200_000,
    "context_window_1m": 1_000_000,
    "bar_width": 10,
    "color": True,
    "blocks_ttl_seconds": 30,
    "daily_ttl_seconds": 300,
    "ccusage_timeout_seconds": 12,
}


def load_config():
    cfg = dict(DEFAULT_CONFIG)
    if CONFIG_FILE.exists():
        try:
            cfg.update(json.loads(CONFIG_FILE.read_text()))
        except Exception:
            pass
    return cfg


C = {
    "reset": "\033[0m",
    "dim": "\033[2m",
    "bold": "\033[1m",
    "cyan": "\033[36m",
    "magenta": "\033[35m",
    "green": "\033[32m",
    "yellow": "\033[33m",
    "red": "\033[31m",
    "blue": "\033[34m",
    "gray": "\033[90m",
}


def color(text, name, use_color):
    if not use_color:
        return text
    return f"{C.get(name, '')}{text}{C['reset']}"


def heat_color(pct):
    if pct < 50:
        return "green"
    if pct < 80:
        return "yellow"
    return "red"


def cached_run(key, cmd, ttl):
    cache_file = CACHE_DIR / f"{key}.json"
    if cache_file.exists() and time.time() - cache_file.stat().st_mtime < ttl:
        try:
            return json.loads(cache_file.read_text())
        except Exception:
            pass
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True,
            timeout=load_config()["ccusage_timeout_seconds"],
        )
        if result.returncode == 0 and result.stdout.strip():
            data = json.loads(result.stdout)
            cache_file.write_text(json.dumps(data))
            return data
    except Exception:
        pass
    if cache_file.exists():
        try:
            return json.loads(cache_file.read_text())
        except Exception:
            pass
    return None


def get_last_context_tokens(transcript_path):
    if not transcript_path or not os.path.exists(transcript_path):
        return 0
    last_usage = None
    try:
        with open(transcript_path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            read_size = min(size, 256_000)
            f.seek(size - read_size)
            tail = f.read().decode("utf-8", errors="ignore")
        lines = tail.split("\n")
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                msg = entry.get("message", {})
                if msg.get("role") == "assistant" and "usage" in msg:
                    last_usage = msg["usage"]
            except Exception:
                continue
    except Exception:
        return 0
    if not last_usage:
        return 0
    return (
        last_usage.get("input_tokens", 0)
        + last_usage.get("cache_read_input_tokens", 0)
        + last_usage.get("cache_creation_input_tokens", 0)
    )


def fmt_tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 10_000:
        return f"{n / 1_000:.0f}K"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def progress_bar(pct, width, use_color):
    pct = max(0, min(100, pct))
    filled = round(width * pct / 100)
    bar = "█" * filled + "░" * (width - filled)
    return color(bar, heat_color(pct), use_color)


def fmt_time_left(minutes):
    if minutes <= 0:
        return "0m"
    minutes = int(minutes)
    h = minutes // 60
    m = minutes % 60
    if h == 0:
        return f"{m}m"
    if m == 0:
        return f"{h}h"
    return f"{h}h{m}m"


def ccusage_blocks(ttl):
    return cached_run(
        "blocks_active",
        ["npx", "-y", "ccusage@latest", "blocks", "--active", "--json", "--offline"],
        ttl,
    )


def ccusage_daily_7d(ttl):
    since = (datetime.date.today() - datetime.timedelta(days=6)).strftime("%Y%m%d")
    return cached_run(
        "daily_7d",
        ["npx", "-y", "ccusage@latest", "daily", "--since", since, "--json", "--offline"],
        ttl,
    )


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}

    cfg = load_config()
    use_color = bool(cfg.get("color", True)) and sys.stdout.isatty() or True

    model_info = data.get("model", {}) or {}
    model_name = model_info.get("display_name") or "Claude"
    model_id = model_info.get("id", "")
    session_cost = (data.get("cost", {}) or {}).get("total_cost_usd", 0.0)
    transcript_path = data.get("transcript_path", "")
    exceeds_200k = bool(data.get("exceeds_200k_tokens"))

    ctx_tokens = get_last_context_tokens(transcript_path)

    is_1m = (
        "[1m]" in model_id
        or "1m" in model_id.lower().split("-")[-1:]
        or exceeds_200k
        or ctx_tokens > cfg["context_window_default"]
    )
    ctx_window = cfg["context_window_1m"] if is_1m else cfg["context_window_default"]
    ctx_pct = (ctx_tokens / ctx_window) * 100 if ctx_window > 0 else 0

    blocks = ccusage_blocks(cfg["blocks_ttl_seconds"])
    block_pct = 0.0
    block_time = ""
    if blocks and blocks.get("blocks"):
        b = blocks["blocks"][0]
        block_cost = b.get("costUSD", 0) or 0
        block_pct = (block_cost / cfg["plan_5h_limit_usd"]) * 100 if cfg["plan_5h_limit_usd"] else 0
        remaining = (b.get("projection", {}) or {}).get("remainingMinutes", 0) or 0
        block_time = fmt_time_left(remaining)

    daily = ccusage_daily_7d(cfg["daily_ttl_seconds"])
    week_cost = 0.0
    if daily and isinstance(daily, dict):
        totals = daily.get("totals") or {}
        week_cost = totals.get("totalCost", 0) or 0
    week_pct = (week_cost / cfg["plan_7d_limit_usd"]) * 100 if cfg["plan_7d_limit_usd"] else 0

    sep = color(" │ ", "gray", use_color)
    bar = progress_bar(ctx_pct, cfg["bar_width"], use_color)
    ctx_str = f"{fmt_tokens(ctx_tokens)}/{fmt_tokens(ctx_window)}"

    parts = [
        f"🤖 {color(model_name, 'cyan', use_color)}",
        f"{bar} {color(f'{ctx_pct:.0f}%', heat_color(ctx_pct), use_color)}",
        color(ctx_str, "dim", use_color),
        color(f"${session_cost:.2f}", "yellow", use_color),
        (
            f"5h: {color(f'{block_pct:.0f}%', heat_color(block_pct), use_color)}"
            + (f" ({color(block_time, 'dim', use_color)})" if block_time else "")
        ),
        f"7d: {color(f'{week_pct:.0f}%', heat_color(week_pct), use_color)}",
    ]

    sys.stdout.write(sep.join(parts))
    sys.stdout.flush()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.stdout.write(f"🤖 Claude (statusline error: {type(e).__name__})")
        sys.stdout.flush()
