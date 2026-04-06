param(
    [string]$InboxPath
)

$zip = Get-ChildItem -Path $InboxPath -Filter *.zip -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $zip) {
    return $null
}

Write-Host "ZIP FOUND: $($zip.FullName)"
$zip.FullName
