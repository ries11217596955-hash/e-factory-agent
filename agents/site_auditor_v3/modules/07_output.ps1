function Invoke-Module07Output {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $run        = $PipelineState.run
    $request    = $PipelineState.request
    $input      = $PipelineState.input
    $routeAudit = $PipelineState.route_audit
    $selection  = $PipelineState.selection
    $capture    = $PipelineState.capture
    $reconcile  = $PipelineState.reconcile
    $decision   = $PipelineState.decision

    return @{
        status = "OK"
        data = @{
            run = $run

            request = $request

            input = $input

            route_audit = $routeAudit

            selection = $selection

            capture = $capture

            reconcile = $reconcile

            decision = $decision
        }
    }
}
