# ForgeKitCC - Interactive menu. Opens without network checks and waits for a key press.

$script:KeyInput = $true
try { $script:KeyInput = -not [Console]::IsInputRedirected } catch { $script:KeyInput = $false }
$script:MenuStates = $null

function Read-Choice([string[]]$Valid) {
  Write-Host ''
  Write-Host ' Press a number: ' -NoNewline -ForegroundColor Cyan
  while ($true) {
    if ($script:KeyInput) {
      $k = [Console]::ReadKey($true)
      if ($k.Key -eq [ConsoleKey]::Escape) { $c = '0' } else { $c = ([string]$k.KeyChar).ToLower() }
    } else {
      $line = Read-Host
      if ($null -eq $line) { $c = '0' } else { $c = $line.Trim().ToLower() }
    }
    if ($Valid -contains $c) { Write-Host $c; return $c }
  }
}

function Wait-AnyKey {
  Write-Host ''
  Write-Host ' Press any key to go back...' -NoNewline -ForegroundColor DarkGray
  if ($script:KeyInput) { [void][Console]::ReadKey($true) } else { [void](Read-Host) }
  Write-Host ''
}

function Confirm-Menu([string]$Question) {
  Write-Host ''
  Write-Host " $Question [y/N] " -NoNewline -ForegroundColor Yellow
  if ($script:KeyInput) { $c = ([string][Console]::ReadKey($true).KeyChar).ToLower() }
  else { $c = [string](Read-Host); $c = $c.Trim().ToLower() }
  Write-Host $c
  return ($c -eq 'y' -or $c -eq 'yes')
}

# Tool states for the header, without using the network ("UPDATE" comes from the last check).
function Get-MenuStates {
  $pending = Get-CachedPending
  $states = @()
  foreach ($t in $script:Tools) {
    $inst = Get-Installed $t
    if (-not $inst -and (Test-Optional $t)) { $s = 'off'; $c = 'DarkGray' }
    elseif (-not $inst)               { $s = 'missing'; $c = 'Red' }
    elseif (-not $inst.Version)       { $s = 'broken';  $c = 'Red' }
    elseif ($pending -contains $t.name) { $s = 'UPDATE'; $c = 'Yellow' }
    else                              { $s = 'ok';      $c = 'Green' }
    $states += [pscustomobject]@{ Name = $t.name; State = $s; Color = $c; Version = (Format-Ver $t $inst) }
  }
  return $states
}

function Show-Header([string]$Title = '') {
  if ($null -eq $script:MenuStates) { $script:MenuStates = Get-MenuStates }
  try { Clear-Host } catch { }
  Write-Host ''
  Write-Host " $AppName v$AppVersion" -ForegroundColor Cyan
  Write-Host (' ' + ('-' * 58)) -ForegroundColor DarkGray
  Write-Host ' ' -NoNewline
  foreach ($s in $script:MenuStates) {
    Write-Host "$($s.Name) " -NoNewline
    Write-Host $s.State -NoNewline -ForegroundColor $s.Color
    Write-Host '   ' -NoNewline
  }
  Write-Host ''
  Write-Host ''
  if ($Title) { Write-Host " $Title" -ForegroundColor Cyan }
}

function Show-Options([object[]]$Options) {
  foreach ($o in $Options) { Write-Host ("  {0}  {1}" -f $o[0], $o[1]) }
}

function Invoke-MenuAction([scriptblock]$Action) {
  Write-Host ''
  try { & $Action } catch { Write-Err "ERROR: $(Get-ShortError $_)"; $h = Get-LogHint; if ($h) { Write-Summary "       $h" } }
  Close-StatusLine
  Wait-AnyKey
}

function Read-ToolNumbers {
  Show-Header 'Choose tools'
  for ($i = 0; $i -lt $script:MenuStates.Count; $i++) {
    $s = $script:MenuStates[$i]
    $size = '-'
    if ($s.State -ne 'missing') { $size = Format-Size (Get-ToolSize $script:Tools[$i]) }
    Write-Host ("  {0}  {1,-8} {2,-22} {3,8}" -f ($i + 1), $s.Name, $s.Version, $size)
  }
  Write-Host ''
  $answer = Read-Host ' Numbers separated by spaces (Enter = back)'
  $picked = @()
  foreach ($n in ([string]$answer -split '[\s,]+' | Where-Object { $_ })) {
    $k = 0
    if ([int]::TryParse($n, [ref]$k) -and $k -ge 1 -and $k -le $script:Tools.Count) { $picked += $script:Tools[$k - 1].name }
  }
  return @($picked | Select-Object -Unique)
}

