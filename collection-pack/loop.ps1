# Grok laptop collection loop — Windows (PowerShell) edition.
# Burns tokens until the queue is done (or tokens run out).
# One fresh grok session per task, resume-safe.
#
# Setup (one time, in PowerShell):
#   mkdir C:\Users\kim\contact-collection; cd C:\Users\kim\contact-collection
#   # download loop.ps1 + queue.txt into this folder
#   grok -p "say GROK-READY"     # should print GROK-READY
# Run:
#   powershell -ExecutionPolicy Bypass -File .\loop.ps1
# Stop anytime with Ctrl+C — re-running picks up where it left off.
#
# What it does per city: Dublin first (researches its own money category, then
# collects), then Queretaro + Kampala (apply the fix lists), Nairobi + Lisbon
# (verify + top up), Madrid (convert the HTML page + verify). Each city: find 12
# real businesses, check each against a second source, write data\grok-<city>.json,
# validate (JSON parses, >=6 listings, phone digits sane) or retry once and move on.

$ErrorActionPreference = 'Stop'
$Base    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Grok    = if ($env:GROK_BIN) { $env:GROK_BIN } else { 'grok' }
$Queue   = Join-Path $Base 'queue.txt'
$Log     = Join-Path $Base 'loop.log'
$Tally   = Join-Path $Base 'loop-tally.md'
$TimeoutMs   = 1800 * 1000   # 30 min per grok run, then kill and move on
$MaxListings = 12
$WikiRepo = 'kim-page/wiki'
$ContractWiki = 'CONTACT/kb/collector-contract.md'
$SourcesWiki  = 'CONTACT/collection/sources'

New-Item -ItemType Directory -Force -Path (Join-Path $Base 'data') | Out-Null

function Beat($msg) {
  $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
  Add-Content -Path $Log -Value $line
  Write-Host $line
}

function New-SessionId { [guid]::NewGuid().ToString() }

function Set-Status($slug, $status) {
  $lines = Get-Content $Queue | ForEach-Object {
    $t = $_.TrimEnd()
    if ($t -match '^#' -or $t -eq '') { return $_ }
    $p = $t -split '\|'
    if ($p[0] -eq $slug) { $p[6] = $status; ($p -join '|') } else { $_ }
  }
  $lines | Set-Content $Queue
}

function Get-ContractLine {
  $local = Join-Path $Base 'CONTRACT.md'
  if (Test-Path $local) { return "Read $local FIRST and follow it exactly — field names, phone rules, hard rules." }
  return "Read the collector contract FIRST: $ContractWiki in the $WikiRepo GitHub repo (you have access to it). Follow it exactly — field names, phone rules, hard rules."
}

function Write-Mission($slug, $iso, $city, $country, $category, $mode) {
  $dir      = Join-Path $Base $slug
  $datafile = Join-Path $Base "data\grok-$slug.json"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $head = "You are a data collector for contact.page, a business directory.`n$(Get-ContractLine)`nTarget: $city, $country ($iso)."
  $text = ''
  switch ($mode) {
    'collect' {
      if ($category -eq 'RESEARCH-THEN-COLLECT') {
        $text = @"
$head

PHASE 0 - PICK THE CATEGORY: research which boring B2B trade in $city is starving
for leads (businesses that NEED customers: installers, contractors, commercial
services - never popular consumer spots). Pick ONE money category and state why
in result.md.

PHASE 1 - FIND + FILL: find $MaxListings REAL, currently-operating businesses in
that trade in $city. Write one JSON file per the contract at: $datafile

PHASE 2 - CHECK: re-verify every listing against a second source. Drop anything
unconfirmed. Fewer real listings beat more fake ones.

Write result.md in $dir : one-line tally (X collected / Y dropped in check), then
per listing: name, verdict, evidence URLs. Validate the JSON parses before
finishing. Read-only research. Never invent.
"@
      } else {
        $text = @"
$head
Category: $category

PHASE 1 - FIND + FILL: find $MaxListings REAL, currently-operating businesses in
this exact trade in $city. Write one JSON file per the contract at: $datafile

PHASE 2 - CHECK: re-verify every listing against a second source. Drop anything
unconfirmed - including anything in the wrong trade. Fewer real listings beat
more fake ones.

Write result.md in $dir : one-line tally (X collected / Y dropped in check), then
per listing: name, verdict, evidence URLs. Validate the JSON parses before
finishing. Read-only research. Never invent.
"@
      }
    }
    'fixlist' {
      $text = @"
$head
Category: $category

Source files (in the $WikiRepo repo, you have access):
- Fix list: $SourcesWiki/morning-tally.md ("Fix list for production normalization")
- Existing data: $SourcesWiki/<the $slug JSON file in that folder> - read it first.

Your job:
1. Apply every fix: drop/replace miscategorized or dead listings, correct wrong
   phone digits, fix names/addresses/URLs exactly as the tally instructs.
2. Top up with fresh verified listings to reach $MaxListings total.
3. Write the corrected file to $datafile EXACTLY per the contract.
   Phone rule is absolute: pure digits, country code, trunk zero dropped.

Write result.md in $dir : what was fixed per listing, what was dropped and why,
what was added. Validate the JSON parses before finishing. Never invent.
"@
    }
    'topup' {
      $text = @"
$head
Category: $category

The existing file for this city is $SourcesWiki/<the $slug JSON file in that folder>
in the $WikiRepo repo (you have access) - read it first.
Your job:
1. VERIFY every existing listing (second source each). Drop the unconfirmed.
2. TOP UP with fresh real businesses in the same trade to reach $MaxListings.
3. Write the merged file to $datafile EXACTLY per the contract.

Write result.md in $dir : kept/dropped/added with evidence URLs per listing.
Validate the JSON parses before finishing. Read-only. Never invent.
"@
    }
    'convert' {
      $text = @"
$head
Category: $category

Source: $SourcesWiki/madrid-solar-installers.html in the $WikiRepo repo
(you have access) - read it first.
Your job:
1. Extract every business listing from the HTML into JSON EXACTLY per the contract,
   written to $datafile. Phone rule: pure digits, country code, trunk zero dropped.
2. CHECK: verify each extracted listing is a real, currently-operating business
   (second source). Drop the unconfirmed.
3. Top up with fresh listings to reach $MaxListings if drops leave gaps.

Write result.md in $dir : extracted/verified/dropped/added per listing with
evidence URLs. Validate the JSON parses before finishing. Never invent.
"@
    }
  }
  Set-Content -Path (Join-Path $dir 'mission.txt') -Value $text
}

