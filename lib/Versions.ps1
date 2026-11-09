# ForgeKitCC - Versions: installed vs available, update checks and cached state.

function Get-Ver([string]$Text) {
  if ($Text -match '(\d+(?:\.\d+){1,3})') { return [version]$Matches[1] }
  return $null
}

function Test-Pin($Version, [string]$Pin) {
  if (-not $Pin) { return $true }
  $s = $Version.ToString()
  return ($s -eq $Pin -or $s.StartsWith("$Pin."))
}

function Get-MsvcLayout {
  $t = Get-MsvcTool
  if (-not $t) { return $null }
  $root = Get-ToolDir $t
  $vcRoot = Join-Path $root 'VC\Tools\MSVC'
  $sdkInc = Join-Path $root 'Windows Kits\10\Include'
  if (-not (Test-Path $vcRoot)) { return $null }
  $vc = Get-ChildItem $vcRoot -Directory | Where-Object { Get-Ver $_.Name } |
    Sort-Object { Get-Ver $_.Name } -Descending | Select-Object -First 1
  $sdk = $null
  if (Test-Path $sdkInc) {
    $sdk = Get-ChildItem $sdkInc -Directory | Where-Object { Get-Ver $_.Name } |
      Sort-Object { Get-Ver $_.Name } -Descending | Select-Object -First 1
  }
  return [pscustomobject]@{
    Root       = $root
    VcVersion  = $(if ($vc) { $vc.Name } else { '' })
    SdkVersion = $(if ($sdk) { $sdk.Name } else { '' })
    Setup      = (Join-Path $root 'setup_x64.bat')
  }
}

function Get-Installed($t) {
  if ($t.type -eq 'msvc') {
    $m = Get-MsvcLayout
    if (-not $m -or -not $m.VcVersion -or -not (Test-Path $m.Setup)) { return $null }
    $sdkBuild = 0
    $sv = Get-Ver $m.SdkVersion
    if ($sv) { $sdkBuild = $sv.Build }
    return [pscustomobject]@{ Version = (Get-Ver $m.VcVersion); Sdk = $sdkBuild }
  }
  $exe = Join-Path (Get-ToolDir $t) (Get-Prop $t 'exe' '')
  if (-not (Test-Path $exe -PathType Leaf)) { return $null }
  if ($t.type -eq 'vscode') {
    # Code.exe is a GUI program: read the version from the file instead of running it.
    try { return [pscustomobject]@{ Version = (Get-Ver ([string](Get-Item $exe).VersionInfo.ProductVersion)) } }
    catch { return [pscustomobject]@{ Version = $null } }
  }
  try { $out = Invoke-Capture $exe @(Get-Prop $t 'versionArgs' @('--version')) }
  catch { return [pscustomobject]@{ Version = $null } }
  return [pscustomobject]@{ Version = (Get-Ver ($out -join ' ')) }
}

function Get-Latest($t) {
  $pin = [string](Get-Prop $t 'pin' '')
  switch ($t.type) {
    'github' {
      $releases = Get-Json "https://api.github.com/repos/$($t.repo)/releases?per_page=40"
      $best = $null
      foreach ($r in @($releases)) {
        if ($r.prerelease -or $r.draft) { continue }
        $v = Get-Ver $r.tag_name
        if (-not $v -or -not (Test-Pin $v $pin)) { continue }
        $a = @($r.assets) | Where-Object { $_.name -match $t.asset } | Select-Object -First 1
        if (-not $a) { continue }
        if ($best -and $v -le $best.Version) { continue }
        $sha = ''
        $digest = [string](Get-Prop $a 'digest' '')
        if ($digest -like 'sha256:*') { $sha = $digest.Substring(7) }
        $best = [pscustomobject]@{
          Version = $v; Url = $a.browser_download_url; File = $a.name; Size = [long](Get-Prop $a 'size' 0); Sha256 = $sha
        }
      }
      return $best
    }
    'nuget' {
      $pkg = ([string]$t.package).ToLower()
      $index = Get-Json "https://api.nuget.org/v3-flatcontainer/$pkg/index.json"
      $best = $null
      foreach ($s in @($index.versions)) {
        if ($s -notmatch '^\d+(\.\d+)+$') { continue }       # skip pre-releases
        $v = Get-Ver $s
        if (-not $v -or -not (Test-Pin $v $pin)) { continue }
        if ($best -and $v -le $best.Version) { continue }
        $best = [pscustomobject]@{
          Version = $v; Url = "https://api.nuget.org/v3-flatcontainer/$pkg/$s/$pkg.$s.nupkg"
          File = "$pkg.$s.zip"; Size = [long]0; Sha256 = ''
        }
      }
      return $best
    }
    'vscode' {
      $u = Get-Json 'https://update.code.visualstudio.com/api/update/win32-x64-archive/stable/latest'
      $v = Get-Ver ([string]$u.productVersion)
      if (-not $v -or -not $u.url) { return $null }
      return [pscustomobject]@{
        Version = $v; Url = [string]$u.url; File = "vscode-$v.zip"; Size = [long]0; Sha256 = [string](Get-Prop $u 'sha256hash' '')
      }
    }
    'msvc' {
      Update-MsvcScript
      $text = (Invoke-Capture (Get-ToolPython) @('-I', $MsvcScript, '--show-versions')) -join "`n"
      $msvcList = @(); $sdkList = @()
      if ($text -match 'MSVC versions:\s*([^\n]+)')        { $msvcList = @($Matches[1].Trim() -split '\s+') }
      if ($text -match 'Windows SDK versions:\s*([^\n]+)') { $sdkList  = @($Matches[1].Trim() -split '\s+') }
      if ($pin) {
        if ($msvcList -notcontains $pin) { throw "MSVC $pin is no longer offered (available: $($msvcList -join ', '))" }
        $m = [version]$pin
      } else {
        $m = $msvcList | ForEach-Object { Get-Ver $_ } | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
      }
      $sdk = $sdkList | ForEach-Object { if ($_ -match '(\d{5})') { [int]$Matches[1] } } |
        Sort-Object -Descending | Select-Object -First 1
      return [pscustomobject]@{ Version = $m; Sdk = $sdk }
    }
  }
}

