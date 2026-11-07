# ForgeKitCC - Install: downloads, extraction, MSVC, manifests, update, verify and repair.

$GlobalExcludes = @('*\__pycache__\*', '*.pyc')

# ============================================================ extraction
function Expand-Download([string]$File, [string]$Dest) {
  if ($File -match '\.tar\.(xz|gz|bz2)$') {
    $helper = Join-Path $DownloadDir 'extract_tar.py'
    Set-Content -Path $helper -Encoding ASCII -Value @(
      'import sys, tarfile',
      'with tarfile.open(sys.argv[1]) as t:',
      '    kw = {"filter": "data"} if hasattr(tarfile, "data_filter") else {}',
      '    t.extractall(sys.argv[2], **kw)'
    )
    Invoke-Capture (Get-ToolPython) @('-I', $helper, $File, $Dest) | Out-Null
  } else {
    Invoke-Capture 'tar.exe' @('-xf', $File, '-C', $Dest) | Out-Null
  }
}

# ============================================================ manifests (file list + size + SHA-256)
function Get-ManifestPath($t) { return (Join-Path $ManifestDir "$($t.name).tsv") }

function Get-Excludes($t) { return @($GlobalExcludes + @(Get-Prop $t 'verifyExclude' @())) }

function Test-Excluded([string]$Rel, [string[]]$Patterns) {
  foreach ($p in $Patterns) { if ($Rel -like $p -or "\$Rel" -like $p) { return $true } }
  return $false
}

function Get-FileSha256([string]$Path, $Algorithm) {
  $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  try { return ([BitConverter]::ToString($Algorithm.ComputeHash($fs))).Replace('-', '') }
  finally { $fs.Dispose() }
}

