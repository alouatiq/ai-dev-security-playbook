<#
.SYNOPSIS
    Deep scan for Windows. Run from the project folder, or pass -ProjectPath.
.DESCRIPTION
    Downloads pinned scanners into a per-user cache (nothing is installed),
    verifies each SHA-256 against tools.lock, runs them read-only, and writes
    raw results to <project>\.devsec\ for index.html to pick up. .devsec holds
    a self-ignoring .gitignore, so `git status` stays clean.

    Keep this file ASCII-only: Windows PowerShell 5.1 reads unmarked scripts
    using the ANSI codepage (see audit/README.md).
#>
param([string]$ProjectPath = (Get-Location).Path)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Project = (Resolve-Path -LiteralPath $ProjectPath).Path
$Lock = Join-Path $PSScriptRoot 'tools.lock'
$Cache = Join-Path $env:LOCALAPPDATA 'ai-dev-security-playbook'
$Out = Join-Path $Project '.devsec'
$Platform = 'windows-x64'
$Started = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$States = New-Object System.Collections.ArrayList
$Utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not [Environment]::Is64BitOperatingSystem) { Write-Error 'A 64-bit OS is required.'; exit 2 }
New-Item -ItemType Directory -Force -Path $Out, $Cache | Out-Null
[IO.File]::WriteAllText((Join-Path $Out '.gitignore'), "*`n", $Utf8)
Get-ChildItem -LiteralPath $Out -Filter *.json -File | Remove-Item -Force

function Write-Status([string]$Phase) {
    # Written to a temp name first so the page never reads a half-written file.
    $json = @{ schema = 1; phase = $Phase; platform = $Platform; root = $Project; started = $Started; tools = @($States) } |
        ConvertTo-Json -Depth 4
    $tmp = Join-Path $Out 'status.json.tmp'
    [IO.File]::WriteAllText($tmp, $json, $Utf8)
    Move-Item -LiteralPath $tmp -Destination (Join-Path $Out 'status.json') -Force
}

function Add-Record([string]$Tool, [string]$State, [string]$Version, [string]$Note) {
    [void]$States.Add(@{ tool = $Tool; state = $State; version = $Version; note = $Note })
    Write-Host ("  [{0}] {1} {2}" -f $State, $Tool, $Note)
    Write-Status 'running'
}

function Get-LockEntry([string]$Tool) {
    foreach ($line in Get-Content -LiteralPath $Lock) {
        if ($line.StartsWith('#') -or -not $line.Trim()) { continue }
        $f = $line -split '\s+'
        if ($f[0] -eq $Tool -and ($f[2] -eq $Platform -or $f[2] -eq 'any')) {
            return @{ Version = $f[1]; Sha = $f[3]; Asset = $f[4] }
        }
    }
    return $null
}

function Get-Verified([string]$Url, [string]$Dest, [string]$Sha) {
    try { Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop } catch { return $false }
    $actual = (Get-FileHash -LiteralPath $Dest -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Sha) {
        Remove-Item -LiteralPath $Dest -Force
        Write-Host "  HASH MISMATCH for $Url - refusing to run it"
        return $false
    }
    return $true
}

function Get-Tool([string]$Tool, [string]$Repo) {
    $e = Get-LockEntry $Tool
    if (-not $e) { return $null }
    $dir = Join-Path $Cache "$Tool-$($e.Version)-$Platform"
    $bin = Join-Path $dir "$Tool.exe"
    if (-not (Test-Path -LiteralPath $bin)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $dest = Join-Path $dir $e.Asset
        $url = "https://github.com/$Repo/releases/download/v$($e.Version)/$($e.Asset)"
        if (-not (Get-Verified $url $dest $e.Sha)) { return $null }
        if ($e.Asset -like '*.zip') {
            Expand-Archive -LiteralPath $dest -DestinationPath $dir -Force
            $found = Get-ChildItem -LiteralPath $dir -Recurse -Filter "$Tool.exe" | Select-Object -First 1
            if (-not $found) { return $null }
            $bin = $found.FullName
        } else {
            Move-Item -LiteralPath $dest -Destination $bin -Force
        }
    }
    $hit = Get-ChildItem -LiteralPath $dir -Recurse -Filter "$Tool.exe" | Select-Object -First 1
    return @{ Bin = $hit.FullName; Version = $e.Version }
}

function Get-Rules {
    # Rules stay a download, never vendored: opengrep-rules carries the Commons
    # Clause, so this repo must not redistribute them.
    $e = Get-LockEntry 'opengrep-rules'
    $dir = Join-Path $Cache "opengrep-rules-$($e.Version)"
    $rules = Join-Path $dir "opengrep-rules-$($e.Version)"
    if (-not (Test-Path -LiteralPath $rules)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $dest = Join-Path $dir $e.Asset
        if (-not (Get-Verified "https://github.com/opengrep/opengrep-rules/archive/$($e.Asset)" $dest $e.Sha)) { return $null }
        # Full path: under Git Bash, PATH finds a tar that reads "C:" as a remote host.
        & (Join-Path $env:SystemRoot 'System32\tar.exe') -xzf $dest -C $dir 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
    }
    return $rules
}

Write-Host ""
Write-Host "==== Deep scan: $Project ($Platform) ===="
Write-Host "Results: $Out"
Write-Host ""
Write-Status 'running'

