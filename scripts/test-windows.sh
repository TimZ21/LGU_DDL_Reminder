#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_DOTNET="${DDL_DOTNET:-dotnet}"
if [ -x "$TASK_ROOT/.local/dotnet/dotnet" ] && [ -z "${DDL_DOTNET:-}" ]; then TASK_DOTNET="$TASK_ROOT/.local/dotnet/dotnet"; fi
export DOTNET_CLI_HOME="$TASK_ROOT/.local/dotnet-home"
export NUGET_PACKAGES="$TASK_ROOT/.local/nuget-packages"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
export DOTNET_GENERATE_ASPNET_CERTIFICATE=false
cd "$TASK_ROOT"
"$TASK_DOTNET" run --project windows/Shiqi.Tests/Shiqi.Tests.csproj --configuration Release