function Test-NeedsUpdate($t, $Installed, $Latest) {
  if (-not $Latest) { return $false }
  if (-not $Installed -or -not $Installed.Version) { return $true }
  if ($t.type -eq 'msvc') {
    $pin = [string](Get-Prop $t 'pin' '')
    if ($pin -and -not (Test-Pin $Installed.Version $pin)) { return $true }
    if (-not $pin -and $Latest.Version -and $Installed.Version -lt $Latest.Version) { return $true }
    return ($Installed.Sdk -lt $Latest.Sdk)
  }
  return ($Latest.Version -gt $Installed.Version)
}

function Format-Ver($t, $Info) {
  if (-not $Info) { return '-' }
  if ($t.type -eq 'msvc') {
    if ($Info.Sdk) { return "$($Info.Version) / SDK $($Info.Sdk)" }
    return "$($Info.Version)"
  }
  if ($Info.Version) { return "$($Info.Version)" }
  return '?'
}

# ============================================================ cached state
function Save-State([string[]]$Pending) {
  try {
    @{ checked = (Get-Date).ToString('o'); pending = @($Pending) } | ConvertTo-Json |
      Set-Content -Path $StateFile -Encoding ASCII
  } catch { }
}

function Get-CachedPending {
  try {
    if (Test-Path $StateFile) {
      $s = Get-Content -Raw $StateFile | ConvertFrom-Json
      return @($s.pending | Where-Object { $_ })
    }
  } catch { }
  return @()
}

function Get-StatusRows([switch]$Quick) {
  $rows = @(); $pending = @(); $reached = 0
  foreach ($t in $script:Tools) {
    if ($Quick -and $t.type -eq 'msvc') { continue }   # the MSVC manifest is slow to fetch
    $inst = Get-Installed $t
    if ((Test-Optional $t) -and -not $inst) {
      $rows += [pscustomobject]@{ Tool = $t.name; Installed = '-'; Available = '-'; Status = 'optional'; Size = '-'; Bytes = $null; Error = $null }
      continue
    }
    $lat = $null; $err = $null
    try { $lat = Get-Latest $t; $reached++ } catch { $err = Get-ShortError $_ }
    if ($err)                               { $state = 'no data' }
    elseif (-not $lat)                      { $state = 'no Windows build' }
    elseif (-not $inst)                     { $state = 'MISSING'; $pending += $t.name }
    elseif (Test-NeedsUpdate $t $inst $lat) { $state = 'UPDATE';  $pending += $t.name }
    else                                    { $state = 'up to date' }
    $bytes = $null
    if (-not $Quick -and $inst) { $bytes = Get-ToolSize $t }
    $rows += [pscustomobject]@{
      Tool = $t.name; Installed = (Format-Ver $t $inst); Available = (Format-Ver $t $lat); Status = $state
      Size = (Format-Size $bytes); Bytes = $bytes; Error = $err
    }
  }
  if ($reached -gt 0) { Save-State $pending }
  return $rows
}

function Show-Status {
  if (-not (Test-Internet)) { Write-Warn 'No internet connection. Showing installed versions only.' }
  Write-Status 'Checking versions...'
  $rows = Get-StatusRows
  Clear-StatusLine
  $rows | Format-Table Tool, Installed, Available, Status, @{ Label = 'Size'; Expression = { $_.Size }; Align = 'Right' } -AutoSize |
    Out-String -Width 200 | ForEach-Object { Write-Summary $_.TrimEnd() }
  $total = ($rows | Where-Object { $null -ne $_.Bytes } | Measure-Object -Property Bytes -Sum).Sum
  if ($total) { Write-Summary "Total installed: $(Format-Size ([long]$total))" }
  $rows | Where-Object { $_.Error } | ForEach-Object { Write-Detail "  $($_.Tool): $($_.Error)" }
  if ($rows | Where-Object { $_.Status -in @('UPDATE', 'MISSING') }) { Write-Summary "`nRun: forgekitcc update" 'Yellow' }
}

# Weekly check shown when the build console opens. Silent when offline.
function Invoke-Notify {
  try {
    $pending = $null
    if (Test-Path $StateFile) {
      $s = Get-Content -Raw $StateFile | ConvertFrom-Json
      if (((Get-Date) - [datetime]$s.checked).TotalDays -lt $CheckIntervalDays) { $pending = @($s.pending | Where-Object { $_ }) }
    }
    if ($null -eq $pending) {
      if (-not (Test-Internet 3)) { return }
      $script:HttpTimeout = 5
      $pending = @(Get-StatusRows -Quick | Where-Object { $_.Status -in @('UPDATE', 'MISSING') } | ForEach-Object { $_.Tool })
    }
    if ($pending.Count -gt 0) { Write-Host "Updates available: $($pending -join ', ')  (run: forgekitcc update)" -ForegroundColor Yellow }
  } catch { }
}
