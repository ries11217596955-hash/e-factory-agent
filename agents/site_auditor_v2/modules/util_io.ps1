Set-StrictMode -Version Latest

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Data
    )

    $directory = Split-Path -Path $Path -Parent
    Ensure-Directory -Path $directory
    $json = $Data | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, (New-SafeUtf8NoBom))
}
