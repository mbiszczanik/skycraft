<#
.SYNOPSIS
    Pester 5 tests for New-LabUser.ps1 password handling.

.DESCRIPTION
    Verifies three things:
      1. Regression: the historical hard-coded password is no longer in the file.
      2. Parameter shape: the script exposes -InitialPassword as [SecureString].
      3. Password generator: New-LabRandomPassword yields a 20-character string
         containing at least one upper, lower, digit, and symbol.

.EXAMPLE
    Invoke-Pester -Path .\New-LabUser.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\scripts\New-LabUser.ps1' | Resolve-Path
    $script:ScriptText = Get-Content -Raw -LiteralPath $script:ScriptPath

    $errs   = $null
    $tokens = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:ScriptPath, [ref]$tokens, [ref]$errs
    )
    if ($errs.Count -gt 0) {
        throw "Parse errors in New-LabUser.ps1: $($errs.Message -join '; ')"
    }
}

Describe 'New-LabUser.ps1 — hard-coded password regression' {
    It 'does not contain the legacy shared password literal' {
        $script:ScriptText | Should -Not -Match 'LoveAzeroth!2004'
    }

    It 'does not contain any `Password = "..."` literal assignment' {
        $script:ScriptText | Should -Not -Match 'Password\s*=\s*"[^"$]+"'
    }
}

Describe 'New-LabUser.ps1 — parameter contract' {
    BeforeAll {
        $paramAst = $script:Ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.ParameterAst] -and
            $node.Name.VariablePath.UserPath -eq 'InitialPassword'
        }, $true)
        $script:InitialPasswordParam = $paramAst
    }

    It 'exposes an -InitialPassword parameter' {
        $script:InitialPasswordParam | Should -Not -BeNullOrEmpty
    }

    It 'types -InitialPassword as [SecureString]' {
        $script:InitialPasswordParam.StaticType.FullName | Should -Be 'System.Security.SecureString'
    }
}

Describe 'New-LabUser.ps1 — random password generator' {
    BeforeAll {
        $funcAst = $script:Ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'New-LabRandomPassword'
        }, $true)
        if (-not $funcAst) { throw 'New-LabRandomPassword not found.' }
        Invoke-Expression $funcAst.Extent.Text
    }

    It 'produces a 20-character password' {
        $pwd = New-LabRandomPassword
        $pwd.Length | Should -Be 20
    }

    It 'produces passwords with all four character classes' {
        1..20 | ForEach-Object {
            $pwd = New-LabRandomPassword
            $pwd | Should -Match '[A-Z]'
            $pwd | Should -Match '[a-z]'
            $pwd | Should -Match '[0-9]'
            $pwd | Should -Match '[!@#\$%\^&\*\(\)\-_=\+\[\]\{\}]'
        }
    }

    It 'produces distinct passwords across 10 invocations' {
        $results = 1..10 | ForEach-Object { New-LabRandomPassword }
        ($results | Sort-Object -Unique).Count | Should -Be 10
    }
}
