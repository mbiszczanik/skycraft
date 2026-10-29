<#
.SYNOPSIS
    Pester 5 test: a resourceId() call in a subscription-scope template names the subscription.

.DESCRIPTION
    In a template with targetScope = 'subscription', resourceId(a, b, c) reads its first argument
    as a subscription id when it gets three arguments or more. resourceId(<resource group>, <type>,
    <name>) therefore fails the deployment with "'<group>' is not valid subscription identifier"
    (Lab 5.2, found live 2026-10-29). The three-argument form is valid only where the deployment
    scope is a resource group, that is in a module. This suite scans every *.bicep file under
    module-*/ that sets targetScope = 'subscription' and requires each resourceId() call to start
    with the subscription id, as Lab 2.1 does with subscription().subscriptionId.

    It is a text scan: comments are dropped, and the first argument is cut at the first comma
    outside parentheses. Path matching is separator-agnostic.

.EXAMPLE
    Invoke-Pester -Path .\tests\Bicep-ResourceId-Scope.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #366
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    # The first argument of every resourceId( call in $Text, with the call's line number.
    function Get-ResourceIdFirstArgument {
        param([string]$Text)
        foreach ($m in [regex]::Matches($Text, '\bresourceId\(')) {
            $depth = 0
            $first = [System.Text.StringBuilder]::new()
            for ($i = $m.Index + $m.Length; $i -lt $Text.Length; $i++) {
                $c = $Text[$i]
                if ($c -eq '(') { $depth++ }
                elseif ($c -eq ')') { if ($depth -eq 0) { break }; $depth-- }
                elseif ($c -eq ',' -and $depth -eq 0) { break }
                [void]$first.Append($c)
            }
            [pscustomobject]@{
                Line  = ($Text.Substring(0, $m.Index) -split "`n").Count
                First = ($first.ToString() -replace '\s+', ' ').Trim()
            }
        }
    }

    $script:SubscriptionTemplates = @(
        Get-ChildItem -Path $repoRoot -Recurse -File -Filter '*.bicep' |
            Where-Object { $_.FullName -match '[/\\]module-\d[^/\\]*[/\\]' } |
            ForEach-Object {
                $text = Get-Content -Raw -LiteralPath $_.FullName
                if ($text -notmatch "(?m)^\s*targetScope\s*=\s*'subscription'") { return }
                # Drop // comments and /* */ blocks so a mention in prose is not a call.
                $code = [regex]::Replace([regex]::Replace($text, '(?s)/\*.*?\*/', ''), '(?m)//.*$', '')
                @{
                    File  = ($_.FullName.Substring($repoRoot.Length + 1) -replace '\\', '/')
                    Calls = @(Get-ResourceIdFirstArgument -Text $code)
                }
            }
    )
}

Describe 'Subscription-scope Bicep - resourceId() names the subscription' {

    It 'finds the subscription-scope templates' {
        $SubscriptionTemplates.Count | Should -BeGreaterThan 10
    }

    It '<File> starts every resourceId() call with the subscription id' -ForEach $SubscriptionTemplates {
        $bad = @($Calls | Where-Object { $_.First -notmatch 'subscriptionId' } |
                ForEach-Object { "first argument '$($_.First)'" })
        $bad | Should -BeNullOrEmpty -Because "a subscription-scope resourceId() reads its first argument as the subscription id; use resourceId(subscription().subscriptionId, <group>, <type>, <name>)"
    }
}
