<#
.SYNOPSIS
    Portable, project-agnostic security audit for any repo (Python backend,
    Node frontend, monorepo, or either alone).
.DESCRIPTION
    Runs the automatable controls documented in ../README.md, classifies each
    finding by severity, and prints an overall deploy-readiness verdict:
      - LOW RISK      : all clear, safe to deploy to dev
      - ACCEPTED RISK : warnings only, no criticals - deploy if accepted
      - CRITICAL      : blocking finding - do not deploy
    A markdown report is written to <RepoPath>/audit/reports/.
.PARAMETER RepoPath
    Path to the repository to audit. Defaults to the current directory.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File run-audit.ps1 -RepoPath C:\Projects\SomeRepo
#>

param(
    [string]$RepoPath = (Get-Location).Path
)

$ErrorActionPreference = 'Continue'
$RepoPath = (Resolve-Path $RepoPath).Path
$PlaybookName = 'AI & Developer Security + Deployment Playbook'
$PlaybookRepository = 'https://github.com/alouatiq/ai-dev-security-playbook'
$PlaybookMaintainer = 'Dr. AL OUATIQ H.'
$PlaybookWebsite = 'https://www.alouatiq.com'

# Directories to always skip when scanning
$ExcludeRegex = '\\(node_modules|\.git|dist|build|venv|\.venv|__pycache__|coverage|\.next|out)(\\|$)'

$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Id, [string]$Status, [string]$Severity, [string]$Msg)
    $script:Results.Add([pscustomobject]@{ Id = $Id; Status = $Status; Severity = $Severity; Message = $Msg })
    $color = switch ($Status) { 'PASS' { 'Green' }; 'WARN' { 'Yellow' }; 'FAIL' { 'Red' } }
    Write-Host ("  [{0}] {1,-6} {2}" -f $Status, $Id, $Msg) -ForegroundColor $color
}

function Get-ProjectFiles {
    param([string]$Filter)
    Get-ChildItem -Path $RepoPath -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $ExcludeRegex }
}

Write-Host ""
Write-Host "==== Security audit: $RepoPath ====" -ForegroundColor Cyan
Write-Host "Tooling: $PlaybookName by $PlaybookMaintainer" -ForegroundColor DarkGray
Write-Host "Source: $PlaybookRepository | Website: $PlaybookWebsite" -ForegroundColor DarkGray
Write-Host ""

# --- F-03  CORS not wildcard (Medium) ---
$pyFiles = Get-ProjectFiles -Filter '*.py'
$corsHit = $null
if ($pyFiles) {
    $corsHit = $pyFiles | Select-String -Pattern 'allow_origin_regex\s*=\s*r?"\.\*"|Access-Control-Allow-Origin.*\*' -ErrorAction SilentlyContinue
}
if ($corsHit) { Add-Result -Id 'F-03' -Status 'FAIL' -Severity 'Medium' -Msg 'CORS allows any origin (wildcard) in application code' }
else { Add-Result -Id 'F-03' -Status 'PASS' -Severity 'Medium' -Msg 'CORS is not a catch-all wildcard' }

# --- F-01  Auth dependency present on API routes (Critical) ---
$jsTsFiles = @()
$jsTsFiles += Get-ProjectFiles -Filter '*.ts'
$jsTsFiles += Get-ProjectFiles -Filter '*.tsx'
$jsTsFiles += Get-ProjectFiles -Filter '*.js'

$hasAuth = $false
if ($pyFiles) {
    $hasAuth = [bool]($pyFiles | Select-String -Pattern 'Depends\(|Security\(|HTTPBearer|OAuth2|require_auth|login_required|jwt_required' -ErrorAction SilentlyContinue)
}
$hasAuthJs = $false
if ($jsTsFiles) {
    $hasAuthJs = [bool]($jsTsFiles | Select-String -Pattern 'passport\.|verifyToken|authMiddleware|requireAuth|jwt\.verify' -ErrorAction SilentlyContinue)
}
if ($hasAuth -or $hasAuthJs) { Add-Result -Id 'F-01' -Status 'PASS' -Severity 'Critical' -Msg 'API routes declare an auth/security dependency' }
elseif ($pyFiles -or $jsTsFiles) { Add-Result -Id 'F-01' -Status 'FAIL' -Severity 'Critical' -Msg 'No auth dependency found on any route - endpoints may be unauthenticated' }
else { Add-Result -Id 'F-01' -Status 'WARN' -Severity 'Critical' -Msg 'No backend source found - skipped' }

