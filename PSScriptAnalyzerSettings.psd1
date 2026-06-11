@{
    # SkyCraft PSScriptAnalyzer configuration.
    # Usage: Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
    # See docs/powershell-standards.md (Section 6) for the policy behind this file.

    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # Conscious divergence 7.1: color-coded Write-Host is the lab-script UX standard.
        'PSAvoidUsingWriteHost'
    )

    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.0')
        }
        PSPlaceOpenBrace = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
    }
}