# --- gitleaks: secrets in files and full Git history ---
$t = Get-Tool 'gitleaks' 'gitleaks/gitleaks'
if ($t) {
    & git -C $Project rev-parse --is-inside-work-tree 2>$null | Out-Null
    $isGit = ($LASTEXITCODE -eq 0)
    $mode = if ($isGit) { 'git' } else { 'dir' }
    $note = if ($isGit) { 'scanned git' } else { 'scanned dir (not a Git repository: history skipped)' }
    if ($isGit -and (& git -C $Project rev-parse --is-shallow-repository) -eq 'true') {
        $note += ' (shallow clone: history incomplete)'
    }
    # --redact=100 keeps secret values out of the report on disk.
    & $t.Bin $mode $Project --redact=100 --no-banner --log-level error `
        --report-format json --report-path (Join-Path $Out 'gitleaks.json') --exit-code 0
    if ($LASTEXITCODE -eq 0) { Add-Record 'gitleaks' 'ok' $t.Version $note }
    else { Add-Record 'gitleaks' 'failed' $t.Version 'scanner error' }
} else { Add-Record 'gitleaks' 'failed' '' 'download or verification failed' }

# --- osv-scanner: dependency vulnerabilities (lockfiles and manifests) ---
$t = Get-Tool 'osv-scanner' 'google/osv-scanner'
if ($t) {
    & $t.Bin scan source -r --format json --output-file (Join-Path $Out 'osv-scanner.json') $Project *> $null
    $code = $LASTEXITCODE
    # 0 = clean, 1 = vulnerabilities found, 128 = nothing to scan.
    if ($code -eq 0 -or $code -eq 1) { Add-Record 'osv-scanner' 'ok' $t.Version 'scan complete' }
    elseif ($code -eq 128) { Add-Record 'osv-scanner' 'ok' $t.Version 'no lockfiles found' }
    else { Add-Record 'osv-scanner' 'failed' $t.Version "exit code $code" }
} else { Add-Record 'osv-scanner' 'failed' '' 'download or verification failed' }

# --- trivy: vulnerabilities and IaC / Dockerfile misconfiguration ---
$t = Get-Tool 'trivy' 'aquasecurity/trivy'
if ($t) {
    $env:TRIVY_CACHE_DIR = Join-Path $Cache 'trivy-db'
    & $t.Bin fs --quiet --scanners 'vuln,misconfig' --format json --output (Join-Path $Out 'trivy.json') $Project *> $null
    $code = $LASTEXITCODE
    if ($code -eq 0) { Add-Record 'trivy' 'ok' $t.Version 'scan complete' }
    else { Add-Record 'trivy' 'failed' $t.Version "exit code $code" }
} else { Add-Record 'trivy' 'failed' '' 'download or verification failed' }

# --- zizmor: GitHub Actions workflow security ---
if (-not (Test-Path -LiteralPath (Join-Path $Project '.github\workflows'))) {
    Add-Record 'zizmor' 'skipped' '' 'no GitHub Actions workflows'
} else {
    $t = Get-Tool 'zizmor' 'zizmorcore/zizmor'
    if ($t) {
        $zPath = Join-Path $Out 'zizmor.json'
        $zOut = & $t.Bin --format=json --no-progress --offline $Project 2>$null
        $code = $LASTEXITCODE
        # zizmor exits 10-14 when it has findings.
        if ($code -eq 0 -or $code -ge 10) {
            [IO.File]::WriteAllText($zPath, ($zOut -join "`n"), $Utf8)
            Add-Record 'zizmor' 'ok' $t.Version 'scan complete'
        } else { Add-Record 'zizmor' 'failed' $t.Version "exit code $code" }
    } else { Add-Record 'zizmor' 'failed' '' 'download or verification failed' }
}

# --- opengrep: SAST. Open-source engine, compatible with Semgrep rules ---
$map = [ordered]@{ py = 'python'; js = 'javascript'; jsx = 'javascript'; ts = 'typescript'; tsx = 'typescript'
                   java = 'java'; go = 'go'; rb = 'ruby'; php = 'php'; cs = 'csharp' }
$found = @{}
Get-ChildItem -LiteralPath $Project -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git)[\\/]' } |
    ForEach-Object { $x = $_.Extension.TrimStart('.').ToLowerInvariant(); if ($map.Contains($x)) { $found[$map[$x]] = $true } }
if ($found.Count -eq 0) {
    Add-Record 'opengrep' 'skipped' '' 'no supported source language found'
} else {
    $t = Get-Tool 'opengrep' 'opengrep/opengrep'
    $rules = Get-Rules
    if ($t -and $rules) {
        $cfg = @()
        foreach ($lang in $found.Keys) { $cfg += @('--config', (Join-Path $rules $lang)) }
        & $t.Bin scan --json --quiet --output (Join-Path $Out 'opengrep.json') @cfg $Project *> $null
        $code = $LASTEXITCODE
        if ($code -eq 0 -or $code -eq 1) { Add-Record 'opengrep' 'ok' $t.Version ("languages: " + ($found.Keys -join ' ')) }
        else { Add-Record 'opengrep' 'failed' $t.Version "exit code $code" }
    } else { Add-Record 'opengrep' 'failed' '' 'download or verification failed' }
}

Write-Status 'done'
Write-Host ""
Write-Host "Done. Go back to the browser page: results load automatically."
Write-Host "If they do not, drop the files from $Out onto the page."
