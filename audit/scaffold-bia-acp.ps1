<#
.SYNOPSIS
    Scaffolds a dated BIA/ACP addendum from the template, pre-filling the
    "Known open items" table from the most recent audit report.
.DESCRIPTION
    This does NOT auto-generate the ACP ratings (Confidentiality/Integrity/
    Availability) - those require a human business judgment call. It only
    saves the boilerplate: copies templates/BIA_ACP_TEMPLATE.md into
    <RepoPath>/security/BIA_ACP_<date>.md, fills in date/app placeholders,
    and lists the current FAIL/WARN findings from the latest
    audit/reports/CYB_report_*.md (run run-audit.ps1 first if none exists).
.PARAMETER RepoPath
    Path to the target repository. Defaults to the current directory.
.PARAMETER AppName
    Application name to fill into the template.
.PARAMETER AssetId
    Org asset ID to fill into the template (optional).
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scaffold-bia-acp.ps1 -RepoPath C:\Projects\SomeRepo -AppName "Some App"
#>

param(
    [string]$RepoPath = (Get-Location).Path,
    [string]$AppName = '<app name>',
    [string]$AssetId = '<asset ID>'
)

$RepoPath = (Resolve-Path $RepoPath).Path
$PlaybookRoot = Split-Path -Parent $PSScriptRoot
$TemplatePath = Join-Path $PlaybookRoot 'templates\BIA_ACP_TEMPLATE.md'

if (-not (Test-Path $TemplatePath)) {
    Write-Error "Template not found: $TemplatePath"
    exit 1
}

$today = Get-Date -Format 'yyyy-MM-dd'
$securityDir = Join-Path $RepoPath 'security'
New-Item -ItemType Directory -Path $securityDir -Force | Out-Null
$outPath = Join-Path $securityDir "BIA_ACP_$today.md"

if (Test-Path $outPath) {
    Write-Error "Refusing to overwrite existing file: $outPath"
    exit 1
}

$content = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
$content = $content -replace '<app name>', $AppName
$content = $content -replace '<YYYY-MM-DD>', $today
$content = $content -replace '<org asset ID, e.g. APP-2026-001>', $AssetId

# Pull the latest CYB-style report's FAIL/WARN findings into section 4.
# (Only data rows here - the template already provides the table header.)
$reportsDir = Join-Path $RepoPath 'audit\reports'
$latestCyb = Get-ChildItem -Path $reportsDir -Filter 'CYB_report_*.md' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

$openItemsTable = New-Object System.Collections.Generic.List[string]

if ($latestCyb) {
    $cybContent = Get-Content -Path $latestCyb.FullName -Raw -Encoding UTF8
    $findingHeaders = [regex]::Matches($cybContent, '### \[(?<sev>[^\]]+)\] (?<id>\S+) - (?<msg>[^\r\n]+)')
    foreach ($m in $findingHeaders) {
        $sevTag = if ($m.Groups['sev'].Value -in @('Critical','High')) { 'Red' } else { 'Yellow' }
        $marker = if ($sevTag -eq 'Red') { '[CRITICAL/HIGH]' } else { '[REVIEW]' }
        $openItemsTable.Add("| $($m.Groups['id'].Value) | $($m.Groups['msg'].Value.Trim()) | $marker Open |")
    }
    if ($findingHeaders.Count -eq 0) {
        $openItemsTable.Add("| - | No open findings in latest audit run | - |")
    }
    Write-Host "Pulled $($findingHeaders.Count) open item(s) from: $($latestCyb.FullName)" -ForegroundColor DarkGray
} else {
    $openItemsTable.Add("| - | No audit report found - run audit/run-audit.ps1 first | - |")
    Write-Host "No CYB_report_*.md found under $reportsDir - run run-audit.ps1 first for auto-filled findings." -ForegroundColor Yellow
}

$content = $content -replace '\|\s*<ID>\s*\|\s*<finding>\s*\|.*\|', ($openItemsTable -join "`n")

Set-Content -Path $outPath -Value $content -Encoding UTF8
Write-Host "BIA/ACP addendum scaffolded at: $outPath" -ForegroundColor Green
Write-Host "Now fill in the Confidentiality/Integrity/Availability ratings by hand and route for CYB validation." -ForegroundColor DarkGray
