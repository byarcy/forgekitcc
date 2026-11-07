# ForgeKitCC - Core: settings, output, logging, process helpers and configuration.
# Dot-sourced by forgekitcc.ps1. $Root is defined there.

$AppName           = 'ForgeKitCC'
$AppVersion        = '0.2.0'
$ConfigFile        = Join-Path $Root 'tools.json'
$StateFile         = Join-Path $Root 'state.json'
$DownloadDir       = Join-Path $Root '_downloads'
$ManifestDir       = Join-Path $Root 'manifests'
$LogDir            = Join-Path $Root 'logs'
$LogKeepDays       = 30
$CheckIntervalDays = 7

$script:HttpTimeout   = 20
$script:LogFile       = $null
$script:Verbosity     = 1       # 0 = quiet, 1 = normal, 2 = verbose
$script:LineOpen      = $false
$script:LastOutput    = @()
$script:AcceptLicense = $false
$script:Notes         = @()

$script:Interactive = $true
try { $script:Interactive = -not [Console]::IsOutputRedirected } catch { $script:Interactive = $false }

# ============================================================ logging
function Write-Log([string]$Level, [string]$Message) {
  if (-not $script:LogFile) { return }
  $stamp = (Get-Date).ToString('HH:mm:ss')
  $lines = @($Message -split "`r?`n" | ForEach-Object { "$stamp [$Level] $_" })
  try { Add-Content -Path $script:LogFile -Value $lines -Encoding UTF8 } catch { }
}

function Start-Log([string]$CommandLine) {
  try {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $script:LogFile = Join-Path $LogDir ((Get-Date).ToString('yyyy-MM-dd') + '.log')
    Get-ChildItem -Path $LogDir -Filter '*.log' -File |
      Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogKeepDays) } |
      Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log 'INFO' ('=' * 70)
    Write-Log 'INFO' "$AppName $AppVersion | forgekitcc $CommandLine"
    Write-Log 'INFO' "PowerShell $($PSVersionTable.PSVersion) | $([Environment]::OSVersion.VersionString) | $Root"
  } catch { $script:LogFile = $null }
}

function Get-LogHint {
  if ($script:LogFile) { return "Details: logs\$(Split-Path $script:LogFile -Leaf)" }
  return ''
}

# ============================================================ output
# Normal output is short. --verbose adds details, --quiet shows only errors and summaries.
# Everything is written to the log, whatever the level.
function Close-StatusLine {
  if ($script:LineOpen) { Write-Host ''; $script:LineOpen = $false }
}

function Write-Out([string]$Message, [string]$Color = '', [int]$MinLevel = 1, [string]$LogLevel = 'INFO') {
  Write-Log $LogLevel $Message
  if ($script:Verbosity -lt $MinLevel) { return }
  Close-StatusLine
  if ($Color) { Write-Host $Message -ForegroundColor $Color } else { Write-Host $Message }
}
function Write-Info([string]$m)    { Write-Out $m }
function Write-Ok([string]$m)      { Write-Out $m 'Green' }
function Write-Warn([string]$m)    { Write-Out $m 'Yellow' 1 'WARN' }
function Write-Detail([string]$m)  { Write-Out $m 'DarkGray' 2 }
function Write-Summary([string]$m, [string]$Color = '') { Write-Out $m $Color 0 }
function Write-Err([string]$m)     { Write-Out $m 'Red' 0 'ERROR' }

function Get-LineWidth {
  $w = 0
  try { $w = [Console]::WindowWidth - 1 } catch { }
  if ($w -lt 20) { $w = 79 }
  return $w
}

