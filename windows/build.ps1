param([ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:AVALONIA_TELEMETRY_OPTOUT = '1'
$TaskRoot = Split-Path -Parent $PSScriptRoot
$TaskOutput = Join-Path $TaskRoot "dist/windows/1.2.0/$Runtime"
Push-Location $TaskRoot
try {
    dotnet run --project windows/Shiqi.Tests/Shiqi.Tests.csproj --configuration Release
    if ($LASTEXITCODE -ne 0) { throw 'Windows tests failed.' }
    dotnet publish windows/Shiqi.Desktop/Shiqi.Desktop.csproj --configuration Release `
        --runtime $Runtime --self-contained true -p:PublishSingleFile=false -p:PublishTrimmed=false -o $TaskOutput
    if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
    Copy-Item windows/INSTALL.txt "$TaskOutput/INSTALL.txt"
    Copy-Item LICENSE "$TaskOutput/LICENSE.txt"
    Copy-Item windows/THIRD-PARTY-NOTICES.txt "$TaskOutput/THIRD-PARTY-NOTICES.txt"
    python windows/tools/package.py $TaskOutput $Runtime
    if ($LASTEXITCODE -ne 0) { throw 'Packaging verification failed.' }
} finally { Pop-Location }