function Get-ToolFiles($t) {
  $dir = (Get-ToolDir $t).TrimEnd('\', '/')
  $excludes = Get-Excludes $t
  $result = New-Object 'System.Collections.Generic.List[object]'
  foreach ($f in (Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($dir.Length + 1)
    if (-not (Test-Excluded $rel $excludes)) { $result.Add([pscustomobject]@{ Rel = $rel; File = $f }) }
  }
  return , $result
}

function Write-Manifest($t, [string]$Version, [string]$Label) {
  New-Item -ItemType Directory -Force -Path $ManifestDir | Out-Null
  $files = Get-ToolFiles $t
  $sha = [Security.Cryptography.SHA256]::Create()
  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add("# $($t.name)`t$Version`t$((Get-Date).ToString('s'))")
  $i = 0
  foreach ($x in $files) {
    $i++
    if ($i % 250 -eq 0) { Write-Status ("{0}  verifying  {1}/{2} files" -f $Label, $i, $files.Count) }
    $lines.Add("$($x.File.Length)`t$(Get-FileSha256 $x.File.FullName $sha)`t$($x.Rel)")
  }
  $sha.Dispose()
  [IO.File]::WriteAllLines((Get-ManifestPath $t), $lines)
  Write-Log 'INFO' "Manifest for $($t.name): $($files.Count) files."
}

# Returns $null when there is no manifest, otherwise counts of missing and changed files.
function Test-Manifest($t, [switch]$Full, [string]$Label) {
  $path = Get-ManifestPath $t
  if (-not (Test-Path $path)) { return $null }
  $entries = @(Get-Content -Path $path -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') })
  $actual = @{}
  foreach ($x in (Get-ToolFiles $t)) { $actual[$x.Rel] = $x.File }
  $missing = 0; $changed = 0; $i = 0
  $sha = $null
  if ($Full) { $sha = [Security.Cryptography.SHA256]::Create() }
  foreach ($e in $entries) {
    $i++
    if ($i % 250 -eq 0) { Write-Status ("{0}  checking  {1}/{2} files" -f $Label, $i, $entries.Count) }
    $parts = $e -split "`t", 3
    if ($parts.Count -lt 3) { continue }
    $f = $actual[$parts[2]]
    if (-not $f) { $missing++; Write-Log 'VERIFY' "missing: $($t.dir)\$($parts[2])"; continue }
    if ($f.Length -ne [long]$parts[0]) { $changed++; Write-Log 'VERIFY' "size changed: $($t.dir)\$($parts[2])"; continue }
    if ($Full -and (Get-FileSha256 $f.FullName $sha) -ne $parts[1]) { $changed++; Write-Log 'VERIFY' "content changed: $($t.dir)\$($parts[2])" }
  }
  if ($sha) { $sha.Dispose() }
  return [pscustomobject]@{ Total = $entries.Count; Missing = $missing; Changed = $changed }
}

# ============================================================ installers
function Install-Archive($t, $Latest, [string]$Label) {
  $dest = Get-ToolDir $t
  $file = Join-Path $DownloadDir $Latest.File
  $work = Join-Path $Root ('_tmp_' + $t.name)

  Save-Download $Latest.Url $file $Latest.Size $Latest.Sha256 $Label

  Write-Status "$Label  extracting"
  Reset-Dir $work
  Expand-Download $file $work

  $subdir = [string](Get-Prop $t 'subdir' '')
  $src = $work
  if ($subdir -eq '*') {
    $top = @(Get-ChildItem $work -Directory)
    if ($top.Count -ne 1) { throw "unexpected layout inside $($Latest.File)" }
    $src = $top[0].FullName
  } elseif ($subdir) {
    $src = Join-Path $work $subdir
    if (-not (Test-Path $src)) { throw "folder '$subdir' not found inside $($Latest.File)" }
  }

  # Python: remember the pip packages so they can be reinstalled in the new version.
  $isPython = ($t.type -eq 'nuget' -and (Get-Prop $t 'package') -eq 'python')
  $requirements = $null
  if ($isPython) {
    $oldPy = Join-Path $dest (Get-Prop $t 'exe' 'python.exe')
    if (Test-Path $oldPy) {
      $requirements = Join-Path $DownloadDir 'pip-packages.txt'
      try {
        Invoke-Capture $oldPy @('-m', 'pip', 'freeze', '--disable-pip-version-check') |
          Where-Object { $_ -match '==| @ ' } | Set-Content -Path $requirements -Encoding ASCII
      } catch { $requirements = $null }
    }
  }

  Write-Status "$Label  installing"
  Replace-Dir $src $dest
  Remove-Dir $work
  Remove-Item $file -Force -ErrorAction SilentlyContinue

  Write-Manifest $t "$($Latest.Version)" $Label

  if ($isPython) {
    $py = Join-Path $dest (Get-Prop $t 'exe' 'python.exe')
    Write-Status "$Label  setting up pip"
    Invoke-Capture $py @('-m', 'ensurepip', '--upgrade') | Out-Null
    if ($requirements -and (Test-Path $requirements) -and (Get-Item $requirements).Length -gt 0) {
      Write-Status "$Label  reinstalling pip packages"
      try { Invoke-Capture $py @('-m', 'pip', 'install', '--disable-pip-version-check', '-r', $requirements) | Out-Null }
      catch { Write-Log 'WARN' 'Some pip packages could not be reinstalled.'; $script:Notes += "Some pip packages could not be reinstalled. $(Get-LogHint)" }
    }
  }
}

function Confirm-MsvcLicense {
  if ($script:AcceptLicense) { return }
  Close-StatusLine
  Write-Host ''
  Write-Host '  MSVC needs the Visual Studio Build Tools license to be accepted:'
  Write-Host '  https://visualstudio.microsoft.com/license-terms/' -ForegroundColor Cyan
  $a = Read-Host '  Accept the license? [y/N]'
  if ($a -notmatch '^(y|yes)$') { throw 'license not accepted' }
  Write-Log 'INFO' 'Visual Studio Build Tools license accepted by the user.'
  $script:AcceptLicense = $true
}

function Get-FolderBytes([string]$Path) {
  if (-not (Test-Path $Path)) { return [long]0 }
  $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
  if ($sum) { return [long]$sum }
  return [long]0
}

function Install-Msvc($t, [string]$Label) {
  $py = Get-ToolPython
  Update-MsvcScript
  Confirm-MsvcLicense

  # The work folder keeps the downloaded packages, so an interrupted install resumes where it stopped.
  $work = Join-Path $Root '_tmp_msvc'
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  Remove-Dir (Join-Path $work 'msvc')

  $pin = [string](Get-Prop $t 'pin' '')
  $argList = @('-I', $MsvcScript, '--accept-license')
  if ($pin) { $argList += @('--msvc-version', $pin) }
  $ctx = @{ Label = $Label; Work = $work; Tick = 0; Mb = '0' }
  $tick = {
    param($elapsed, $c)
    $c.Tick++
    if ($c.Tick % 4 -eq 1) { $c.Mb = Format-MB (Get-FolderBytes $c.Work) }   # every 2 seconds
    Write-Status ("{0}  downloading and installing  {1} MB  ({2})" -f $c.Label, $c.Mb, (Format-Elapsed $elapsed))
  }
  $code = Invoke-Tracked $py $argList $work $tick $ctx
  if ($code -ne 0) {
    if (-not (Test-Internet)) { throw 'connection lost' }
    throw 'the MSVC download failed'
  }
  $out = Join-Path $work 'msvc'
  if (-not (Test-Path (Join-Path $out 'setup_x64.bat'))) { throw 'the MSVC download did not finish' }

  Write-Status "$Label  installing"
  Replace-Dir $out (Get-ToolDir $t)
  Remove-Dir $work
  $ver = '?'
  $m = Get-MsvcLayout
  if ($m) { $ver = $m.VcVersion }
  Write-Manifest $t $ver $Label
}

# ============================================================ update / install / repair
function Invoke-Update([string[]]$Wanted, [switch]$MissingOnly, [switch]$Force) {
  Assert-SystemTools
  $selected = @(Select-Tools $Wanted)
  $script:Notes = @()

  Write-Status 'Checking internet connection...'
  if (-not (Test-Internet)) {
    Clear-StatusLine
    Write-Summary 'No internet connection. Nothing was changed.' 'Yellow'
    return $false
  }

  Write-Status 'Checking versions...'
  $plan = @(); $failed = @()
  foreach ($t in $selected) {
    $inst = Get-Installed $t
    if ($MissingOnly -and $inst) { continue }
    if ($t.type -eq 'msvc' -and (-not $inst -or $Force)) {
      # Python may not be installed yet; the MSVC version is resolved when it is installed.
      $plan += [pscustomobject]@{ Tool = $t; Latest = $null }
      continue
    }
    try { $lat = Get-Latest $t }
    catch { $failed += [pscustomobject]@{ Tool = $t.name; Reason = (Get-ShortError $_) }; continue }
    if (-not $lat) { $failed += [pscustomobject]@{ Tool = $t.name; Reason = 'no Windows build found' }; continue }
    if ($Force -or (Test-NeedsUpdate $t $inst $lat)) { $plan += [pscustomobject]@{ Tool = $t; Latest = $lat } }
  }
  Clear-StatusLine

  if ($plan.Count -eq 0 -and $failed.Count -eq 0) {
    if ($MissingOnly) { Write-Summary 'Nothing is missing.' 'Green' } else { Write-Summary 'Everything is up to date.' 'Green' }
    if (-not $MissingOnly) { Save-State @() }
    return $true
  }

  foreach ($f in $failed) { Write-Status (" {0,-7} FAILED: {1}" -f $f.Tool, $f.Reason) 'Red' -Final }

  $done = 0; $i = 0
  foreach ($p in $plan) {
    $i++
    $t = $p.Tool
    if ($p.Latest) { $ver = "$($p.Latest.Version)" } else { $ver = [string](Get-Prop $t 'pin' 'latest') }
    $label = " [{0}/{1}] {2,-7}{3,-10}" -f $i, $plan.Count, $t.name, $ver
    Write-Log 'INFO' "--- $($t.name) $ver"
    try {
      if ($t.type -eq 'msvc') { Install-Msvc $t $label } else { Install-Archive $t $p.Latest $label }
      Write-Status "$label  done" 'Green' -Final
      $done++
    } catch {
      $reason = Get-ShortError $_
      Write-Log 'ERROR' "$($t.name): $($_.Exception.Message)"
      Write-Status "$label  FAILED: $reason" 'Red' -Final
      $failed += [pscustomobject]@{ Tool = $t.name; Reason = $reason }
    }
  }

  $verb = 'updated'
  if ($Force) { $verb = 'reinstalled' } elseif ($MissingOnly) { $verb = 'installed' }
  Write-Summary ''
  $color = 'Green'
  if ($failed.Count -gt 0) { $color = 'Yellow' }
  Write-Summary "$done $verb, $($failed.Count) failed." $color
  foreach ($n in $script:Notes) { Write-Summary $n 'Yellow' }
  if ($failed.Count -gt 0) {
    Write-Summary '      Run the same option again to resume.'
    $hint = Get-LogHint
    if ($hint) { Write-Summary "      $hint" }
  }
  if (Test-Path $StateFile) { Remove-Item $StateFile -Force -ErrorAction SilentlyContinue }
  return ($failed.Count -eq 0)
}

# ============================================================ verify
# Returns the names of the tools that have problems.
function Invoke-Verify([string[]]$Wanted, [switch]$Full) {
  $bad = @()
  $noManifest = @()
  foreach ($t in (Select-Tools $Wanted)) {
    $label = " {0,-7}" -f $t.name
    Write-Status "$label  checking"
    $inst = Get-Installed $t
    if (-not $inst) { Write-Status "$label  not installed" 'Yellow' -Final; $bad += $t.name; continue }
    if (-not $inst.Version) { Write-Status "$label  does not run" 'Red' -Final; $bad += $t.name; continue }
    $r = Test-Manifest $t -Full:$Full -Label $label
    if ($null -eq $r) {
      Write-Status "$label  runs, files not checked (no manifest)" 'Yellow' -Final
      $noManifest += $t.name
      continue
    }
    if ($r.Missing -eq 0 -and $r.Changed -eq 0) {
      Write-Status ("{0}  ok  ({1} {2})" -f $label, $r.Total, $(if ($r.Total -eq 1) { 'file' } else { 'files' })) 'Green' -Final
    } else {
      $parts = @()
      if ($r.Missing) { $parts += "$($r.Missing) missing" }
      if ($r.Changed) { $parts += "$($r.Changed) changed" }
      Write-Status ("{0}  damaged: {1}" -f $label, ($parts -join ', ')) 'Red' -Final
      $bad += $t.name
    }
  }
  if ($noManifest.Count -gt 0) {
    Write-Summary "No manifest for: $($noManifest -join ', '). Run a repair once to create it." 'DarkGray'
  }
  if ($Full) {
    Write-Summary ''
    if (-not (Invoke-TestBuild)) { $bad += 'build' }
  }
  return $bad
}

# ============================================================ clean
function Invoke-Clean {
  $targets = @($DownloadDir)
  $targets += @(Get-ChildItem $Root -Directory | Where-Object { $_.Name -like '_tmp_*' -or $_.Name -like '*.old' } |
    ForEach-Object { $_.FullName })
  $bytes = [long]0; $n = 0
  foreach ($p in $targets) {
    if (Test-Path $p) { $bytes += Get-FolderBytes $p; Remove-Dir $p; $n++ }
  }
  Write-Summary "Removed $n temporary folder(s), $(Format-MB $bytes) MB freed." 'Green'
}
