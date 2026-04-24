Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ContractFieldValue {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) { return $null }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }

    return $null
}

function Get-ContractNonEmptyString {
    param([Parameter(Mandatory = $false)][object]$Value)

    if ($null -eq $Value) { return $null }
    $stringValue = [string]$Value
    if ([string]::IsNullOrWhiteSpace($stringValue)) { return $null }
    return $stringValue.Trim()
}

function Convert-ContractArray {
    param([Parameter(Mandatory = $false)][object]$Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace([string]$Value)) { return @() }
        return @([string]$Value)
    }
    if ($Value -is [System.Array]) { return @($Value) }
    if ($Value -is [System.Collections.IEnumerable]) { return @($Value) }
    return @($Value)
}

function New-NormalizedFinding {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Finding,
        [Parameter(Mandatory = $true)]
        [int]$Index,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$MissingFields
    )

    if ($null -eq $MissingFields) {
        $MissingFields = New-Object System.Collections.Generic.List[string]
    }

    if ($null -eq $Finding) { $Finding = [ordered]@{} }

    $findingId = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'finding_id')
    if ($null -eq $findingId) {
        $findingId = 'finding_{0:d3}' -f ($Index + 1)
        $null = $MissingFields.Add('finding_id')
    }

    $issueType = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'issue_type')
    if ($null -eq $issueType) { $issueType = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'signal_type') }
    if ($null -eq $issueType) { $issueType = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'type') }
    if ($null -eq $issueType) {
        $issueType = 'UNSPECIFIED_FINDING'
        $null = $MissingFields.Add('issue_type')
    }

    $category = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'category')
    if ($null -eq $category) {
        $category = 'DEFECT'
        $null = $MissingFields.Add('category')
    }

    $priority = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'priority')
    if ($null -eq $priority) {
        $priority = if ($category -eq 'LIMITATION') { 'NONE' } else { 'P2' }
        $null = $MissingFields.Add('priority')
    }

    $severity = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'severity')
    if ($null -eq $severity) {
        $severity = $priority
        $null = $MissingFields.Add('severity')
    }

    $confidence = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'confidence')
    if ($null -eq $confidence) {
        $confidence = 'LOW'
        $null = $MissingFields.Add('confidence')
    }

    $route = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'route')
    if ($null -eq $route) { $route = '_unknown'; $null = $MissingFields.Add('route') }

    $surfaceType = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'surface_type')
    if ($null -eq $surfaceType) { $surfaceType = 'UNKNOWN'; $null = $MissingFields.Add('surface_type') }

    $evidenceText = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'evidence_text')
    if ($null -eq $evidenceText) {
        $evidenceText = 'No evidence text provided.'
        $null = $MissingFields.Add('evidence_text')
    }

    $whyItMatters = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'why_it_matters')
    if ($null -eq $whyItMatters) {
        $whyItMatters = $evidenceText
        $null = $MissingFields.Add('why_it_matters')
    }

    $recommendedAction = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'recommended_action')
    if ($null -eq $recommendedAction) {
        $recommendedAction = if ($category -eq 'LIMITATION') { 'Expand route sample and rerun LINK mode for broader coverage.' } else { 'Review this finding and define the next bounded repair action.' }
        $null = $MissingFields.Add('recommended_action')
    }

    $title = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'title')
    if ($null -eq $title) { $title = $issueType; $null = $MissingFields.Add('title') }

    $description = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'description')
    if ($null -eq $description) { $description = $whyItMatters; $null = $MissingFields.Add('description') }

    $evidenceRefsSource = Get-ContractFieldValue -Object $Finding -Name 'evidence_refs'
    if ($null -eq $evidenceRefsSource) { $evidenceRefsSource = Get-ContractFieldValue -Object $Finding -Name 'evidence_ref' }
    $evidenceRefs = @(Convert-ContractArray -Value $evidenceRefsSource)
    if ($evidenceRefs.Count -eq 0) {
        $evidenceRefs = @('RUN_REPORT.json')
        $null = $MissingFields.Add('evidence.evidence_refs')
    }

    $evidenceType = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'evidence_type')
    if ($null -eq $evidenceType) { $evidenceType = 'status' }

    $evidenceScreenshot = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $Finding -Name 'evidence_screenshot')
    if ($null -eq $evidenceScreenshot) { $evidenceScreenshot = '' }

    return [ordered]@{
        finding_id = [string]$findingId
        route = [string]$route
        signal_type = [string]$issueType
        type = [string]$issueType
        issue_type = [string]$issueType
        category = [string]$category
        priority = [string]$priority
        severity = [string]$severity
        confidence = [string]$confidence
        surface_type = [string]$surfaceType
        title = [string]$title
        description = [string]$description
        evidence_text = [string]$evidenceText
        evidence_type = [string]$evidenceType
        evidence_ref = if ($evidenceRefs.Count -gt 0) { [string]$evidenceRefs[0] } else { 'RUN_REPORT.json' }
        evidence_refs = @($evidenceRefs)
        evidence_screenshot = [string]$evidenceScreenshot
        evidence = [ordered]@{ evidence_refs = @($evidenceRefs) }
        why_it_matters = [string]$whyItMatters
        recommended_action = [string]$recommendedAction
    }
}

function Normalize-FindingContract {
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$Findings,
        [Parameter(Mandatory = $true)]
        [string]$DiagnosticPath
    )

    $inputFindings = @($Findings)
    $missingFieldsByFinding = New-Object System.Collections.Generic.List[object]
    $normalizedFindings = New-Object System.Collections.Generic.List[object]
    $normalizedFieldsCount = 0

    for ($index = 0; $index -lt $inputFindings.Count; $index++) {
        $missing = New-Object System.Collections.Generic.List[string]
        $normalized = New-NormalizedFinding -Finding $inputFindings[$index] -Index $index -MissingFields $missing
        if ($missing.Count -gt 0) {
            $normalizedFieldsCount += [int]$missing.Count
            $null = $missingFieldsByFinding.Add([ordered]@{
                    finding_id = [string]$normalized.finding_id
                    missing_fields = @($missing.ToArray())
                })
        }
        $null = $normalizedFindings.Add($normalized)
    }

    $diagnostic = [ordered]@{
        total_findings = [int]$inputFindings.Count
        missing_fields_by_finding = @($missingFieldsByFinding.ToArray())
        normalized_fields_count = [int]$normalizedFieldsCount
    }

    $diagnosticJson = $diagnostic | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($DiagnosticPath, $diagnosticJson + [Environment]::NewLine, (New-SafeUtf8NoBom))

    return [ordered]@{
        findings = @($normalizedFindings.ToArray())
        diagnostic = $diagnostic
    }
}
