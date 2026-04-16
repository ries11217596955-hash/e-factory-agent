$ErrorActionPreference = 'Stop'

$FilePath = ".\agent.ps1"

if (-not (Test-Path -LiteralPath $FilePath)) {
    throw "File not found: $FilePath"
}

$content = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8

$replacements = @(
    @{
        Old = '$AuditResult.source = New-SourceLayer -Overrides (Safe-Get -Object $AuditResult -Key ''source'' -Default @{})'
        New = '$AuditResult[''source''] = New-SourceLayer -Overrides (Safe-Get -Object $AuditResult -Key ''source'' -Default @{})'
    },
    @{
        Old = '$AuditResult.live = New-LiveLayer -Overrides (Safe-Get -Object $AuditResult -Key ''live'' -Default @{})'
        New = '$AuditResult[''live''] = New-LiveLayer -Overrides (Safe-Get -Object $AuditResult -Key ''live'' -Default @{})'
    },
    @{
        Old = 'if (-not $AuditResult.ContainsKey(''required_inputs'') -or $null -eq $AuditResult.required_inputs) {'
        New = 'if (-not $AuditResult.ContainsKey(''required_inputs'') -or $null -eq $AuditResult[''required_inputs'']) {'
    },
    @{
        Old = '$AuditResult.required_inputs = @()'
        New = '$AuditResult[''required_inputs''] = @()'
    },
    @{
        Old = '$AuditResult.product_status = [string]$productStatusText'
        New = '$AuditResult[''product_status''] = [string]$productStatusText'
    },
    @{
        Old = '$AuditResult.product_status_detail = $productStatusDetail'
        New = '$AuditResult[''product_status_detail''] = $productStatusDetail'
    },
    @{
        Old = '$AuditResult.product_closeout = $productCloseout'
        New = '$AuditResult[''product_closeout''] = $productCloseout'
    },
    @{
        Old = '$AuditResult.schema_version = ''4.0'''
        New = '$AuditResult[''schema_version''] = ''4.0'''
    },
    @{
        Old = '$AuditResult.run_id = $runId'
        New = '$AuditResult[''run_id''] = $runId'
    },
    @{
        Old = '$AuditResult.target = if ([string]::IsNullOrWhiteSpace([string]$env:TARGET_REPO_PATH)) { [string]$env:BASE_URL } else { [string]$env:TARGET_REPO_PATH }'
        New = '$AuditResult[''target''] = if ([string]::IsNullOrWhiteSpace([string]$env:TARGET_REPO_PATH)) { [string]$env:BASE_URL } else { [string]$env:TARGET_REPO_PATH }'
    },
    @{
        Old = '$AuditResult.runtime = [ordered]@{'
        New = '$AuditResult[''runtime''] = [ordered]@{'
    },
    @{
        Old = '$AuditResult.decision = [ordered]@{'
        New = '$AuditResult[''decision''] = [ordered]@{'
    },
    @{
        Old = '$AuditResult.visual_coverage = $visualCoverage'
        New = '$AuditResult[''visual_coverage''] = $visualCoverage'
    },
    @{
        Old = '$AuditResult.facts = [ordered]@{'
        New = '$AuditResult[''facts''] = [ordered]@{'
    },
    @{
        Old = '$AuditResult.artifacts = [ordered]@{'
        New = '$AuditResult[''artifacts''] = [ordered]@{'
    },
    @{
        Old = '$AuditResult.live = $liveLayer'
        New = '$AuditResult[''live''] = $liveLayer'
    },
    @{
        Old = 'if ($AuditResult.decision -is [System.Collections.IDictionary]) {'
        New = 'if ($AuditResult[''decision''] -is [System.Collections.IDictionary]) {'
    },
    @{
        Old = '$AuditResult.decision.product_closeout = $productCloseout'
        New = '$AuditResult[''decision''][''product_closeout''] = $productCloseout'
    },
    @{
        Old = '$sourceStatus = if (-not (Safe-Get -Object $AuditResult.source -Key ''enabled'' -Default $false)) { ''OFF'' } elseif (Safe-Get -Object $AuditResult.source -Key ''ok'' -Default $false) { ''PASS'' } else { ''FAIL'' }'
        New = '$sourceStatus = if (-not (Safe-Get -Object $AuditResult[''source''] -Key ''enabled'' -Default $false)) { ''OFF'' } elseif (Safe-Get -Object $AuditResult[''source''] -Key ''ok'' -Default $false) { ''PASS'' } else { ''FAIL'' }'
    },
    @{
        Old = '$liveStatus = if (-not (Safe-Get -Object $AuditResult.live -Key ''enabled'' -Default $false)) { ''OFF'' } elseif (Safe-Get -Object $AuditResult.live -Key ''ok'' -Default $false) { ''PASS'' } else { ''FAIL'' }'
        New = '$liveStatus = if (-not (Safe-Get -Object $AuditResult[''live''] -Key ''enabled'' -Default $false)) { ''OFF'' } elseif (Safe-Get -Object $AuditResult[''live''] -Key ''ok'' -Default $false) { ''PASS'' } else { ''FAIL'' }'
    },
    @{
        Old = '$repoRoot = Safe-Get -Object $AuditResult.source -Key ''root'' -Default $null'
        New = '$repoRoot = Safe-Get -Object $AuditResult[''source''] -Key ''root'' -Default $null'
    },
    @{
        Old = '$sourceEnabled = [bool](Safe-Get -Object $AuditResult.source -Key ''enabled'' -Default $false)'
        New = '$sourceEnabled = [bool](Safe-Get -Object $AuditResult[''source''] -Key ''enabled'' -Default $false)'
    }
)

$changed = 0
$missing = New-Object System.Collections.Generic.List[string]

foreach ($pair in $replacements) {
    if ($content.Contains($pair.Old)) {
        $content = $content.Replace($pair.Old, $pair.New)
        $changed++
    }
    else {
        $missing.Add($pair.Old)
    }
}

$backupPath = "$FilePath.bak"
Copy-Item -LiteralPath $FilePath -Destination $backupPath -Force

Set-Content -LiteralPath $FilePath -Value $content -Encoding UTF8

Write-Host "PATCHED: $changed replacement(s)"
Write-Host "BACKUP:  $backupPath"

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "NOT FOUND:"
    $missing | ForEach-Object { Write-Host " - $_" }
}
else {
    Write-Host "All target lines replaced."
}
