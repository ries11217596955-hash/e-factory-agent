param(
    [Parameter(Mandatory)][string]$RequestPath,
    [string]$RegistryPath = 'agents/site_auditor_v3/contracts/module_registry.json'
)

$ErrorActionPreference = "Stop"

function Read-Json($p) {
    Get-Content $p -Raw | ConvertFrom-Json -AsHashtable
}

$registry = Read-Json $RegistryPath
$request  = Read-Json $RequestPath

$pipeline_state = @{
    run = @{
        execution_status = "RUNNING"
    }
    request = $request
}

foreach ($m in ($registry.modules | Sort-Object ordinal)) {

    if (-not $m.enabled) { continue }

    . $m.file_path

    $fn = Get-Command $m.entry_function -ErrorAction Stop

    $input = @{}

    foreach ($k in $m.reads_state_paths) {
        if (-not $pipeline_state.ContainsKey($k)) {
            throw "Missing pipeline key: $k for module $($m.module_id)"
        }
        $input[$k] = $pipeline_state[$k]
    }

    $result = & $fn -PipelineState $pipeline_state -InputData $input

    if ($result.status -ne "OK") {
        throw "Module failed: $($m.module_id)"
    }

    $pipeline_state[$m.writes_state_paths[0]] = $result.data
}

$pipeline_state.run.execution_status = "SUCCESS"

$pipeline_state | ConvertTo-Json -Depth 10
