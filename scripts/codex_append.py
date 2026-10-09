#!/usr/bin/env python3
"""Append each supplied deadline as a separate entry for the user to manage in the app.

Input: {"items": [{"title": "...", "course": "...", "dueAt": "2026-10-19T23:59:00+08:00",
                   "hasTime": true, "notes": "..."}]}
Date-only entries use YYYY-MM-DD and hasTime=false. Every item is appended as a
new entry; this script never reads or changes the app's calendar/task data.
"""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import uuid
from zoneinfo import ZoneInfo

APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)


def deadline(item: dict, zone: ZoneInfo) -> dict:
    title = item["title"]
    course = item.get("course", "")
    due_at = item["dueAt"]
    has_time = item["hasTime"]
    if not isinstance(title, str) or not title.strip():
        raise ValueError("title must be nonempty text")
    if not isinstance(course, str) or not isinstance(has_time, bool):
        raise ValueError("course must be text and hasTime must be boolean")
    if has_time:
        date = datetime.fromisoformat(due_at.replace("Z", "+00:00"))
        if date.tzinfo is None:
            raise ValueError("timed dueAt needs an explicit time zone")
    else:
        date = datetime.strptime(due_at, "%Y-%m-%d").replace(tzinfo=zone)
    notes = item.get("notes", "")
    if not isinstance(notes, str):
        raise ValueError("notes must be text")
    result = {
        "id": "codex:" + str(uuid.uuid4()),
        "title": title,
        "course": course,
        "notes": notes,
        "dueDate": (date.astimezone(timezone.utc) - APPLE_EPOCH).total_seconds(),
        "hasTime": has_time,
        "source": "outlook",
        "completed": False,
    }
    link = item.get("link")
    if link is not None:
        if not isinstance(link, str) or not link.startswith("https://"):
            raise ValueError("link must be an HTTPS URL")
        result["link"] = link
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="JSON file containing user-approved items")
    parser.add_argument("--output", type=Path, default=Path.home() / "Library/Application Support/DDLReminder/CodexDeadlines.jsonl")
    parser.add_argument("--time-zone", default="Asia/Shanghai")
    args = parser.parse_args()
    payload = json.loads(args.input.read_text(encoding="utf-8"))
    items = payload["items"]
    if not isinstance(items, list) or not items:
        raise ValueError("items must be a nonempty list")
    records = [deadline(item, ZoneInfo(args.time_zone)) for item in items]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    data = b"".join((json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8") for record in records)
    descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(descriptor, data)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    print(f"Appended {len(records)} entries to {args.output}")


if __name__ == "__main__":
    main()
