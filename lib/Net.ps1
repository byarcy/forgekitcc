# ForgeKitCC - Network: JSON APIs, connectivity and resumable downloads.

$MsvcScriptUrl = 'https://gist.githubusercontent.com/mmozeiko/7f3162ec2988e81e56d5c4e22cde9977/raw/portable-msvc.py'
$MsvcScript    = Join-Path $Root 'portable-msvc.py'
$script:MsvcScriptFresh = $false

function Get-Json([string]$Uri) {
  $h = @{ 'User-Agent' = "$AppName/$AppVersion" }
  if ($Uri -like 'https://api.github.com/*') {
    $h['Accept'] = 'application/vnd.github+json'
    if ($env:GITHUB_TOKEN) { $h['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
  }
  Write-Log 'NET' "GET $Uri"
  try { return Invoke-RestMethod -Uri $Uri -Headers $h -TimeoutSec $script:HttpTimeout }
  catch {
    $msg = $_.Exception.Message
    Write-Log 'NET' "Failed: $msg"
    if ($Uri -like 'https://api.github.com/*' -and $msg -match '403|rate limit') {
      throw 'GitHub refused the request (rate limit). Try later or set GITHUB_TOKEN.'
    }
    throw "cannot reach $(([Uri]$Uri).Host): $msg"
  }
}

# True if at least one of the servers answers. Any HTTP response counts as being online.
function Test-Internet([int]$TimeoutSec = 5) {
  foreach ($u in 'https://api.github.com', 'https://api.nuget.org/v3/index.json') {
    try {
      Invoke-WebRequest -UseBasicParsing -Method Head -Uri $u -TimeoutSec $TimeoutSec | Out-Null
      return $true
    } catch {
      if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { return $true }
    }
  }
  Write-Log 'NET' 'No internet connection detected.'
  return $false
}

function Get-RemoteSize([string]$Url) {
  try {
    $r = Invoke-WebRequest -UseBasicParsing -Method Head -Uri $Url -TimeoutSec $script:HttpTimeout
    $len = $r.Headers['Content-Length']
    if ($len -is [array]) { $len = $len[0] }
    if ($len) { return [long]$len }
  } catch { }
  return [long]0
}

function Get-CurlReason([int]$Code) {
  switch ($Code) {
    6       { return 'no internet connection' }
    7       { return 'cannot connect to the server' }
    18      { return 'connection lost' }
    22      { return 'the server returned an error' }
    23      { return 'cannot write the file (is the disk full?)' }
    28      { return 'connection too slow or timed out' }
    33      { return 'the server cannot resume downloads' }
    35      { return 'secure connection failed' }
    52      { return 'connection lost' }
    55      { return 'connection lost' }
    56      { return 'connection lost' }
    default { return "download error (curl code $Code)" }
  }
}

function Show-DownloadProgress($Ctx) {
  $have = 0
  if (Test-Path $Ctx.Part) { $have = (Get-Item $Ctx.Part).Length }
  if ($Ctx.Size -gt 0) {
    $pct = [Math]::Min(100, [int][Math]::Floor($have * 100 / $Ctx.Size))
    Write-Status ("{0}  downloading  {1}/{2} MB  {3}%" -f $Ctx.Label, (Format-MB $have), (Format-MB $Ctx.Size), $pct)
  } else {
    Write-Status ("{0}  downloading  {1} MB" -f $Ctx.Label, (Format-MB $have))
  }
}

# Downloads to "<file>.part" and resumes it if a previous attempt was interrupted.
# Checks size and SHA-256 (when known) before renaming it to <file>.
function Save-Download([string]$Url, [string]$OutFile, [long]$Size, [string]$Sha256, [string]$Label) {
  New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
  $part = "$OutFile.part"
  if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
  if ($Size -le 0) { $Size = Get-RemoteSize $Url }
  if ((Test-Path $part) -and $Size -gt 0 -and (Get-Item $part).Length -gt $Size) { Remove-Item $part -Force }
  Write-Log 'NET' "Download $Url -> $OutFile (size: $Size)"

  $ctx = @{ Part = $part; Size = $Size; Label = $Label }
  $maxAttempts = 3
  $restarted = $false
  for ($attempt = 1; $true; $attempt++) {
    $have = 0
    if (Test-Path $part) { $have = (Get-Item $part).Length }
    if ($Size -gt 0 -and $have -eq $Size) { break }
    if ($have -gt 0) { Write-Detail "  resuming at $(Format-MB $have) MB" }

    $curlArgs = @('-L', '--fail', '-sS', '-C', '-', '--connect-timeout', '20',
      '--speed-limit', '1024', '--speed-time', '60', '--retry', '3', '--retry-delay', '3', '-o', $part, $Url)
    $code = Invoke-Tracked 'curl.exe' $curlArgs $DownloadDir { param($elapsed, $c) Show-DownloadProgress $c } $ctx
    if ($code -eq 0) { break }

    # The partial file cannot be resumed: start once from zero.
    if (($code -eq 33 -or ($code -eq 22 -and $have -gt 0)) -and -not $restarted) {
      Write-Log 'NET' 'Resume not possible; restarting the download.'
      Remove-Item $part -Force -ErrorAction SilentlyContinue
      $restarted = $true
      continue
    }
    $reason = Get-CurlReason $code
    if (-not (Test-Internet)) { throw 'connection lost' }
    if ($attempt -ge $maxAttempts) { throw $reason }
    Write-Log 'NET' "Attempt $attempt failed ($reason). Retrying."
    Start-Sleep -Seconds 3
  }

  $actual = (Get-Item $part).Length
  if ($Size -gt 0 -and $actual -ne $Size) {
    Remove-Item $part -Force
    throw "incomplete download ($(Format-MB $actual) of $(Format-MB $Size) MB)"
  }
  if ($Sha256) {
    Write-Status "$Label  checking download"
    $hash = (Get-FileHash -Algorithm SHA256 -Path $part).Hash
    if ($hash -ne $Sha256) {
      Remove-Item $part -Force
      throw 'the download is damaged (checksum mismatch); it was deleted'
    }
    Write-Log 'NET' 'Checksum verified.'
  }
  Move-Item $part $OutFile -Force
}

function Update-MsvcScript {
  if ($script:MsvcScriptFresh -and (Test-Path $MsvcScript)) { return }
  try {
    Invoke-Capture 'curl.exe' @('-sSL', '--fail', '--retry', '2', '-o', $MsvcScript, $MsvcScriptUrl) | Out-Null
    $script:MsvcScriptFresh = $true
  } catch {
    if (-not (Test-Path $MsvcScript)) { throw 'cannot download portable-msvc.py' }
    Write-Log 'WARN' 'Could not refresh portable-msvc.py; using the local copy.'
  }
}
