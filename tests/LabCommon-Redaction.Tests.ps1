<#
.SYNOPSIS
    Pester 5 tests: lab script output carries no subscription id and no signed-in user from
    Azure's authorization text (#393).

.DESCRIPTION
    Azure's error text names the signed-in user, their object id and the scope, and resource ids
    carry the subscription id. tools/LabCommon.psm1 shadows Write-Host: the subscription id becomes
    <id> in every line, and the sign-in name and object id in "The client '...' with object id
    '...'" become <user> and <id>. Other ids and names stay, because some scripts print a lab
    user's name or a tenant id on purpose. The shadow acts only for a call from a lab script (module-*/*/scripts) or from tools/,
    because the module stays imported in the learner's session after a script ends.

    The cases run the real module in a child process, with a probe script placed under a
    module-*/*/scripts path, and one call from outside such a path.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCommon-Redaction.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #393
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:Module = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'LabCommon.psm1')).Path
    Import-Module $script:Module -Force -Verbose:$false

    # A probe script under a lab scripts folder, and one outside, each run in a child process.
    $script:LabDir = Join-Path $TestDrive 'module-9-probe' '9.9-probe' 'scripts'
    New-Item -ItemType Directory -Path $script:LabDir -Force | Out-Null
    $script:Outside = Join-Path $TestDrive 'elsewhere'
    New-Item -ItemType Directory -Path $script:Outside -Force | Out-Null

    $importLine = "Import-Module '$($script:Module)' -Force -Verbose:`$false"
    $body = @'
Write-Host "Connected to Subscription: Azure subscription 1 (11111111-2222-3333-4444-555555555555)"
Write-Host "  [ERROR] The client 'malfurion.stormrage@contoso.onmicrosoft.com' with object id '66666666-7777-8888-9999-000000000000' does not have authorization over scope '/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/dev-rg'." -ForegroundColor Red
Write-Host "Created user malfurion.stormrage@contoso.onmicrosoft.com"
Write-Host "[FAIL] User missing: khadgar.archmage@contoso.onmicrosoft.com"
Write-Host "  [ERROR] Graph is signed in to tenant 99999999-8888-7777-6666-555555555555, not the Az tenant" -ForegroundColor Red
Write-Host 'one', 'two', 'three' -Separator '-'
Write-Host 'no newline' -NoNewline
Write-Host ' continued'
Write-Host
function Show-Inner { Write-Host 'inner /subscriptions/11111111-2222-3333-4444-555555555555/x' }
Show-Inner
'@
    Set-Content -LiteralPath (Join-Path $script:LabDir 'Probe.ps1') -Value ($importLine + "`n" + $body) -Encoding utf8
    Set-Content -LiteralPath (Join-Path $script:Outside 'Probe.ps1') -Value ($importLine + "`n" + $body) -Encoding utf8

    $script:InLab = (& pwsh -NoProfile -File (Join-Path $script:LabDir 'Probe.ps1') 2>&1 | Out-String)
    $script:NotInLab = (& pwsh -NoProfile -File (Join-Path $script:Outside 'Probe.ps1') 2>&1 | Out-String)
}

Describe 'Protect-LabText (#393)' {

    It 'replaces a GUID with <id>' {
        Protect-LabText -Text 'scope /subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/x' | Should -Be 'scope /subscriptions/<id>/resourceGroups/x'
    }

    It 'replaces a subscription id in upper case' {
        Protect-LabText -Text '/SUBSCRIPTIONS/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/resourceGroups/x' | Should -Be '/SUBSCRIPTIONS/<id>/resourceGroups/x'
    }

    It 'replaces the subscription id of a "Subscription: name (id)" line' {
        Protect-LabText -Text 'Connected to Subscription: Azure subscription 1 (11111111-2222-3333-4444-555555555555)' |
            Should -Be 'Connected to Subscription: Azure subscription 1 (<id>)'
    }

    It 'keeps a tenant id, which some errors name on purpose so the learner can tell the tenants apart' {
        $line = '[ERROR] Graph is signed in to tenant 11111111-2222-3333-4444-555555555555, but Az names tenant 66666666-7777-8888-9999-000000000000'
        Protect-LabText -Text $line | Should -Be $line
    }

    It 'keeps a GUID that is neither a subscription id nor an object id' {
        Protect-LabText -Text 'matched 2 principals (11111111-2222-3333-4444-555555555555, 66666666-7777-8888-9999-000000000000)' |
            Should -Be 'matched 2 principals (11111111-2222-3333-4444-555555555555, 66666666-7777-8888-9999-000000000000)'
    }

    It 'replaces the sign-in name and the object id in Azure''s authorization text' {
        Protect-LabText -Text "[ERROR] The client 'guest_other.com#EXT#@tenant.onmicrosoft.com' with object id '66666666-7777-8888-9999-000000000000' does not have authorization" |
            Should -Be "[ERROR] The client '<user>' with object id '<id>' does not have authorization"
    }

    It 'keeps a lab user''s name in an error line, which the learner needs to see which user is missing' {
        $line = '[FAIL] User missing: khadgar.archmage@contoso.onmicrosoft.com'
        Protect-LabText -Text $line | Should -Be $line
    }

    It 'keeps an e-mail address in a normal line' {
        Protect-LabText -Text 'Created user malfurion.stormrage@contoso.onmicrosoft.com' | Should -Be 'Created user malfurion.stormrage@contoso.onmicrosoft.com'
    }

    It 'leaves text without a GUID or an e-mail address unchanged' {
        Protect-LabText -Text 'Resource group dev-skycraft-swc-rg created' | Should -Be 'Resource group dev-skycraft-swc-rg created'
    }

    It 'returns an empty string and null as they are' {
        Protect-LabText -Text '' | Should -Be ''
        Protect-LabText -Text $null | Should -BeNullOrEmpty
    }
}

Describe 'Write-Host in a lab script (#393)' {

    It 'replaces the subscription id in a normal line' {
        $script:InLab | Should -Match 'Connected to Subscription: Azure subscription 1 \(<id>\)'
        $script:InLab | Should -Not -Match '11111111-2222-3333-4444-555555555555'
    }

    It 'replaces the sign-in name and both ids in an error line, and keeps the rest' {
        $script:InLab | Should -Match "\[ERROR\] The client '<user>' with object id '<id>' does not have authorization over scope '/subscriptions/<id>/resourceGroups/dev-rg'"
        $script:InLab | Should -Not -Match 'malfurion.stormrage@contoso.onmicrosoft.com\x27 with'
    }

    It 'keeps a lab user''s name, in a normal line and in an error line' {
        $script:InLab | Should -Match 'Created user malfurion.stormrage@contoso.onmicrosoft.com'
        $script:InLab | Should -Match '\[FAIL\] User missing: khadgar.archmage@contoso.onmicrosoft.com'
    }

    It 'keeps a tenant id that an error names on purpose' {
        $script:InLab | Should -Match 'tenant 99999999-8888-7777-6666-555555555555'
    }

    It 'keeps -Separator and -NoNewline' {
        $script:InLab | Should -Match 'one-two-three'
        $script:InLab | Should -Match 'no newline continued'
    }

    It 'redacts a call made from a function of the script' {
        $script:InLab | Should -Match 'inner /subscriptions/<id>/x'
    }
}

Describe 'Write-Host outside a lab script (#393)' {

    It 'passes the learner''s own output through unchanged, though the module is imported' {
        $script:NotInLab | Should -Match 'Connected to Subscription: Azure subscription 1 \(11111111-2222-3333-4444-555555555555\)'
        $script:NotInLab | Should -Match 'malfurion.stormrage@contoso.onmicrosoft.com'
        $script:NotInLab | Should -Not -Match '<id>'
        $script:NotInLab | Should -Not -Match '<user>'
    }
}
