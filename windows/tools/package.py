"""Package only a published Windows folder; verify the executable format and hash the ZIP."""
from pathlib import Path
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import zipfile

output, runtime = Path(sys.argv[1]).resolve(), sys.argv[2]
source = Path(__file__).resolve().parents[2]
if runtime not in {"win-x64", "win-arm64"}:
    raise SystemExit("Unsupported Windows architecture")
exe = (output / "Shiqi.exe").read_bytes()
if exe[:2] != b"MZ":
    raise SystemExit("Missing Windows executable")
pe = struct.unpack_from("<I", exe, 0x3C)[0]
expected = 0x8664 if runtime == "win-x64" else 0xAA64
if exe[pe:pe + 4] != b"PE\0\0" or struct.unpack_from("<H", exe, pe + 4)[0] != expected:
    raise SystemExit("Executable architecture does not match package")
for dependency in ["Shiqi.dll", "Shiqi.Core.dll", "coreclr.dll", "hostfxr.dll", "Assets/Shiqi.ico", "INSTALL.txt"]:
    if not (output / dependency).is_file():
        raise SystemExit(f"Missing portable runtime file: {dependency}")
try:
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=output, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=output, text=True).strip())
except (OSError, subprocess.CalledProcessError):
    commit, dirty = "unknown", True
info = {
    "version": "1.2.0-windows-preview.1", "runtime": runtime,
    "sourceBaseCommit": commit, "hasUncommittedChanges": dirty,
    "signature": "unsigned", "distribution": "Windows preview; not verified on physical Windows hardware",
    "runtimeIncluded": True, "remindersRequireRunningApp": True,
}
source_digest = hashlib.sha256()
for file in sorted((source / "windows").rglob("*")):
    if file.is_file() and not any(part in {"obj", "bin"} for part in file.relative_to(source).parts):
        source_digest.update(str(file.relative_to(source)).replace('\\', '/').encode())
        source_digest.update(file.read_bytes())
info["windowsSourceSha256"] = source_digest.hexdigest()

# Preserve upstream copyright/license texts alongside the self-contained runtime.
licenses = output / "licenses"
licenses.mkdir(exist_ok=True)
for file in (source / "windows" / "licenses").iterdir():
    if file.is_file():
        shutil.copy2(file, licenses / file.name)
assets_path = source / "windows/Shiqi.Desktop/obj/project.assets.json"
if not assets_path.exists():
    raise SystemExit("Missing restored dependency inventory")
assets = json.loads(assets_path.read_text(encoding="utf-8-sig"))
dependencies = []
for name, library in sorted(assets["libraries"].items()):
    if library.get("type") != "package":
        continue
    dependencies.append(name)
    for folder in assets.get("packageFolders", {}):
        root = Path(folder) / library.get("path", name.lower())
        if not root.is_dir():
            continue
        for file in root.rglob("*"):
            normalized = file.name.lower().replace('-', '').replace('_', '').replace(' ', '')
            if file.is_file() and any(word in normalized for word in ["license", "licence", "copying", "thirdpartynotices"]) and file.stat().st_size < 5000000:
                destination = licenses / name.replace('/', '-') / file.relative_to(root)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(file, destination)
runtime_config = json.loads((output / "Shiqi.runtimeconfig.json").read_text(encoding="utf-8"))
for framework in runtime_config.get("runtimeOptions", {}).get("includedFrameworks", []):
    if framework.get("name") == "Microsoft.NETCore.App":
        for folder in assets.get("packageFolders", {}):
            root = Path(folder) / f"microsoft.netcore.app.runtime.{runtime}" / framework["version"]
            for name in ["LICENSE.TXT", "THIRD-PARTY-NOTICES.TXT"]:
                if (root / name).exists():
                    destination = licenses / f'dotnet-{framework["version"]}'
                    destination.mkdir(exist_ok=True)
                    shutil.copy2(root / name, destination / name)
(licenses / "dependencies.json").write_text(json.dumps(dependencies, indent=2) + "\n", encoding="utf-8")
(output / "BUILD-INFO.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
archive = output.parent / f"Shiqi-1.2.0-windows-preview.1-{runtime}-unsigned.zip"
files = [file for file in sorted(output.rglob("*")) if file.is_file() and file.suffix != ".pdb"]
for file in files:
    if file.name in {"deadlines.json", "deadlines.backup.json"} or file.suffix in {".pfx", ".key", ".log"}:
        raise SystemExit("Private data found in publish directory; refusing to package")
pending = archive.with_suffix(".pending.zip")
with zipfile.ZipFile(pending, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    for file in files:
        bundle.write(file, Path("Shiqi") / file.relative_to(output))
with zipfile.ZipFile(pending) as bundle:
    if bundle.testzip() is not None:
        raise SystemExit("Archive integrity check failed")
pending.replace(archive)
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix(".sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
print(f"Windows package: {archive}\nSHA-256: {digest}\nStatus: unsigned preview; Windows smoke test still required.")
