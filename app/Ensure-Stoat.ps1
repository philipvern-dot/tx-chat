# Installs the official Stoat desktop app for the current user when it is missing.
# The only argument is the path to stoat-desktop-setup.exe, already downloaded.
# On failure, writes one line to %TEMP%\txchat-stoat-error.txt and exits 1.

param(
    [Parameter(Mandatory = $true)]
    [string] $SetupExe
)

$ErrorActionPreference = 'Stop'

$stub = Join-Path $env:LOCALAPPDATA 'Stoat\stoat-desktop.exe'
$errorFile = Join-Path $env:TEMP 'txchat-stoat-error.txt'
if (Test-Path -LiteralPath $errorFile) {
    Remove-Item -LiteralPath $errorFile -Force
}

function Fail([string] $Message) {
    Set-Content -LiteralPath $errorFile -Value $Message -Encoding Ascii
    exit 1
}

function Test-StoatReady {
    if (-not (Test-Path -LiteralPath $stub)) {
        return $false
    }
    $root = Join-Path $env:LOCALAPPDATA 'Stoat'
    $apps = @(Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue)
    foreach ($app in $apps) {
        if (Test-Path -LiteralPath (Join-Path $app.FullName 'stoat-desktop.exe')) {
            return $true
        }
    }
    return $false
}

if (Test-StoatReady) {
    exit 0
}

if (-not (Test-Path -LiteralPath $SetupExe)) {
    Fail 'The Stoat installer download is missing.'
}

try {
    Unblock-File -LiteralPath $SetupExe -ErrorAction SilentlyContinue
    $already = @(Get-Process -Name 'stoat-desktop' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    $proc = Start-Process -FilePath $SetupExe -PassThru
    $deadline = (Get-Date).AddMinutes(8)
    $readySince = $null
    while ((Get-Date) -lt $deadline) {
        if (Test-StoatReady) {
            if (-not $readySince) {
                $readySince = Get-Date
            } elseif ($proc.HasExited -or (((Get-Date) - $readySince).TotalSeconds -ge 15)) {
                break
            }
        } else {
            $readySince = $null
            if ($proc.HasExited) {
                break
            }
        }
        Start-Sleep -Milliseconds 500
    }

    if (-not (Test-StoatReady)) {
        Fail 'The official Stoat setup did not finish installing.'
    }

    Get-Process -Name 'stoat-desktop' -ErrorAction SilentlyContinue |
        Where-Object { $already -notcontains $_.Id } |
        Stop-Process -Force -ErrorAction SilentlyContinue

    if (-not $proc.HasExited) {
        $null = $proc.WaitForExit(20000)
    }
    exit 0
} catch {
    Fail $_.Exception.Message
}
