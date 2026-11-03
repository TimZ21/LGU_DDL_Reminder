#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_RUNTIME="${1:-win-x64}"
case "$TASK_RUNTIME" in win-x64|win-arm64) ;; *) echo 'Use win-x64 or win-arm64.' >&2; exit 2 ;; esac
TASK_DOTNET="${DDL_DOTNET:-dotnet}"
if [ -x "$TASK_ROOT/.local/dotnet/dotnet" ] && [ -z "${DDL_DOTNET:-}" ]; then TASK_DOTNET="$TASK_ROOT/.local/dotnet/dotnet"; fi
export DOTNET_CLI_HOME="$TASK_ROOT/.local/dotnet-home"
export NUGET_PACKAGES="$TASK_ROOT/.local/nuget-packages"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
export DOTNET_GENERATE_ASPNET_CERTIFICATE=false
export AVALONIA_TELEMETRY_OPTOUT=1
TASK_OUTPUT="$TASK_ROOT/dist/windows/1.2.0/$TASK_RUNTIME"
cd "$TASK_ROOT"
"$TASK_DOTNET" run --project windows/Shiqi.Tests/Shiqi.Tests.csproj --configuration Release
"$TASK_DOTNET" publish windows/Shiqi.Desktop/Shiqi.Desktop.csproj --configuration Release \
  --runtime "$TASK_RUNTIME" --self-contained true -p:PublishSingleFile=false -p:PublishTrimmed=false \
  -o "$TASK_OUTPUT"
cp "$TASK_ROOT/windows/INSTALL.txt" "$TASK_OUTPUT/INSTALL.txt"
cp "$TASK_ROOT/LICENSE" "$TASK_OUTPUT/LICENSE.txt"
cp "$TASK_ROOT/windows/THIRD-PARTY-NOTICES.txt" "$TASK_OUTPUT/THIRD-PARTY-NOTICES.txt"
python3 "$TASK_ROOT/windows/tools/package.py" "$TASK_OUTPUT" "$TASK_RUNTIME"
