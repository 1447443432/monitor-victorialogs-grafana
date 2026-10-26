[CmdletBinding()]
param(
    [string]$Manifest,
    [ValidateSet('all', 'amd64', 'arm64')]
    [string]$Architecture = 'all',
    [string]$Proxy,
    [switch]$NoProxy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Manifest)) {
    $Manifest = Join-Path -Path $PSScriptRoot -ChildPath '..\packages\package-manifest.yaml'
}

$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
$packageDirectory = Join-Path (Split-Path -Parent $manifestPath) ''

# This manifest intentionally uses a small, fixed YAML shape, so no external YAML module is required.
$records = @()
$current = $null
$inDownloadSettings = $false
$manifestUseProxy = $true
$manifestProxy = $null
foreach ($line in Get-Content -Encoding utf8 -LiteralPath $manifestPath) {
    if ($line -match '^download:\s*$') { $inDownloadSettings = $true; continue }
    if ($inDownloadSettings -and $line -match '^\S') { $inDownloadSettings = $false }
    if ($inDownloadSettings -and $line -match '^\s+use_proxy:\s*(true|false)\s*$') {
        $manifestUseProxy = $Matches[1] -eq 'true'
        continue
    }
    if ($inDownloadSettings -and $line -match '^\s+proxy:\s*(\S+)\s*$') {
        $manifestProxy = $Matches[1]
        continue
    }
    if ($line -match '^\s+filename:\s*(\S+)\s*$') {
        if ($null -ne $current) {
            $records += [pscustomobject]$current
        }
        $current = @{ filename = $Matches[1] }
        continue
    }
    if ($null -eq $current) { continue }
    if ($line -match '^\s+use_proxy:\s*(true|false)\s*$') { $current.use_proxy = $Matches[1] -eq 'true'; continue }
    if ($line -match '^\s+size_bytes:\s*(\d+)\s*$') { $current.size_bytes = [int64]$Matches[1]; continue }
    if ($line -match '^\s+url:\s*(\S+)\s*$') { $current.url = $Matches[1]; continue }
    if ($line -match '^\s+sha256:\s*([0-9a-fA-F]{64})\s*$') { $current.sha256 = $Matches[1].ToLowerInvariant(); continue }
}
if ($null -ne $current) { $records += [pscustomobject]$current }

if ($records.Count -eq 0) { throw "No package records found in $manifestPath" }

$useProxy = $manifestUseProxy
if ($NoProxy) { $useProxy = $false }
if ($useProxy -and [string]::IsNullOrWhiteSpace($Proxy)) {
    $Proxy = $manifestProxy
    if ([string]::IsNullOrWhiteSpace($Proxy)) {
        $Proxy = @($env:HTTPS_PROXY, $env:HTTP_PROXY, $env:https_proxy, $env:http_proxy) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -First 1
    }
    if ([string]::IsNullOrWhiteSpace($Proxy)) {
        $Proxy = 'http://127.0.0.1:7897'
    }
}

foreach ($record in $records) {
    foreach ($field in @('filename', 'size_bytes', 'url', 'sha256')) {
        if ($record.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$record.$field)) {
            throw "Invalid package manifest: '$field' is missing for '$($record.filename)'"
        }
    }
    if ($record.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw "Invalid package manifest: SHA256 for '$($record.filename)' must contain exactly 64 hexadecimal characters"
    }
}

function Format-ByteSize {
    param([int64]$Bytes)

    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

function Format-Duration {
    param([double]$Seconds)

    if ($Seconds -lt 60) { return ('{0:N0}s' -f $Seconds) }
    $time = [TimeSpan]::FromSeconds($Seconds)
    if ($time.TotalHours -ge 1) { return $time.ToString('hh\h\ mm\m\ ss\s') }
    return $time.ToString('mm\m\ ss\s')
}

function Download-FileWithProgress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [string]$OutFile,
        [Parameter(Mandatory = $true)]
        [int64]$ExpectedBytes,
        [string]$Proxy
    )

    $webRequest = [System.Net.HttpWebRequest]::Create($Uri)
    $webRequest.Method = 'GET'
    $webRequest.UserAgent = 'monitor-victorialogs-grafana-package-downloader'
    if ([string]::IsNullOrWhiteSpace($Proxy)) {
        $webRequest.Proxy = $null
    } else {
        $webRequest.Proxy = New-Object System.Net.WebProxy($Proxy)
    }

    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        [int64]$existingBytes = 0
        if (Test-Path -LiteralPath $OutFile) {
            $existingBytes = (Get-Item -LiteralPath $OutFile).Length
            if ($existingBytes -gt $ExpectedBytes) {
                Remove-Item -LiteralPath $OutFile -Force
                $existingBytes = 0
            } elseif ($existingBytes -eq $ExpectedBytes) {
                Write-Host "[RESUME] temporary file already has the expected size: $(Format-ByteSize $existingBytes)"
                return
            }
        }

        if ($existingBytes -gt 0) {
            $webRequest.AddRange($existingBytes)
            Write-Host "[RESUME] continuing from $(Format-ByteSize $existingBytes)"
        }
        $response = $webRequest.GetResponse()
        $inputStream = $response.GetResponseStream()
        $append = $existingBytes -gt 0 -and [int]$response.StatusCode -eq 206
        if ($existingBytes -gt 0 -and -not $append) {
            Write-Host '[RESUME] server did not accept Range; restarting from zero'
            $existingBytes = 0
        }
        $fileMode = if ($append) { [System.IO.FileMode]::Append } else { [System.IO.FileMode]::Create }
        $outputStream = [System.IO.File]::Open($OutFile, $fileMode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $buffer = New-Object byte[] (1024 * 1024)
        [int64]$downloadedBytes = $existingBytes
        $lastReportedPercent = -1
        $startedAt = Get-Date
        $lastReportedAt = $startedAt

        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $read)
            $downloadedBytes += $read
            $percent = [math]::Min(100, [math]::Floor(($downloadedBytes * 100) / $ExpectedBytes))
            $now = Get-Date
            if ($percent -gt $lastReportedPercent -or (($now - $lastReportedAt).TotalMilliseconds -ge 500)) {
                $elapsedSeconds = ((Get-Date) - $startedAt).TotalSeconds
                $speed = if ($elapsedSeconds -gt 0) { $downloadedBytes / $elapsedSeconds } else { 0 }
                $remainingSeconds = if ($speed -gt 0) { ($ExpectedBytes - $downloadedBytes) / $speed } else { 0 }
                $progressText = '[PROGRESS] {0} / {1} ({2}%) | {3}/s | ETA {4}' -f (Format-ByteSize $downloadedBytes), (Format-ByteSize $ExpectedBytes), $percent, (Format-ByteSize $speed), (Format-Duration $remainingSeconds)
                [Console]::Write(("`r" + $progressText).PadRight(120))
                if ($percent -eq 100) { Write-Host }
                $lastReportedPercent = $percent
                $lastReportedAt = $now
            }
        }
    } finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
    }
}