# --- G-03  No secret files tracked by git (Critical) ---
Push-Location $RepoPath
$isGitRepo = ((git rev-parse --is-inside-work-tree 2>$null) -eq 'true')
$tracked = @()
if ($isGitRepo) {
    $tracked = git ls-files 2>$null | Where-Object {
        $_ -match '(^|/)\.env$' -or $_ -match '\.env\.(local|prod|production)$' -or
        $_ -match '\.pem$' -or $_ -match '\.key$' -or $_ -match '_msal_cache' -or $_ -match 'id_rsa$'
    }
}
Pop-Location
if (-not $isGitRepo) { Add-Result -Id 'G-03' -Status 'WARN' -Severity 'Critical' -Msg 'Not a git repository - skipped' }
elseif ($tracked) { Add-Result -Id 'G-03' -Status 'FAIL' -Severity 'Critical' -Msg ("Secret-like files tracked by git: " + ($tracked -join ', ')) }
else { Add-Result -Id 'G-03' -Status 'PASS' -Severity 'Critical' -Msg 'No .env / key / token-cache files tracked by git' }

# --- G-01  SQL parameterization spot check (Critical) ---
$banned = 'f"[^"]*\{[^}]+\}[^"]*"'
$sqlHits = $null
if ($pyFiles) {
    $sqlHits = $pyFiles | Select-String -Pattern $banned -ErrorAction SilentlyContinue |
        Where-Object { $_.Line -match 'execute|cursor|SELECT|INSERT|UPDATE|DELETE|FROM|WHERE' }
}
if ($sqlHits) { Add-Result -Id 'G-01' -Status 'FAIL' -Severity 'Critical' -Msg 'Possible user input interpolated into SQL (f-string) - review query construction' }
else { Add-Result -Id 'G-01' -Status 'PASS' -Severity 'Critical' -Msg 'No obvious f-string-interpolated SQL found' }

# --- G-02  No XSS sinks in frontend (High) ---
if ($jsTsFiles) {
    $xss = $jsTsFiles | Select-String -Pattern 'dangerouslySetInnerHTML|\.innerHTML\s*=|eval\(' -ErrorAction SilentlyContinue
    if ($xss) { Add-Result -Id 'G-02' -Status 'FAIL' -Severity 'High' -Msg 'XSS sink found (dangerouslySetInnerHTML / innerHTML / eval)' }
    else { Add-Result -Id 'G-02' -Status 'PASS' -Severity 'High' -Msg 'No XSS sinks found in frontend source' }
} else { Add-Result -Id 'G-02' -Status 'WARN' -Severity 'High' -Msg 'No frontend source found - skipped' }