# One status line that is rewritten in place (progress) until -Final prints it for good.
function Write-Status([string]$Text, [string]$Color = '', [switch]$Final) {
  if ($Final) { Write-Log 'INFO' $Text.Trim() }
  if ($script:Verbosity -lt 1) { return }
  if (-not $script:Interactive) {
    if ($Final) { Write-Host $Text }
    return
  }
  $width = Get-LineWidth
  if ($Text.Length -gt $width) { $line = $Text.Substring(0, $width) } else { $line = $Text.PadRight($width) }
  if ($Color) { Write-Host "`r$line" -NoNewline -ForegroundColor $Color } else { Write-Host "`r$line" -NoNewline }
  if ($Final) { Write-Host ''; $script:LineOpen = $false } else { $script:LineOpen = $true }
}

function Clear-StatusLine {
  if (-not $script:LineOpen) { return }
  $width = Get-LineWidth
  Write-Host ("`r" + (' ' * $width) + "`r") -NoNewline
  $script:LineOpen = $false
}

function Get-ShortError($ErrorRecord) {
  $m = [string]$ErrorRecord.Exception.Message
  return (($m -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
}

function Format-MB([long]$Bytes) { return [string][Math]::Round($Bytes / 1MB) }

# "-" when unknown, "850 MB" below 1 GB, "2.1 GB" above.
function Format-Size($Bytes) {
  if ($null -eq $Bytes) { return '-' }
  if ($Bytes -ge 1GB) { return ('{0:0.0} GB' -f ($Bytes / 1GB)).Replace(',', '.') }
  return "$(Format-MB $Bytes) MB"
}

function Format-Elapsed([TimeSpan]$Span) { return ('{0}:{1:00}' -f [int][Math]::Floor($Span.TotalMinutes), $Span.Seconds) }

# ============================================================ processes
function Format-Arg([string]$Value) {
  if ($Value -eq '') { return '""' }
  if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
  return $Value
}

# Runs a program, writes its output to the log and returns it. Throws on a non-zero exit code.
function Invoke-Capture([string]$Exe, [string[]]$ArgList = @()) {
  Write-Log 'CMD' ("$Exe " + (($ArgList | ForEach-Object { Format-Arg $_ }) -join ' '))
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $out = @(& $Exe @ArgList 2>&1 | ForEach-Object { "$_" }) }
  finally { $ErrorActionPreference = $prev }
  $code = $LASTEXITCODE
  $script:LastOutput = $out
  if ($out.Count -gt 0) { Write-Log 'OUT' ($out -join "`n") }
  if ($code -ne 0) { throw "$(Split-Path $Exe -Leaf) failed (exit code $code)." }
  return , $out
}

# Starts a program in the background and calls $OnTick every half second while it runs.
# Output goes to the log. Returns the exit code.
function Invoke-Tracked([string]$Exe, [string[]]$ArgList, [string]$WorkDir, [scriptblock]$OnTick, $Context) {
  New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
  $tag = [guid]::NewGuid().ToString('N')
  $outFile = Join-Path $DownloadDir "proc-$tag.out"
  $errFile = Join-Path $DownloadDir "proc-$tag.err"
  $argLine = ($ArgList | ForEach-Object { Format-Arg $_ }) -join ' '
  Write-Log 'CMD' "$Exe $argLine"
  $proc = Start-Process -FilePath $Exe -ArgumentList $argLine -WorkingDirectory $WorkDir -NoNewWindow -PassThru `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile
  $null = $proc.Handle   # needed so ExitCode is available after the process ends
  $clock = [Diagnostics.Stopwatch]::StartNew()
  while (-not $proc.WaitForExit(500)) {
    if ($OnTick) { & $OnTick $clock.Elapsed $Context }
  }
  $proc.WaitForExit()
  $code = $proc.ExitCode
  $out = @()
  foreach ($f in $outFile, $errFile) {
    if (Test-Path $f) { $out += @(Get-Content -Path $f); Remove-Item $f -Force -ErrorAction SilentlyContinue }
  }
  $script:LastOutput = $out
  if ($out.Count -gt 0) { Write-Log 'OUT' ($out -join "`n") }
  Write-Log 'INFO' "Exit code $code after $(Format-Elapsed $clock.Elapsed)"
  return $code
}

# ============================================================ files
function Reset-Dir([string]$Path) {
  if (Test-Path $Path) { Remove-Item $Path -Recurse -Force }
  New-Item -ItemType Directory -Path $Path | Out-Null
}

function Remove-Dir([string]$Path) {
  if (Test-Path $Path) { Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue }
}

# Swaps $Source into $Dest. The previous $Dest is kept until the swap succeeds and restored on failure.
function Replace-Dir([string]$Source, [string]$Dest) {
  $backup = "$Dest.old"
  Remove-Dir $backup
  if (Test-Path $Dest) {
    try { Rename-Item $Dest (Split-Path $backup -Leaf) }
    catch { throw "cannot replace '$(Split-Path $Dest -Leaf)'. Close the consoles or programs using it." }
  }
  try { Move-Item $Source $Dest }
  catch {
    if (Test-Path $backup) { Rename-Item $backup (Split-Path $Dest -Leaf) }
    throw
  }
  Remove-Dir $backup
}

function Assert-SystemTools {
  foreach ($exe in 'curl.exe', 'tar.exe') {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
      throw "$exe was not found. ForgeKitCC needs Windows 10 version 1803 or newer."
    }
  }
}

