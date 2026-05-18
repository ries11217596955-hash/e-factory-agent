param(
    [Parameter(Mandatory)][string]$RequestPath,
    [string]$RegistryPath = "agents/site_auditor_v3/contracts/module_registry.json"
)

$ErrorActionPreference = "Stop"

function Read-Json($p) {
    Get-Content $p -Raw | ConvertFrom-Json -AsHashtable
}

$runId = [string](Get-Date -Format "yyyyMMdd_HHmmss")
$registry = Read-Json $RegistryPath
$request  = Read-Json $RequestPath

$pipeline_state = @{
    run = @{
        run_id = $runId
        execution_status = "RUNNING"
        failed_module = $null
    }
    request = $request
}

$outputModule = ($registry.modules | Where-Object { $_.module_id -eq "07_output" } | Select-Object -First 1)

foreach ($m in ($registry.modules | Sort-Object ordinal)) {
    if (-not $m.enabled) { continue }
    if ($m.module_id -eq "07_output") { continue }

    . $m.file_path
    $fn = Get-Command $m.entry_function -ErrorAction Stop

    $input = @{}
    foreach ($k in $m.reads_state_paths) {
        if (-not $pipeline_state.ContainsKey($k)) {
            $pipeline_state.run.execution_status = "FAIL"
            $pipeline_state.run.failed_module = $m.module_id
            break
        }
        $input[$k] = $pipeline_state[$k]
    }

    if ($pipeline_state.run.execution_status -eq "FAIL") { break }

    $result = & $fn -PipelineState $pipeline_state -InputData $input
    $pipeline_state[$m.writes_state_paths[0]] = $result.data

    if ($result.status -ne "OK") {
        $pipeline_state.run.execution_status = "FAIL"
        $pipeline_state.run.failed_module = $m.module_id
        break
    }
}

if ($pipeline_state.run.execution_status -eq "RUNNING") {
    $pipeline_state.run.execution_status = "SUCCESS"
}

if ($null -ne $outputModule -and $outputModule.enabled) {
    . $outputModule.file_path
    $outFn = Get-Command $outputModule.entry_function -ErrorAction Stop

    $outResult = & $outFn -PipelineState $pipeline_state -InputData @{}
    $pipeline_state[$outputModule.writes_state_paths[0]] = $outResult.data

    if ($outResult -and $outResult.data -and $outResult.data.run_report) {
        $runReportPath = [string]$outResult.data.run_report
        $finalizerPath = "agents/site_auditor_v3/tools/finalize_session.ps1"
        if (Test-Path -LiteralPath $finalizerPath) {
            & $finalizerPath -RunReportPath $runReportPath
        }

        $repairExecutionPath = "agents/site_auditor_v3/tools/prepare_repair_execution.ps1"
        if (Test-Path -LiteralPath $repairExecutionPath) {
            & $repairExecutionPath -RunReportPath $runReportPath
        }
    }
}

$pipeline_state | ConvertTo-Json -Depth 20
