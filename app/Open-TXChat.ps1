# Opens Stoat on the private server.
# Stoat can only run one copy. A second launch ignores --force-server and
# shows the window that is already open. Sign-in also starts that one copy
# without the private server. This script turns that sign-in start off,
# closes a copy that is on the wrong server, and repairs a blank window.

$ErrorActionPreference = 'Stop'

$Server = 'https://txchat.duckdns.org'
$Stub = Join-Path $env:LOCALAPPDATA 'Stoat\stoat-desktop.exe'
$Fallback = 'get:()=>s||{firstLaunch:!1,customFrame:!0,minimiseToTray:!0,startMinimisedToTray:!1,spellchecker:!0,hardwareAcceleration:!0,discordRpc:!0,windowState:{x:0,y:0,width:0,height:0,isMaximised:!1}},'

function Show-Problem([string] $Message) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($Message, 'TX Chat') | Out-Null
}

function Remove-StoatSignInStart {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path -LiteralPath $key)) {
        return
    }
    $item = Get-ItemProperty -LiteralPath $key
    foreach ($property in $item.PSObject.Properties) {
        if ($property.Name -like 'PS*') {
            continue
        }
        $value = [string] $property.Value
        if ($value -match 'stoat-desktop' -and $value -notmatch [regex]::Escape($Server)) {
            Remove-ItemProperty -LiteralPath $key -Name $property.Name -ErrorAction SilentlyContinue
        }
    }
}

function Get-StoatAppDir {
    $root = Join-Path $env:LOCALAPPDATA 'Stoat'
    $apps = @(Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
        Sort-Object { try { [version] $_.Name.Substring(4) } catch { [version] '0.0' } })
    $best = $null
    foreach ($app in $apps) {
        $exe = Join-Path $app.FullName 'stoat-desktop.exe'
        $asar = Join-Path $app.FullName 'resources\app.asar'
        if ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $asar)) {
            $best = $app.FullName
        }
    }
    return $best
}

function Read-AsarLayout([string] $Path) {
    $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'Read')
    try {
        $sizeBuf = New-Object byte[] 8
        if ($stream.Read($sizeBuf, 0, 8) -ne 8) {
            throw 'Stoat app package header is unreadable.'
        }
        $headerLen = [BitConverter]::ToUInt32($sizeBuf, 4)
        $header = New-Object byte[] $headerLen
        if ($stream.Read($header, 0, $headerLen) -ne $headerLen) {
            throw 'Stoat app package header is unreadable.'
        }
        $jsonLen = [BitConverter]::ToInt32($header, 4)
        $json = [System.Text.Encoding]::UTF8.GetString($header, 8, $jsonLen)
        $dataStart = 8 + $headerLen
        return @{ Json = $json; DataStart = [int] $dataStart; Stream = $stream }
    } catch {
        $stream.Dispose()
        throw
    }
}

function Get-Sha256Hex([byte[]] $Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function New-AsarPickle([string] $Json) {
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $aligned = ($jsonBytes.Length + 3) -band -bnot 3
    $payload = 4 + $aligned
    $header = New-Object byte[] (4 + $payload)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32] $payload), 0, $header, 0, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([int32] $jsonBytes.Length), 0, $header, 4, 4)
    [Buffer]::BlockCopy($jsonBytes, 0, $header, 8, $jsonBytes.Length)
    $size = New-Object byte[] 8
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32] 4), 0, $size, 0, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32] $header.Length), 0, $size, 4, 4)
    return @{ Size = $size; Header = $header; JsonBytes = $jsonBytes }
}

function Read-StreamRange($Stream, [int] $Offset, [int] $Count) {
    $buffer = New-Object byte[] $Count
    $stream.Position = $Offset
    $read = 0
    while ($read -lt $Count) {
        $n = $stream.Read($buffer, $read, $Count - $read)
        if ($n -le 0) {
            throw 'Stoat app package ended early.'
        }
        $read += $n
    }
    return $buffer
}