# ============================================================ configuration
function Get-Prop($Obj, [string]$Name, $Default = $null) {
  if ($null -eq $Obj) { return $Default }
  $p = $Obj.PSObject.Properties[$Name]
  if ($p -and $null -ne $p.Value) { return $p.Value }
  return $Default
}

function Import-Config {
  if (-not (Test-Path $ConfigFile)) { throw "tools.json not found in $Root." }
  try { $cfg = Get-Content -Raw -Path $ConfigFile | ConvertFrom-Json }
  catch { throw "tools.json is not valid JSON: $($_.Exception.Message)" }
  $list = @($cfg.tools)
  if ($list.Count -eq 0) { throw 'tools.json has no tools.' }
  foreach ($t in $list) {
    foreach ($k in 'name', 'type', 'dir') {
      if (-not (Get-Prop $t $k)) { throw "a tool in tools.json is missing '$k'." }
    }
    if ($t.type -notin @('github', 'nuget', 'msvc')) { throw "tool '$($t.name)' has an unknown type '$($t.type)'." }
  }
  return $list
}

function Get-Tool([string]$Name) { return ($script:Tools | Where-Object { $_.name -eq $Name } | Select-Object -First 1) }
function Get-ToolDir($t) { return (Join-Path $Root $t.dir) }

function Select-Tools([string[]]$Wanted) {
  if (-not $Wanted -or $Wanted.Count -eq 0 -or $Wanted -contains 'all') { return $script:Tools }
  foreach ($n in $Wanted) {
    if (-not (Get-Tool $n)) {
      throw "unknown tool '$n'. Available: $(($script:Tools | ForEach-Object { $_.name }) -join ', '), all"
    }
  }
  return @($script:Tools | Where-Object { $Wanted -contains $_.name })   # keeps the order of tools.json
}

function Get-PythonTool {
  return ($script:Tools | Where-Object { $_.type -eq 'nuget' -and (Get-Prop $_ 'package') -eq 'python' } | Select-Object -First 1)
}

function Get-ToolPython {
  $t = Get-PythonTool
  if ($t) {
    $p = Join-Path (Get-ToolDir $t) (Get-Prop $t 'exe' 'python.exe')
    if (Test-Path $p) { return $p }
  }
  throw 'needs the ForgeKitCC Python. Install it first: forgekitcc update python'
}

function Get-MsvcTool { return ($script:Tools | Where-Object { $_.type -eq 'msvc' } | Select-Object -First 1) }

function Get-OurDirs {
  $dirs = @($Root)
  foreach ($t in $script:Tools) {
    $base = Get-ToolDir $t
    foreach ($b in @(Get-Prop $t 'bin' @())) {
      if ($null -eq $b) { continue }
      if ($b) { $dirs += (Join-Path $base $b) } else { $dirs += $base }
    }
  }
  return $dirs
}