function Remove-OldPackageFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetFileName
    )

    $pattern = switch -Regex ($TargetFileName) {
        '^victoria-logs-linux-(amd64|arm64)-' { '^victoria-logs-linux-' + $Matches[1] + '-.+\.tar\.gz$'; break }
        '^grafana_.+_linux_(amd64|arm64)\.tar\.gz$' { '^grafana_.+_linux_' + $Matches[1] + '\.tar\.gz$'; break }
        '^victoriametrics-logs-datasource-' { '^victoriametrics-logs-datasource-.+\.tar\.gz$'; break }
        default { $null }
    }

    if ([string]::IsNullOrWhiteSpace($pattern)) { return }

    Get-ChildItem -LiteralPath $packageDirectory -File |
        Where-Object { $_.Name -ne $TargetFileName -and $_.Name -match $pattern } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            Write-Host "[INFO] removed old package: $($_.Name)"
        }
}

$selected = $records | Where-Object {
    $isAll = $_.filename -like 'victoriametrics-logs-datasource-*'
    $isArch = ($Architecture -eq 'all') -or ($_.filename -match "linux-$Architecture")
    $isAll -or $isArch
}

Write-Host "Manifest: $manifestPath"
Write-Host "Architecture: $Architecture"
Write-Host "Proxy: $(if ($useProxy) { $Proxy } else { 'disabled' })"

foreach ($record in $selected) {
    $target = Join-Path $packageDirectory $record.filename
    $temp = "$target.download"
    $recordUseProxy = $useProxy
    if ($NoProxy) {
        $recordUseProxy = $false
    } elseif ($record.PSObject.Properties.Name -contains 'use_proxy') {
        $recordUseProxy = [bool]$record.use_proxy
    }

    if ((Test-Path -LiteralPath $target) -and
        ((Get-Item -LiteralPath $target).Length -eq $record.size_bytes) -and
        ((Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant() -eq $record.sha256)) {
        Write-Host "[SKIP] already verified, skip download: $($record.filename)"
        Write-Host "[SKIP] size and SHA256 verified: $(Format-ByteSize $record.size_bytes)"
        Remove-OldPackageFiles -TargetFileName $record.filename
        continue
    }

    Write-Host "[INFO] downloading: $($record.filename)"
    Write-Host "[INFO] url: $($record.url)"
    try {
        Write-Host "[INFO] proxy: $(if ($recordUseProxy) { $Proxy } else { 'disabled' })"
        Download-FileWithProgress -Uri $record.url -OutFile $temp -ExpectedBytes $record.size_bytes -Proxy $(if ($recordUseProxy) { $Proxy } else { $null })
    } catch {
        throw "Download failed for $($record.filename) via $Proxy. URL: $($record.url). $($_.Exception.Message)"
    }

    $downloaded = Get-Item -LiteralPath $temp
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temp).Hash.ToLowerInvariant()
    if ($downloaded.Length -ne $record.size_bytes) {
        Remove-Item -LiteralPath $temp -Force
        throw "Size mismatch for $($record.filename): expected $($record.size_bytes), got $($downloaded.Length)"
    }
    if ($actualHash -ne $record.sha256) {
        Remove-Item -LiteralPath $temp -Force
        throw "SHA256 mismatch for $($record.filename): expected $($record.sha256), got $actualHash"
    }

    Move-Item -LiteralPath $temp -Destination $target -Force
    Write-Host "[OK] downloaded and verified: $($record.filename)"
    Remove-OldPackageFiles -TargetFileName $record.filename
}

Write-Host '[OK] package download complete'