function Repair-StoatPreload([string] $AppDir) {
    $asar = Join-Path $AppDir 'resources\app.asar'
    $exe = Join-Path $AppDir 'stoat-desktop.exe'
    $layout = Read-AsarLayout $asar
    try {
        $json = $layout.Json
        $preloadMatch = [regex]::Match($json, '"preload\.js":\{"size":(?<size>\d+),"offset":"(?<offset>\d+)","integrity":\{"algorithm":"SHA256","hash":"(?<hash>[0-9a-f]+)","blockSize":4194304,"blocks":\["(?<block>[0-9a-f]+)"\]\}')
        $packageMatch = [regex]::Match($json, '"package\.json":\{"size":(?<size>\d+),"offset":"(?<offset>\d+)"')
        if (-not $preloadMatch.Success -or -not $packageMatch.Success) {
            return
        }
        $preloadOffset = [int] $preloadMatch.Groups['offset'].Value
        $preloadSize = [int] $preloadMatch.Groups['size'].Value
        $preload = Read-StreamRange $layout.Stream ($layout.DataStart + $preloadOffset) $preloadSize
        $preloadText = [System.Text.Encoding]::UTF8.GetString($preload)
        if ($preloadText.Contains('get:()=>s||')) {
            return
        }
        if (-not $preloadText.Contains('get:()=>s,')) {
            return
        }
        $patchedText = $preloadText.Replace('get:()=>s,', $Fallback)
        $patched = [System.Text.Encoding]::UTF8.GetBytes($patchedText)
        $hash = Get-Sha256Hex $patched
        $entry = '"preload.js":{"size":' + $patched.Length + ',"offset":"' + $preloadOffset + '","integrity":{"algorithm":"SHA256","hash":"' + $hash + '","blockSize":4194304,"blocks":["' + $hash + '"]}'
        $json = $json.Remove($preloadMatch.Index, $preloadMatch.Length).Insert($preloadMatch.Index, $entry)
        $delta = $patched.Length - $preloadSize
        if ($delta -ne 0) {
            $builder = New-Object System.Text.StringBuilder
            $last = 0
            foreach ($offsetMatch in [regex]::Matches($json, '"offset":"(\d+)"')) {
                [void] $builder.Append($json.Substring($last, $offsetMatch.Index - $last))
                $number = [int] $offsetMatch.Groups[1].Value
                if ($number -gt $preloadOffset) {
                    $number += $delta
                }
                [void] $builder.Append('"offset":"' + $number + '"')
                $last = $offsetMatch.Index + $offsetMatch.Length
            }
            [void] $builder.Append($json.Substring($last))
            $json = $builder.ToString()
        }
        $before = Read-StreamRange $layout.Stream $layout.DataStart $preloadOffset
        $afterAt = $layout.DataStart + $preloadOffset + $preloadSize
        $afterCount = [int] ($layout.Stream.Length - $afterAt)
        $after = Read-StreamRange $layout.Stream $afterAt $afterCount
    } finally {
        $layout.Stream.Dispose()
    }

    $pickle = New-AsarPickle $json
    $tempAsar = Join-Path $env:TEMP 'txchat-app.asar'
    $out = [System.IO.File]::Create($tempAsar)
    try {
        $out.Write($pickle.Size, 0, $pickle.Size.Length)
        $out.Write($pickle.Header, 0, $pickle.Header.Length)
        $out.Write($before, 0, $before.Length)
        $out.Write($patched, 0, $patched.Length)
        if ($after.Length -gt 0) {
            $out.Write($after, 0, $after.Length)
        }
    } finally {
        $out.Dispose()
    }
    Move-Item -LiteralPath $tempAsar -Destination $asar -Force

    $exeBytes = [System.IO.File]::ReadAllBytes($exe)
    $exeText = [System.Text.Encoding]::ASCII.GetString($exeBytes)
    $marker = '[{"file":"resources\\app.asar","alg":"SHA256","value":"'
    $markerAt = $exeText.IndexOf($marker)
    if ($markerAt -ge 0) {
        $headerHash = Get-Sha256Hex $pickle.JsonBytes
        $hashBytes = [System.Text.Encoding]::ASCII.GetBytes($headerHash)
        [System.Buffer]::BlockCopy($hashBytes, 0, $exeBytes, $markerAt + $marker.Length, 64)
        [System.IO.File]::WriteAllBytes($exe, $exeBytes)
    }
}

function Test-PreloadNeedsRepair([string] $AppDir) {
    $asar = Join-Path $AppDir 'resources\app.asar'
    $layout = Read-AsarLayout $asar
    try {
        $match = [regex]::Match($layout.Json, '"preload\.js":\{"size":(?<size>\d+),"offset":"(?<offset>\d+)"')
        if (-not $match.Success) {
            return $false
        }
        $count = [int] $match.Groups['size'].Value
        $offset = $layout.DataStart + [int] $match.Groups['offset'].Value
        $bytes = Read-StreamRange $layout.Stream $offset $count
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        return ($text.Contains('get:()=>s,') -and -not $text.Contains('get:()=>s||'))
    } finally {
        $layout.Stream.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $Stub)) {
    Show-Problem 'Stoat is not installed. Run the TX Chat setup again.'
    exit 1
}

Remove-StoatSignInStart

$appDir = Get-StoatAppDir
if (-not $appDir) {
    Show-Problem 'Stoat is not installed. Run the TX Chat setup again.'
    exit 1
}

$needsRepair = Test-PreloadNeedsRepair $appDir
$running = @(Get-CimInstance Win32_Process -Filter "Name = 'stoat-desktop.exe'" | Where-Object { $_.CommandLine -notmatch '--type=' })
$onServer = @($running | Where-Object { $_.CommandLine -match [regex]::Escape($Server) })

if ($needsRepair -or $onServer.Count -eq 0) {
    Get-Process -Name 'stoat-desktop' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
    if ($needsRepair) {
        Repair-StoatPreload $appDir
    }
}

Start-Process -FilePath $Stub -ArgumentList "--force-server=$Server"
