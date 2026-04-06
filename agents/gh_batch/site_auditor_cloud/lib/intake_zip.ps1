
param(
    [string]$InboxPath
)

$zip = Get-ChildItem $InboxPath -Filter *.zip | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (!$zip) {
    Write-Output "NO ZIP FOUND"
    return $null
}

Write-Output "ZIP FOUND: $($zip.FullName)"
return $zip.FullName