function Show-UpdateMenu {
  Show-Header 'Install / update'
  Show-Options @(@('1', 'Update all'), @('2', 'Choose tools'), @('0', 'Back'))
  switch (Read-Choice @('1', '2', '0')) {
    '1' { Invoke-MenuAction { [void](Invoke-Update @()) }; $script:MenuStates = $null }
    '2' {
      $sel = @(Read-ToolNumbers)
      if ($sel.Count -gt 0) { Invoke-MenuAction { [void](Invoke-Update $sel) }; $script:MenuStates = $null }
    }
  }
}

function Show-CheckMenu {
  Show-Header 'Check installation'
  Show-Options @(@('1', 'Quick check'), @('2', 'Full check + test build'), @('0', 'Back'))
  $c = Read-Choice @('1', '2', '0')
  if ($c -eq '0') { return }
  Write-Host ''
  try {
    $bad = @(Invoke-Verify @() -Full:($c -eq '2') | Where-Object { Get-Tool $_ })
    Close-StatusLine
    if ($bad.Count -eq 0) {
      Write-Summary "`nEverything is fine." 'Green'
    } elseif (Confirm-Menu "Repair $($bad -join ', ') now?") {
      Write-Host ''
      [void](Invoke-Update $bad -Force)
      $script:MenuStates = $null
    }
  } catch { Write-Err "ERROR: $(Get-ShortError $_)" }
  Close-StatusLine
  Wait-AnyKey
}

function Show-SettingsMenu {
  Show-Header 'Settings'
  Show-Options @(@('1', 'Add to PATH'), @('2', 'Remove from PATH'), @('3', 'Open log folder'), @('4', 'Clean temp files'), @('0', 'Back'))
  switch (Read-Choice @('1', '2', '3', '4', '0')) {
    '1' { Invoke-MenuAction { Invoke-SetPath } }
    '2' { if (Confirm-Menu 'Remove ForgeKitCC from your user PATH?') { Invoke-MenuAction { Invoke-SetPath -Remove } } }
    '3' {
      New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
      Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$LogDir`""
    }
    '4' { Invoke-MenuAction { Invoke-Clean } }
  }
}

function Open-BuildConsole {
  $m = Get-MsvcLayout
  if (-not $m -or -not (Test-Path $m.Setup)) {
    Write-Host ''
    Write-Warn ' MSVC is not installed yet. Use option 3 first.'
    Wait-AnyKey
    return
  }
  Start-Process -FilePath (Join-Path $Root 'env.bat') -WorkingDirectory $Root
}

# Folder picker window; falls back to typing the path.
function Read-Folder([string]$Start) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Choose the project folder to open in VS Code'
    if ($Start) { $d.SelectedPath = $Start }
    if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $d.SelectedPath }
    return ''
  } catch {
    $hint = ''
    if ($Start) { $hint = " (Enter = $Start)" }
    $f = [string](Read-Host " Project folder$hint")
    if (-not $f.Trim()) { return $Start }
    return $f.Trim().Trim('"')
  }
}

function Open-VSCodeMenu {
  if (-not (Get-VSCodeExe)) {
    if (-not (Confirm-Menu 'VS Code is not installed (about 120 MB). Install it now?')) { return }
    Write-Host ''
    $ok = $false
    try { $ok = Invoke-Update @('vscode') } catch { Write-Err "ERROR: $(Get-ShortError $_)" }
    Close-StatusLine
    $script:MenuStates = $null
    if (-not $ok -or -not (Get-VSCodeExe)) { Wait-AnyKey; return }
  }
  Write-Host ''
  Write-Host ' Choose the project folder...' -ForegroundColor DarkGray
  $folder = Read-Folder (Get-RecentFolder)
  if (-not $folder) { return }
  $init = $false
  if (-not (Test-Path (Join-Path $folder '.vscode'))) {
    $init = Confirm-Menu 'Add build (Ctrl+Shift+B) and debug (F5) settings to this folder?'
  }
  try { Open-VSCode $folder -Init:$init }
  catch { Write-Err "ERROR: $(Get-ShortError $_)"; Wait-AnyKey }
}

function Show-Menu {
  while ($true) {
    Show-Header
    Show-Options @(
      @('1', 'Open build console'),
      @('2', 'Open VS Code'),
      @('3', 'Install / update'),
      @('4', 'Check installation'),
      @('5', 'Settings'),
      @('0', 'Exit')
    )
    switch (Read-Choice @('1', '2', '3', '4', '5', '0')) {
      '1' { Open-BuildConsole }
      '2' { Open-VSCodeMenu }
      '3' { Show-UpdateMenu }
      '4' { Show-CheckMenu }
      '5' { Show-SettingsMenu }
      '0' { return }
    }
  }
}
