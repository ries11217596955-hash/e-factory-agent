function Resolve-SurfaceType {
    param([string]$SurfaceType)

    $normalized = if ($null -eq $SurfaceType) { '' } else { [string]$SurfaceType }
    $normalized = $normalized.Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return 'UNKNOWN'
    }

    if (@('MEDIA_HOME', 'MEDIA_SECTION', 'ARTICLE', 'LANDING', 'DECISION', 'TOOL', 'DIRECTORY', 'UNKNOWN') -contains $normalized) {
        return $normalized
    }

    return 'UNKNOWN'
}

function Get-NormalizedSurfaceType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RouteKey,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [int]$InternalLinkCount,
        [Parameter(Mandatory = $true)]
        [int]$ContentTagCount,
        [Parameter(Mandatory = $true)]
        [int]$WrapperTagCount,
        [Parameter(Mandatory = $true)]
        [int]$HeadlineCount,
        [Parameter(Mandatory = $true)]
        [int]$ArticleListCount,
        [Parameter(Mandatory = $true)]
        [double]$RepeatedLinkBlockRatio,
        [Parameter(Mandatory = $true)]
        [bool]$HasTimestampPatterns
    )

    $routeLower = ([string]$RouteKey).ToLowerInvariant()
    $titleLower = ([string]$Title).ToLowerInvariant()
    $newsLikeDensity = ($HeadlineCount -ge 5) -or ($ArticleListCount -ge 2) -or $HasTimestampPatterns

    if ($routeLower -match '/(compare|vs|pricing|plans|choose|decision|selector|quiz)(/|$)' -or $titleLower -match '\b(compare|versus|pricing|plan|choose)\b') { return 'DECISION' }
    if ($routeLower -match '/(tool|tools|calculator|generator|checker|estimator)(/|$)' -or $titleLower -match '\b(tool|calculator|generator|checker|estimator)\b') { return 'TOOL' }
    if ($routeLower -match '/(directory|directories|catalog|listings|providers|companies|vendors)(/|$)' -or $titleLower -match '\b(directory|catalog|listing|providers|vendors)\b') { return 'DIRECTORY' }
    if ($routeLower -match '/(article|story|stories|post|news|blog|insights|press|updates)/' -or $titleLower -match '\b(article|story|news|blog|insight|opinion)\b') { return 'ARTICLE' }

    if ([string]::IsNullOrWhiteSpace($routeLower) -or $routeLower -eq '/') {
        if ($newsLikeDensity -or $RepeatedLinkBlockRatio -ge 0.35) { return 'MEDIA_HOME' }
        return 'LANDING'
    }

    if ($routeLower -match '/(news|blog|insights|stories|topics|section|sections|latest)(/|$)') {
        if ($newsLikeDensity -or $RepeatedLinkBlockRatio -ge 0.25) { return 'MEDIA_SECTION' }
        return 'LANDING'
    }

    if (($InternalLinkCount -ge 16 -and $RepeatedLinkBlockRatio -ge 0.3) -or ($ArticleListCount -ge 3)) {
        if ($newsLikeDensity) { return 'MEDIA_SECTION' }
        return 'DIRECTORY'
    }

    if ($ContentTagCount -ge 6 -and $InternalLinkCount -le 8 -and ($HeadlineCount -le 3)) { return 'ARTICLE' }
    if ($WrapperTagCount -gt $ContentTagCount -and $InternalLinkCount -ge 10) { return 'DIRECTORY' }
    if ($InternalLinkCount -le 5 -and $ContentTagCount -ge 4) { return 'LANDING' }

    return 'UNKNOWN'
}

function Get-SurfaceExpectation {
    param([string]$SurfaceType)

    $safeSurfaceType = Resolve-SurfaceType -SurfaceType $SurfaceType

    switch ($safeSurfaceType) {
        'MEDIA_HOME' {
            return [ordered]@{ expects_value_first = $false; expects_action_path = $false; allow_content_stream = $true; context_note_en = 'The checked pages behave primarily as a news/content stream.'; context_note_ru = 'Проверенные страницы ведут себя преимущественно как поток новостей/контента.' }
        }
        'MEDIA_SECTION' {
            return [ordered]@{ expects_value_first = $false; expects_action_path = $false; allow_content_stream = $true; context_note_en = 'This surface type is expected to prioritize content listing over direct conversion action.'; context_note_ru = 'Для этого типа поверхности ожидаем приоритет списка контента, а не прямого конверсионного действия.' }
        }
        'ARTICLE' {
            return [ordered]@{ expects_value_first = $false; expects_action_path = $false; allow_content_stream = $false; context_note_en = 'Article surfaces may satisfy value through headline plus lead text without a primary CTA.'; context_note_ru = 'Страница-статья может раскрывать ценность через заголовок и лид без основного CTA.' }
        }
        'DIRECTORY' {
            return [ordered]@{ expects_value_first = $false; expects_action_path = $false; allow_content_stream = $false; context_note_en = 'Directory surfaces may satisfy value by presenting structured choices.'; context_note_ru = 'Поверхности-каталоги могут передавать ценность через структурированный выбор.' }
        }
        'DECISION' {
            return [ordered]@{ expects_value_first = $true; expects_action_path = $true; allow_content_stream = $false; context_note_en = 'Decision surfaces should clarify value and offer a clear next action.'; context_note_ru = 'Поверхности выбора должны объяснять ценность и давать явный следующий шаг.' }
        }
        'TOOL' {
            return [ordered]@{ expects_value_first = $true; expects_action_path = $true; allow_content_stream = $false; context_note_en = 'Tool surfaces should expose utility and a clear usage path on first screen.'; context_note_ru = 'Инструментальные поверхности должны показывать пользу и путь использования на первом экране.' }
        }
        'LANDING' {
            return [ordered]@{ expects_value_first = $true; expects_action_path = $true; allow_content_stream = $false; context_note_en = 'Landing surfaces are expected to frame value first and provide an action path.'; context_note_ru = 'Лендинг должен сначала формулировать ценность и давать путь к действию.' }
        }
        default {
            return [ordered]@{ expects_value_first = $false; expects_action_path = $false; allow_content_stream = $false; context_note_en = 'Surface type could not be normalized with high confidence.'; context_note_ru = 'Тип поверхности не удалось надёжно нормализовать.' }
        }
    }
}

function Test-SurfaceMediaListingSignals {
    param(
        [Parameter(Mandatory = $true)][int]$HeadlineCount,
        [Parameter(Mandatory = $true)][int]$ArticleListCount,
        [Parameter(Mandatory = $true)][bool]$HasTimestampPatterns,
        [Parameter(Mandatory = $true)][double]$RepeatedLinkBlockRatio
    )

    return (
        ($HeadlineCount -ge 5) -or
        ($ArticleListCount -ge 2) -or
        $HasTimestampPatterns -or
        ($RepeatedLinkBlockRatio -ge 0.25)
    )
}

function Test-SurfaceArticleValueSatisfied {
    param(
        [Parameter(Mandatory = $true)][int]$FirstScreenTextLength
    )

    return ($FirstScreenTextLength -ge 70)
}

function Test-SurfaceDirectoryValueSatisfied {
    param(
        [Parameter(Mandatory = $true)][int]$InternalLinkCount,
        [Parameter(Mandatory = $true)][double]$RepeatedLinkBlockRatio
    )

    return ($InternalLinkCount -ge 8 -or $RepeatedLinkBlockRatio -ge 0.2)
}
