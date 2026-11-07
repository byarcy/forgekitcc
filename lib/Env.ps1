# ForgeKitCC - Environment: build console variables, test build and user PATH.

# Extra variables set in the build console, on top of what MSVC's setup_x64.bat sets.
# They help other tools (Rust/cargo, Python setuptools, CMake) use the portable MSVC.
function Get-CompatVars {
  $vars = [ordered]@{}
  $m = Get-MsvcLayout
  if ($m -and $m.VcVersion) {
    $vc  = Join-Path $m.Root 'VC'
    $sdk = Join-Path $m.Root 'Windows Kits\10'
    $vars['VSINSTALLDIR']        = "$($m.Root)\"
    $vars['VCINSTALLDIR']        = "$vc\"
    $vars['VCToolsInstallDir']   = (Join-Path $vc "Tools\MSVC\$($m.VcVersion)") + '\'
    $vars['VCToolsVersion']      = $m.VcVersion
    $vars['VisualStudioVersion'] = '17.0'
    $vars['VSCMD_ARG_HOST_ARCH'] = 'x64'
    $vars['VSCMD_ARG_TGT_ARCH']  = 'x64'
    if ($m.SdkVersion) {
      $vars['WindowsSdkDir']      = "$sdk\"
      $vars['WindowsSDKVersion']  = "$($m.SdkVersion)\"
      $vars['UniversalCRTSdkDir'] = "$sdk\"
      $vars['UCRTVersion']        = $m.SdkVersion
    }
    $vars['DISTUTILS_USE_SDK'] = '1'      # Python setuptools: use cl/link from PATH
    $vars['MSSdk']             = '1'
  }
  $vars['CMAKE_GENERATOR'] = 'Ninja'      # default generator when a project does not choose one
  $vars['FORGEKITCC_ENV']  = '1'
  return $vars
}

# Lines read by forgekitcc.bat ("NAME=VALUE").
function Write-EnvLines {
  $m = Get-MsvcLayout
  if (-not $m -or -not (Test-Path $m.Setup)) { return }   # nothing is set when MSVC is missing
  Write-Output "FKCC_SETUP=$($m.Setup)"
  Write-Output ("FKCC_PATHS=" + ((Get-OurDirs) -join ';'))
  $vars = Get-CompatVars
  foreach ($k in $vars.Keys) { Write-Output "$k=$($vars[$k])" }
}

# Loads the same environment into this PowerShell process (used by the test build).
function Import-BuildEnv {
  $m = Get-MsvcLayout
  if (-not $m -or -not (Test-Path $m.Setup)) { throw 'MSVC is not installed. Run: forgekitcc update' }
  New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
  $dump = Join-Path $DownloadDir 'dump_env.cmd'
  Set-Content -Path $dump -Encoding ASCII -Value @('@echo off', "call `"$($m.Setup)`" >nul 2>&1", 'set')
  foreach ($line in (Invoke-Capture 'cmd.exe' @('/d', '/c', $dump))) {
    if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
  }
  $vars = Get-CompatVars
  foreach ($k in $vars.Keys) { [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process') }
  $env:Path = ((Get-OurDirs) -join ';') + ';' + $env:Path
}

# Builds and runs a small C++ program with clang-cl and with cl.
function Invoke-TestBuild {
  $ok = $true
  try { Import-BuildEnv } catch { Write-Status " build    FAILED: $(Get-ShortError $_)" 'Red' -Final; return $false }
  $dir = Join-Path $Root '_tmp_testbuild'
  Reset-Dir $dir
  Set-Content -Path (Join-Path $dir 'CMakeLists.txt') -Encoding ASCII -Value @(
    'cmake_minimum_required(VERSION 3.20)',
    'project(forgekitcc_test CXX)',
    'set(CMAKE_CXX_STANDARD 20)',
    'add_executable(hello main.cpp)'
  )
  Set-Content -Path (Join-Path $dir 'main.cpp') -Encoding ASCII -Value @(
    '#include <iostream>',
    '#include <string>',
    '#include <vector>',
    'int main() { std::vector<std::string> v{"forge", "kit"}; std::cout << "hello " << v.size() << "\n"; }'
  )
  foreach ($cc in 'clang-cl', 'cl') {
    $label = " {0,-7}" -f $cc
    Write-Status "$label  test build"
    $build = Join-Path $dir "build-$cc"
    try {
      Invoke-Capture 'cmake' @('-S', $dir, '-B', $build, '-G', 'Ninja', "-DCMAKE_CXX_COMPILER=$cc") | Out-Null
      Invoke-Capture 'cmake' @('--build', $build) | Out-Null
      $run = Invoke-Capture (Join-Path $build 'hello.exe')
      if (($run -join '') -notmatch 'hello 2') { throw 'the test program gave a wrong result' }
      Write-Status "$label  test build ok" 'Green' -Final
    } catch {
      $ok = $false
      Write-Status "$label  test build FAILED: $(Get-ShortError $_)" 'Red' -Final
      $script:LastOutput | Select-Object -Last 8 | ForEach-Object { Write-Detail "      $_" }
    }
  }
  Remove-Dir $dir
  if (-not $ok) { $h = Get-LogHint; if ($h) { Write-Summary "      $h" } }
  return $ok
}

# ============================================================ user PATH
function Test-OurDir([string]$Dir) {
  $d = $Dir.TrimEnd('\')
  return ($d -ieq $Root -or $d.StartsWith("$Root\", [StringComparison]::OrdinalIgnoreCase))
}

function Set-UserPath([switch]$Remove) {
  $key = Get-Item 'HKCU:\Environment'
  $current = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
  $others = @($current -split ';' | Where-Object { $_ -and -not (Test-OurDir $_) })
  if ($Remove) { $new = $others } else { $new = @(Get-OurDirs) + $others }
  New-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value ($new -join ';') -PropertyType ExpandString -Force | Out-Null
  # SetEnvironmentVariable also tells Windows that the environment changed.
  if ($Remove) { [Environment]::SetEnvironmentVariable('FORGEKITCC_ROOT', $null, 'User') }
  else         { [Environment]::SetEnvironmentVariable('FORGEKITCC_ROOT', $Root, 'User') }
  Write-Log 'INFO' "User PATH updated (remove=$Remove)."
}

function Invoke-SetPath([switch]$Remove) {
  if ($Remove) {
    Set-UserPath -Remove
    Write-Summary 'Removed from your user PATH. Open a new console.' 'Green'
  } else {
    Set-UserPath
    Write-Summary 'Added to your user PATH. Open a new console to use it.' 'Green'
    Write-Info 'MSVC itself (cl, INCLUDE, LIB) loads only in the build console.'
  }
}