# --- F-09  Dockerfiles set a non-root USER (Medium) ---
$dockerfiles = Get-ChildItem -Path $RepoPath -Recurse -File -Filter 'Dockerfile*' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $ExcludeRegex }
if (-not $dockerfiles) { Add-Result -Id 'F-09' -Status 'WARN' -Severity 'Medium' -Msg 'No Dockerfile found - skipped' }
else {
    foreach ($df in $dockerfiles) {
        $relDf = $df.FullName.Substring($RepoPath.Length).TrimStart('\','/')
        if (Select-String -Path $df.FullName -Pattern '^\s*USER\s+\S' -Quiet -ErrorAction SilentlyContinue) {
            Add-Result -Id 'F-09' -Status 'PASS' -Severity 'Medium' -Msg "$relDf sets a non-root USER"
        } else {
            Add-Result -Id 'F-09' -Status 'FAIL' -Severity 'Medium' -Msg "$relDf has no USER directive - container runs as root"
        }
    }
}

# --- F-07  Python deps pinned (Low) ---
# PASS requires every real dependency line to be exactly pinned (==) or the
# file to carry hashes. Absence of ">="/"~=" is NOT sufficient on its own -
# a bare "requests" line (no operator at all) is the least-pinned case and
# must not silently pass.
$reqFiles = Get-ChildItem -Path $RepoPath -Recurse -File -Filter 'requirements*.txt' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $ExcludeRegex }
if (-not $reqFiles) { Add-Result -Id 'F-07' -Status 'WARN' -Severity 'Low' -Msg 'No requirements*.txt found - skipped' }
else {
    foreach ($rf in $reqFiles) {
        $relRf = $rf.FullName.Substring($RepoPath.Length).TrimStart('\','/')
        $hasHash = Select-String -Path $rf.FullName -Pattern '--hash=' -Quiet -ErrorAction SilentlyContinue
        if ($hasHash) {
            Add-Result -Id 'F-07' -Status 'PASS' -Severity 'Low' -Msg "$relRf is pinned (hashed lock file)"
        } else {
            $lines = Get-Content -Path $rf.FullName -ErrorAction SilentlyContinue
            $unpinnedLines = $lines | Where-Object {
                $_.Trim() -ne '' -and $_ -notmatch '^\s*(#|-r |-e |--)' -and $_ -notmatch '=='
            }
            if (-not $unpinnedLines) { Add-Result -Id 'F-07' -Status 'PASS' -Severity 'Low' -Msg "$relRf is pinned (==)" }
            else { Add-Result -Id 'F-07' -Status 'WARN' -Severity 'Low' -Msg "$relRf has unpinned dependencies: $($unpinnedLines -join '; ')" }
        }
    }
}

# --- G-05  npm audit (High for High/Critical CVEs) ---
$pkgJsons = Get-ChildItem -Path $RepoPath -Recurse -File -Filter 'package.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $ExcludeRegex }
if (-not $pkgJsons) { Add-Result -Id 'G-05' -Status 'WARN' -Severity 'High' -Msg 'No package.json found - skipped' }
else {
    foreach ($pj in $pkgJsons) {
        $pjDir = $pj.DirectoryName
        $relPj = $pjDir.Substring($RepoPath.Length).TrimStart('\','/')
        if ($relPj -eq '') { $relPj = '.' }
        if (-not (Test-Path (Join-Path $pjDir 'node_modules'))) {
            Add-Result -Id 'G-05' -Status 'WARN' -Severity 'High' -Msg "$relPj - node_modules not installed, npm audit skipped (run npm ci first)"
            continue
        }
        Push-Location $pjDir
        $auditJson = npm audit --json 2>$null | Out-String
        Pop-Location
        try {
            $a = $auditJson | ConvertFrom-Json
            $v = $a.metadata.vulnerabilities
            $hc = [int]$v.high + [int]$v.critical
            if ($hc -gt 0) { Add-Result -Id 'G-05' -Status 'FAIL' -Severity 'High' -Msg "$relPj npm audit: $($v.critical) critical, $($v.high) high" }
            elseif (([int]$v.moderate + [int]$v.low) -gt 0) { Add-Result -Id 'G-05' -Status 'WARN' -Severity 'High' -Msg "$relPj npm audit: $($v.moderate) moderate, $($v.low) low" }
            else { Add-Result -Id 'G-05' -Status 'PASS' -Severity 'High' -Msg "$relPj npm audit: 0 vulnerabilities" }
        } catch { Add-Result -Id 'G-05' -Status 'WARN' -Severity 'High' -Msg "$relPj npm audit output could not be parsed" }
    }
}

# --- F-07b  pip-audit (High for known CVEs) ---
$pipAudit = Get-Command pip-audit -ErrorAction SilentlyContinue
if (-not $pipAudit) { Add-Result -Id 'F-07b' -Status 'WARN' -Severity 'High' -Msg 'pip-audit not installed (pip install pip-audit) - skipped' }
elseif (-not $reqFiles) { Add-Result -Id 'F-07b' -Status 'WARN' -Severity 'High' -Msg 'No requirements*.txt found - skipped' }
else {
    foreach ($rf in $reqFiles) {
        $relRf2 = $rf.FullName.Substring($RepoPath.Length).TrimStart('\','/')
        pip-audit -r $rf.FullName *> $null
        if ($LASTEXITCODE -eq 0) { Add-Result -Id 'F-07b' -Status 'PASS' -Severity 'High' -Msg "$relRf2 - pip-audit: no known vulnerabilities" }
        else { Add-Result -Id 'F-07b' -Status 'FAIL' -Severity 'High' -Msg "$relRf2 - pip-audit reported vulnerabilities" }
    }
}

# --- F-02  Hardcoded http:// in frontend API client (Low, informational) ---
$apiClients = @()
if ($jsTsFiles) { $apiClients = $jsTsFiles | Where-Object { $_.Name -match 'api\.(ts|js|tsx|jsx)$' } }
$httpHit = $null
if ($apiClients) { $httpHit = $apiClients | Select-String -Pattern 'http://' -ErrorAction SilentlyContinue }
if ($httpHit) { Add-Result -Id 'F-02' -Status 'WARN' -Severity 'Low' -Msg 'Frontend API client contains http:// - confirm production uses HTTPS/same-origin' }
else { Add-Result -Id 'F-02' -Status 'PASS' -Severity 'Low' -Msg 'No hardcoded http:// found in frontend API client(s)' }

# ==== Verdict ====
$sevRank = @{ 'Critical' = 3; 'High' = 2; 'Medium' = 1; 'Low' = 0 }
$fails = @($script:Results | Where-Object { $_.Status -eq 'FAIL' })
$warns = @($script:Results | Where-Object { $_.Status -eq 'WARN' })
$failsCritHigh = @($fails | Where-Object { $sevRank[$_.Severity] -ge 2 })

if ($failsCritHigh.Count -gt 0) {
    $verdict = 'CRITICAL'; $verdictLine = '[CRITICAL] DO NOT DEPLOY'; $color = 'Red'
} elseif (($fails.Count + $warns.Count) -gt 0) {
    $verdict = 'ACCEPTED RISK'; $verdictLine = '[ACCEPTED RISK] review warnings before deploying'; $color = 'Yellow'
} else {
    $verdict = 'LOW RISK'; $verdictLine = '[LOW RISK] safe to deploy to dev'; $color = 'Green'
}

$passCount = @($script:Results | Where-Object { $_.Status -eq 'PASS' }).Count
$warnCount = $warns.Count
$failCount = $fails.Count

Write-Host ""
Write-Host ("==== Result: {0} PASS, {1} WARN, {2} FAIL ====" -f $passCount, $warnCount, $failCount) -ForegroundColor Cyan
Write-Host ("==== Verdict: {0} ====" -f $verdictLine) -ForegroundColor $color
Write-Host ""

# ==== Report ====
$reportDir = Join-Path $RepoPath 'audit\reports'
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$reportPath = Join-Path $reportDir "audit-report-$stamp.md"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Security Audit Report")
$lines.Add("")
$lines.Add("**Repo:** $RepoPath")
$lines.Add("**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("**Verdict:** $verdictLine")
$lines.Add("**Audit tooling:** [$PlaybookName]($PlaybookRepository)")
$lines.Add("**Tooling maintainer:** $PlaybookMaintainer")
$lines.Add("**Maintainer website:** [$PlaybookWebsite]($PlaybookWebsite)")
$lines.Add("**Attribution scope:** This identifies the audit tooling only; the audited project remains the work and responsibility of its own contributors.")
$lines.Add("")
$lines.Add("| ID | Status | Severity | Message |")
$lines.Add("|---|---|---|---|")
foreach ($r in $script:Results) {
    $lines.Add("| $($r.Id) | $($r.Status) | $($r.Severity) | $($r.Message) |")
}
$lines.Add("")
$lines.Add("**Summary:** $passCount PASS, $warnCount WARN, $failCount FAIL")
$lines | Set-Content -Path $reportPath -Encoding UTF8

# ==== CYB-style report (standards-mapped) ====
# Maps each control ID to the standard(s) it verifies and a one-line remediation,
# so this reads like a point-in-time CYB report (see ../templates/CYB_REPORT_TEMPLATE.md).
$ControlInfo = @{
    'F-01'  = @{ Standard = 'OWASP API2:2023 (Broken Authentication), A01:2021'; Remediation = 'Require a validated auth dependency (JWT/OAuth2/API key) on every route.' }
    'F-02'  = @{ Standard = 'OWASP A02:2021 (Cryptographic Failures)';            Remediation = 'Serve over HTTPS only; confirm no hardcoded http:// remains in production config.' }
    'F-03'  = @{ Standard = 'OWASP A05:2021 (Security Misconfiguration)';         Remediation = 'Replace wildcard CORS with an explicit origin allow-list.' }
    'F-07'  = @{ Standard = 'OWASP A06:2021 (Vulnerable Components)';            Remediation = 'Pin dependencies (==) or add a hashed lock file.' }
    'F-07b' = @{ Standard = 'OWASP A06:2021 (Vulnerable Components)';            Remediation = 'Patch or replace packages with known CVEs (pip-audit).' }
    'F-09'  = @{ Standard = 'CIS Docker Benchmark 4.1';                         Remediation = 'Add a non-root USER directive to the Dockerfile.' }
    'G-01'  = @{ Standard = 'OWASP A03:2021 (Injection)';                       Remediation = 'Use parameterized queries; never f-string user input into SQL.' }
    'G-02'  = @{ Standard = 'OWASP A03:2021 (Injection / XSS)';                 Remediation = 'Remove dangerouslySetInnerHTML/innerHTML/eval or sanitize input first.' }
    'G-03'  = @{ Standard = 'OWASP A02:2021 (Cryptographic Failures), CWE-798';  Remediation = 'Remove secret from git history; rotate the credential; use a secret manager.' }
    'G-05'  = @{ Standard = 'OWASP A06:2021 (Vulnerable Components)';           Remediation = 'Patch or replace npm packages with known CVEs (npm audit).' }
}

$critCount = @($script:Results | Where-Object { $_.Severity -eq 'Critical' -and $_.Status -eq 'FAIL' }).Count
$highCount = @($script:Results | Where-Object { $_.Severity -eq 'High' -and $_.Status -eq 'FAIL' }).Count
$medCount  = @($script:Results | Where-Object { $_.Severity -eq 'Medium' -and $_.Status -eq 'FAIL' }).Count
$lowWarnCount = @($script:Results | Where-Object { $_.Status -eq 'WARN' }).Count

$cybPath = Join-Path $reportDir "CYB_report_$stamp.md"
$cyb = New-Object System.Collections.Generic.List[string]
$cyb.Add("# Security Audit (CYB-style report)")
$cyb.Add("")
$cyb.Add("**Scope:** $RepoPath")
$cyb.Add("**Audit date:** $(Get-Date -Format 'yyyy-MM-dd')")
$cyb.Add("**Method:** automated scan via ``audit/run-audit.ps1`` (see ``../README.md`` for the full checklist; manual controls are not covered here)")
$cyb.Add("**Audit tooling:** [$PlaybookName]($PlaybookRepository)")
$cyb.Add("**Tooling maintainer:** $PlaybookMaintainer")
$cyb.Add("**Maintainer website:** [$PlaybookWebsite]($PlaybookWebsite)")
$cyb.Add("**Attribution scope:** This identifies the audit tooling only; the audited project remains the work and responsibility of its own contributors.")
$cyb.Add("")
$cyb.Add("## 1. Standards this audit maps to")
$cyb.Add("")
$cyb.Add("| Standard | Why it applies |")
$cyb.Add("|---|---|")
$cyb.Add("| OWASP Top 10 (2021) | General web app risk baseline |")
$cyb.Add("| OWASP API Security Top 10 (2023) | Applies to any API-first backend |")
$cyb.Add("| OWASP ASVS 4.0 | Verification-level controls (auth, transport, config) |")
$cyb.Add("| CIS Docker Benchmark | Container hardening for any shipped image |")
$cyb.Add("")
$cyb.Add("## 2. Executive summary")
$cyb.Add("")
$cyb.Add("**Verdict: $verdictLine**")
$cyb.Add("")
$cyb.Add("| Severity | FAIL count |")
$cyb.Add("|---|---|")
$cyb.Add("| Critical | $critCount |")
$cyb.Add("| High | $highCount |")
$cyb.Add("| Medium | $medCount |")
$cyb.Add("| Warnings (any severity) | $lowWarnCount |")
$cyb.Add("")
$cyb.Add("## 3. Findings")
$cyb.Add("")
foreach ($r in ($script:Results | Where-Object { $_.Status -ne 'PASS' })) {
    $info = $ControlInfo[$r.Id]
    $std = if ($info) { $info.Standard } else { 'n/a' }
    $rem = if ($info) { $info.Remediation } else { 'See ../README.md checklist for this control.' }
    $tag = if ($r.Status -eq 'FAIL') { "[$($r.Severity)]" } else { '[Informational]' }
    $cyb.Add("### $tag $($r.Id) - $($r.Message)")
    $cyb.Add("**Standard:** $std  ")
    $cyb.Add("**Remediation:** $rem")
    $cyb.Add("")
}
$cyb.Add("## 4. Verified-good controls")
$cyb.Add("")
foreach ($r in ($script:Results | Where-Object { $_.Status -eq 'PASS' })) {
    $cyb.Add("- [$($r.Id)] $($r.Message)")
}
$cyb.Add("")
$cyb.Add("**Summary:** $passCount PASS, $warnCount WARN, $failCount FAIL - Verdict: $verdictLine")
$cyb | Set-Content -Path $cybPath -Encoding UTF8

Write-Host "Report written to: $reportPath" -ForegroundColor DarkGray
Write-Host "CYB-style report written to: $cybPath" -ForegroundColor DarkGray
Write-Host "Manual controls (TLS, real auth behaviour, network segmentation, CI wiring): see ../README.md" -ForegroundColor DarkGray
Write-Host ""

if ($verdict -eq 'CRITICAL') { exit 1 } else { exit 0 }