function Test-Result($slug) {
  $datafile = Join-Path $Base "data\grok-$slug.json"
  try { $d = Get-Content $datafile -Raw | ConvertFrom-Json }
  catch { return "UNPARSABLE: $($_.Exception.Message)" }
  $ls = @($d.listings)
  if ($ls.Count -lt 6) { return "TOO FEW: $($ls.Count)" }
  $bad = @($ls | Where-Object { "$($_.phone)" -notmatch '^[1-9][0-9]{6,14}$' } | Select-Object -First 5 -ExpandProperty name)
  if ($bad.Count -gt 0) { return "BAD PHONES: $($bad -join ', ')" }
  $missing = @($ls | Where-Object { -not $_.name -or -not $_.proof } | Select-Object -First 5 -ExpandProperty name)
  if ($missing.Count -gt 0) { return "MISSING FIELDS: $($missing -join ', ')" }
  return "OK: $($ls.Count) listings"
}

# --- preflight ---
if (-not (Get-Command $Grok -ErrorAction SilentlyContinue)) { Write-Host "ERROR: grok CLI not found ('$Grok'). Fix PATH or set GROK_BIN."; exit 1 }
if (-not (Test-Path $Queue)) { Write-Host "ERROR: queue.txt not found in $Base."; exit 1 }

$pending = @(Get-Content $Queue | Where-Object { $_ -match '\|pending$' }).Count
Beat "LOOP START - $pending tasks pending"
"# Laptop loop tally - $(Get-Date -Format 'yyyy-MM-dd')" | Set-Content $Tally

while (@(Get-Content $Queue | Where-Object { $_ -match '\|pending$' }).Count -gt 0) {
  $line = (Get-Content $Queue | Where-Object { $_ -match '\|pending$' } | Select-Object -First 1).TrimEnd()
  $p = $line -split '\|'
  $slug, $iso, $city, $country, $category, $mode = $p[0], $p[1], $p[2], $p[3], $p[4], $p[5]
  Set-Status $slug 'running'
  Write-Mission $slug $iso $city $country $category $mode
  $dir = Join-Path $Base $slug

  $attempt = 0; $ok = $false; $vout = ''
  while ($attempt -lt 2 -and -not $ok) {
    $attempt++
    Beat "START $slug ($city - $category) mode=$mode attempt=$attempt"
    $sid = New-SessionId
    $mission = Get-Content (Join-Path $dir 'mission.txt') -Raw
    $proc = Start-Process -FilePath $Grok `
      -ArgumentList @('--always-approve', '--session-id', $sid, '-p', $mission) `
      -NoNewWindow -PassThru `
      -RedirectStandardOutput (Join-Path $dir 'run.out') `
      -RedirectStandardError (Join-Path $dir 'run.err')
    $finished = $proc.WaitForExit($TimeoutMs)
    if (-not $finished) { $proc.Kill(); Beat "TIMEOUT $slug attempt=$attempt (killed after 30 min)" }
    $rc = $proc.ExitCode
    Beat "END $slug attempt=$attempt rc=$rc"
    $datafile = Join-Path $Base "data\grok-$slug.json"
    if ($finished -and $rc -eq 0 -and (Test-Path $datafile)) {
      $vout = Test-Result $slug
      if ($vout -like 'OK:*') { $ok = $true } else { Beat "VALIDATE FAIL ${slug}: $vout" }
    } else {
      Beat "RUN FAIL ${slug}: rc=$rc, data file present: $(Test-Path $datafile)"
    }
    if (-not $ok -and $attempt -lt 2) { Beat "RETRY $slug" }
  }

  if ($ok) {
    Set-Status $slug 'done'
    "## $slug - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - DONE - $vout" | Add-Content $Tally
    Beat "DONE $slug - $vout"
  } else {
    Set-Status $slug 'failed'
    "## $slug - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FAILED after 2 attempts" | Add-Content $Tally
    Beat "FAILED $slug - moving on"
  }
}

$done   = @(Get-Content $Queue | Where-Object { $_ -match '\|done$' }).Count
$failed = @(Get-Content $Queue | Where-Object { $_ -match '\|failed$' }).Count
Beat "LOOP COMPLETE - $done done, $failed failed"
