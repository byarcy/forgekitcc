#Requires -Version 5.1
<#
  ForgeKitCC - portable C/C++ toolchain manager for Windows.
  MSVC (VS 2022 toolset) + Windows SDK + clang-cl (LLVM) + CMake + Ninja + Python,
  in one folder, without installing Visual Studio and without admin rights.

  Run it through forgekitcc.bat. Without a command it opens the interactive menu.
#>
# No param() block on purpose: every argument (including -v, -q, --verbose) arrives in $args.
$Command = 'menu'
$Rest = @()
$allArgs = @($args | ForEach-Object { [string]$_ })
if ($allArgs.Count -gt 0) {
  if ($allArgs[0].StartsWith('-')) { $Rest = $allArgs }
  else { $Command = $allArgs[0]; $Rest = @($allArgs | Select-Object -Skip 1) }
}

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

$Root = $PSScriptRoot.TrimEnd('\', '/')
foreach ($module in 'Core', 'Net', 'Versions', 'Install', 'Env', 'Menu') {
  . (Join-Path (Join-Path $Root 'lib') "$module.ps1")
}

# ------------------------------------------------------------ options
$Flags = @($Rest | Where-Object { $_ -and ($_ -like '--*' -or $_ -in @('-v', '-q')) })
$Names = @($Rest | Where-Object { $_ -and $Flags -notcontains $_ })
if ($Flags -contains '--verbose' -or $Flags -contains '-v') { $script:Verbosity = 2 }
if ($Flags -contains '--quiet' -or $Flags -contains '-q')   { $script:Verbosity = 0 }
if ($Flags -contains '--accept-license') { $script:AcceptLicense = $true }
$FullCheck = $Flags -contains '--full'
$InitVSCode = $Flags -contains '--init'
foreach ($f in $Flags) {
  if ($f -notin @('--verbose', '-v', '--quiet', '-q', '--accept-license', '--full', '--init')) {
    Write-Host "Unknown option '$f'. See: forgekitcc help" -ForegroundColor Yellow
    exit 1
  }
}

function Show-Help {
  $names = ($script:Tools | ForEach-Object { $_.name }) -join ', '
  Write-Host @"
$AppName v$AppVersion - portable C/C++ toolchain for Windows

Usage: forgekitcc [command] [tools] [options]

  (no command)        Open the interactive menu
  status              Installed and available versions
  update [tools]      Install missing tools and update the rest
  install [tools]     Install missing tools only
  repair [tools]      Reinstall tools (fixes damaged installs)
  verify [tools]      Check that the installed files are complete
  verify --full       Also check file contents and build a test program
  env                 Load the build environment into this console
  code [folder]       Open VS Code with the build environment (needs: install vscode)
  code --init         Also add build (Ctrl+Shift+B) and debug (F5) settings
  path add | remove   Add or remove the tools in your user PATH
  clean               Delete downloads and temporary folders
  version             Show the ForgeKitCC version
  help                Show this help

Tools:   $names (default: all; vscode is optional)
Options: --verbose (-v)     more detail on screen
         --quiet (-q)       only errors and the final summary
         --accept-license   accept the Visual Studio Build Tools license

Logs: logs\   Settings: tools.json   Guide: GUIDE.md
"@
}

# ------------------------------------------------------------ main
$internal = $Command -like 'internal-*'
try {
  $script:Tools = @(Import-Config)
  if (-not $internal -and $Command -notin @('help', 'version')) { Start-Log (@($Command) + @($Rest) -join ' ') }

  $ok = $true
  switch ($Command.ToLower()) {
    'menu'    { Show-Menu }
    'status'  { Show-Status }
    'update'  { $ok = Invoke-Update $Names }
    'install' { $ok = Invoke-Update $Names -MissingOnly }
    'repair'  { $ok = Invoke-Update $Names -Force }
    'verify'  {
      $bad = @(Invoke-Verify $Names -Full:$FullCheck)
      Close-StatusLine
      if ($bad.Count -eq 0) { Write-Summary "`nEverything is fine." 'Green' }
      else {
        $tools = @($bad | Where-Object { Get-Tool $_ })
        if ($tools.Count -gt 0) { Write-Summary "`nTo fix it, run: forgekitcc repair $($tools -join ' ')" 'Yellow' }
        $ok = $false
      }
    }
    'doctor'  { $ok = Invoke-TestBuild }
    'code'    {
      $folder = ''
      if ($Names.Count -gt 0) { $folder = $Names[0] }
      Open-VSCode $folder -Init:$InitVSCode
    }
    'clean'   { Invoke-Clean }
    'path' {
      $sub = ''
      if ($Names.Count -gt 0) { $sub = $Names[0].ToLower() }
      switch ($sub) {
        'add'    { Invoke-SetPath }
        'remove' { Invoke-SetPath -Remove }
        default  { throw 'usage: forgekitcc path add | forgekitcc path remove' }
      }
    }
    'version' { Write-Host "$AppName v$AppVersion" }
    'help'    { Show-Help }
    # Used by forgekitcc.bat
    'internal-env'    { Write-EnvLines }
    'internal-notify' { Invoke-Notify }
    default {
      Write-Host "Unknown command '$Command'." -ForegroundColor Yellow
      Write-Host ''
      Show-Help
      exit 1
    }
  }
  Close-StatusLine
  if (-not $ok) { exit 1 }
} catch {
  Close-StatusLine
  if ($internal) { exit 1 }
  Write-Err "ERROR: $(Get-ShortError $_)"
  Write-Log 'ERROR' ($_ | Out-String)
  $h = Get-LogHint
  if ($h) { Write-Host "       $h" }
  exit 1
}
