#!/usr/bin/env python3
"""Hand confirmed Outlook deadlines from Codex to the running Shiqi app.

Usage: python3 scripts/codex_import.py /path/to/deadlines.json
The app validates the versioned JSON package and imports it on launch, focus, or
within one minute while running. This script never opens the mailbox.
"""

import json
import os
from pathlib import Path
import sys
import tempfile
import uuid


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python3 scripts/codex_import.py /path/to/deadlines.json", file=sys.stderr)
        return 2
    source = Path(sys.argv[1])
    data = source.read_bytes()
    if not data or len(data) > 1024 * 1024:
        raise ValueError("JSON file must be between 1 byte and 1 MB")
    package = json.loads(data)
    if not isinstance(package, dict) or package.get("version") != 1 or not isinstance(package.get("items"), list):
        raise ValueError("Expected a version 1 package with an items array")
    inbox = Path.home() / "Library" / "Application Support" / "DDLReminder" / "CodexInbox"
    inbox.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(inbox, 0o700)
    fd, temporary = tempfile.mkstemp(prefix=".codex-", suffix=".tmp", dir=inbox)
    target = inbox / f"codex-{uuid.uuid4().hex}.json"
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"Queued {len(package['items'])} deadline(s) for Shiqi: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
