<#
.SYNOPSIS
    Pester 5 tests: Lab 4.4's Deploy-Bicep.ps1 hands the template the right principal for the
    Storage Blob Data Contributor assignment of guide Step 4.4.7.

.DESCRIPTION
    Since issue #361 the Bicep path assigns Storage Blob Data Contributor on the storage account,
    as the guide's Step 4.4.7 does in the Portal, so all three paths end in the state Test-Lab.ps1
    checks. Deploy-Bicep.ps1 reads the signed-in identity's object id from the oid claim of its
    Azure Resource Manager token (no Microsoft Graph call), and passes nothing when that identity
    holds the role on the account already: ARM refuses a second assignment of the same role to the
    same principal at the same scope under another name (RoleAssignmentExists), which is the state
    a learner who did Step 4.4.7 in the Portal and then runs the Bicep is in.

    The script is never run here - its deployment cmdlets are aliases a function stub cannot
    shadow. The two functions are taken from the script's syntax tree and run against stubs of
    the Az commands they call, and the parameter that carries the principal is checked by name in
    the script and in bicep/main.bicep.

.EXAMPLE
    Invoke-Pester -Path .\Deploy-Bicep.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 4.4 - Storage Security
    Issue: #361
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Deploy-Bicep.ps1')).Path
    $script:BicepPath  = (Resolve-Path (Join-Path $PSScriptRoot '..' 'bicep' 'main.bicep')).Path
    $script:Ast        = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)

    # Stubs of the Az commands the two functions call, so Mock has something to replace on a
    # machine without Az (the CI runner).
    function Get-AzAccessToken { param([string]$ResourceUrl, [string]$ResourceTypeName) $null = $ResourceUrl; $null = $ResourceTypeName }
    function Get-LabArmRoleAssignment { param([string]$Scope, [string]$PrincipalId) $null = $Scope, $PrincipalId }
    function Get-AzStorageBlobServiceProperty { param([string]$ResourceGroupName, [string]$StorageAccountName) $null = $ResourceGroupName, $StorageAccountName }

    # The script's own $dataRoleName and its functions, as the script defines them.
    $roleAssignment = $script:Ast.Find({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$dataRoleName' }, $true)
    . ([scriptblock]::Create($roleAssignment.Extent.Text))
    $daysAssignment = $script:Ast.Find({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$blobSoftDeleteDays' }, $true)
    $daysAssignment | Should -Not -BeNullOrEmpty -Because 'Deploy-Bicep.ps1 keeps the soft delete days in $blobSoftDeleteDays'
    . ([scriptblock]::Create($daysAssignment.Extent.Text))
    foreach ($name in 'Get-LabSignedInObjectId', 'Test-LabDataRoleAssigned', 'Resolve-LabDataPrincipalId', 'Test-LabBlobRestoreConflict') {
        $definition = $script:Ast.Find({ param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        $definition | Should -Not -BeNullOrEmpty -Because "Deploy-Bicep.ps1 defines $name"
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    # A JWT shaped like an ARM token: base64url header and payload, no padding, a dummy signature.
    function Get-TestJwt {
        param([hashtable]$Claims)
        $encode = { param($text) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
        "$(& $encode '{"alg":"RS256","typ":"JWT"}').$(& $encode ($Claims | ConvertTo-Json -Compress)).signature"
    }

    $script:Oid   = '11111111-2222-3333-4444-555555555555'
    $script:Scope = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa'
}

Describe 'Lab 4.4 Deploy-Bicep.ps1 - the signed-in object id comes from the ARM token' {

    It 'reads the oid claim of a token given as a string, for any payload length (<note>)' -ForEach @(
        @{ note = 'user'; claims = @{ oid = '11111111-2222-3333-4444-555555555555'; idtyp = 'user'; name = 'Learner' } }
        @{ note = 'app'; claims = @{ oid = '11111111-2222-3333-4444-555555555555'; idtyp = 'app' } }
        @{ note = 'padding'; claims = @{ oid = '11111111-2222-3333-4444-555555555555'; x = 'ab' } }
        @{ note = 'more padding'; claims = @{ oid = '11111111-2222-3333-4444-555555555555'; x = 'abc' } }
    ) {
        $jwt = Get-TestJwt -Claims $claims
        Mock Get-AzAccessToken { [pscustomobject]@{ Token = $jwt } }
        Get-LabSignedInObjectId | Should -Be $script:Oid
        Should -Invoke Get-AzAccessToken -Times 1 -ParameterFilter { $ResourceTypeName -eq 'Arm' -and -not $ResourceUrl }
    }

    It 'reads the oid claim of a token given as a SecureString (Az.Accounts 5 and later)' {
        $jwt = Get-TestJwt -Claims @{ oid = $script:Oid }
        # Built one character at a time: the token is a test value, and SecureString has no plain-text constructor.
        $secure = [securestring]::new()
        foreach ($character in $jwt.ToCharArray()) { $secure.AppendChar($character) }
        Mock Get-AzAccessToken { [pscustomobject]@{ Token = $secure } }
        Get-LabSignedInObjectId | Should -Be $script:Oid
    }

    It 'answers empty, not an error, when <case>' -ForEach @(
        @{ case = 'no token can be had'; token = $null; throws = $true }
        @{ case = 'the token is not a JWT'; token = 'opaque-token'; throws = $false }
        @{ case = 'the payload is not base64'; token = 'a.!!!.b'; throws = $false }
    ) {
        if ($throws) { Mock Get-AzAccessToken { throw 'stub: no token' } }
        else { Mock Get-AzAccessToken { [pscustomobject]@{ Token = $token } } }
        Get-LabSignedInObjectId | Should -BeExactly ''
    }
}

Describe 'Lab 4.4 Deploy-Bicep.ps1 - an assignment that exists already is not sent again' {

    It 'finds the role assigned to the principal on the account itself' {
        Mock Get-LabArmRoleAssignment {
            [pscustomobject]@{ ObjectId = $script:Oid; RoleDefinitionName = 'Owner'; Scope = '/subscriptions/00000000-0000-0000-0000-000000000000' }
            [pscustomobject]@{ ObjectId = $script:Oid; RoleDefinitionName = 'Storage Blob Data Contributor'; Scope = $script:Scope }
        }
        Test-LabDataRoleAssigned -Scope $script:Scope -PrincipalId $script:Oid | Should -BeTrue
    }

    It 'does not count <case>' -ForEach @(
        @{ case = 'the role inherited from the resource group'; objectId = '11111111-2222-3333-4444-555555555555'; role = 'Storage Blob Data Contributor'; assignedScope = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg' }
        @{ case = 'the role held by another principal'; objectId = '99999999-2222-3333-4444-555555555555'; role = 'Storage Blob Data Contributor'; assignedScope = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa' }
        @{ case = 'another role on the account'; objectId = '11111111-2222-3333-4444-555555555555'; role = 'Storage Blob Data Reader'; assignedScope = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa' }
    ) {
        Mock Get-LabArmRoleAssignment { [pscustomobject]@{ ObjectId = $objectId; RoleDefinitionName = $role; Scope = $assignedScope } }
        Test-LabDataRoleAssigned -Scope $script:Scope -PrincipalId $script:Oid | Should -BeFalse
    }

    It 'answers no, with a warning, when the lookup fails, so the deployment tries the assignment' {
        Mock Get-LabArmRoleAssignment { throw 'stub: lookup failed' }
        Mock Write-Host { }
        Test-LabDataRoleAssigned -Scope $script:Scope -PrincipalId $script:Oid | Should -BeFalse
        Should -Invoke Write-Host -ParameterFilter { "$Object" -match '\[WARNING\] Could not read the role assignments' }
    }
}

Describe 'Lab 4.4 Deploy-Bicep.ps1 - which principal the template is given' {

    BeforeEach {
        Mock Write-Host { }
    }

    It 'gives none, and reads nothing, with -SkipDataRoleAssignment (an identity with Contributor only)' {
        Mock Get-AzAccessToken { throw 'stub: must not be called' }
        Mock Get-LabArmRoleAssignment { throw 'stub: must not be called' }
        Resolve-LabDataPrincipalId -Scope $script:Scope -Skip | Should -BeExactly ''
        Resolve-LabDataPrincipalId -Scope $script:Scope -PrincipalId $script:Oid -Skip | Should -BeExactly ''
        Should -Invoke Get-AzAccessToken -Times 0
        Should -Invoke Get-LabArmRoleAssignment -Times 0
        Should -Invoke Write-Host -ParameterFilter { "$Object" -match '-SkipDataRoleAssignment: the template assigns no role' }
    }

    It 'gives the signed-in identity when it does not hold the role, and says what that needs' {
        $jwt = Get-TestJwt -Claims @{ oid = $script:Oid }
        Mock Get-AzAccessToken { [pscustomobject]@{ Token = $jwt } }
        Mock Get-LabArmRoleAssignment { }
        Resolve-LabDataPrincipalId -Scope $script:Scope | Should -BeExactly $script:Oid
        Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'Owner or User Access Administrator' }
    }

    It 'gives none when the identity holds the role on the account already' {
        Mock Get-LabArmRoleAssignment { [pscustomobject]@{ ObjectId = $script:Oid; RoleDefinitionName = 'Storage Blob Data Contributor'; Scope = $script:Scope } }
        Resolve-LabDataPrincipalId -Scope $script:Scope -PrincipalId $script:Oid | Should -BeExactly ''
    }

    It 'gives none when the signed-in identity cannot be read' {
        Mock Get-AzAccessToken { throw 'stub: no token' }
        Resolve-LabDataPrincipalId -Scope $script:Scope | Should -BeExactly ''
    }

    It 'declares -SkipDataRoleAssignment and passes it on' {
        $scriptText = Get-Content -Raw -LiteralPath $script:ScriptPath
        $scriptText | Should -Match '\[switch\]\$SkipDataRoleAssignment'
        $scriptText | Should -Match 'Resolve-LabDataPrincipalId -Scope \$accountScope -PrincipalId \$DataPrincipalId -Skip:\$SkipDataRoleAssignment'
    }
}

Describe 'Lab 4.4 Deploy-Bicep.ps1 - the principal reaches the template' {

    It 'passes parDataContributorPrincipalId, which main.bicep declares and feeds to roleAssignments' {
        $scriptText = Get-Content -Raw -LiteralPath $script:ScriptPath
        $bicepText  = Get-Content -Raw -LiteralPath $script:BicepPath
        $scriptText | Should -Match 'parDataContributorPrincipalId\s*=\s*\$assignPrincipalId'
        $bicepText  | Should -Match "param parDataContributorPrincipalId string = ''"
        $bicepText  | Should -Match "roleAssignments: empty\(parDataContributorPrincipalId\) \? \[\] :"
        $bicepText  | Should -Match "roleDefinitionIdOrName: 'Storage Blob Data Contributor'"
    }
}

Describe 'Lab 4.4 Deploy-Bicep.ps1 - Lab 5.2 point-in-time restore against the template soft delete days' {

    BeforeEach {
        Mock Write-Host { }
    }

    It 'keeps the soft delete days equal to the default of parBlobSoftDeleteDays in main.bicep' {
        $bicepText = Get-Content -Raw -LiteralPath $script:BicepPath
        $bicepText -match 'param parBlobSoftDeleteDays int = (\d+)' | Should -BeTrue
        $blobSoftDeleteDays | Should -Be ([int]$Matches[1])
    }

    It 'passes the days variable to the template as parBlobSoftDeleteDays' {
        (Get-Content -Raw -LiteralPath $script:ScriptPath) | Should -Match 'parBlobSoftDeleteDays\s*=\s*\$blobSoftDeleteDays'
    }

    It 'stops before the deployment: the guard runs before New-AzSubscriptionDeployment and exits through Exit-Lab' {
        $scriptText = Get-Content -Raw -LiteralPath $script:ScriptPath
        $guard = [regex]::Match($scriptText, '(?s)if \(Test-LabBlobRestoreConflict [^
]*\{\s*Exit-Lab -FailureCount 1\s*\}')
        $guard.Success | Should -BeTrue
        $guard.Index | Should -BeLessThan $scriptText.IndexOf('New-AzSubscriptionDeployment @deployParams')
        $guard.Index | Should -BeLessThan $scriptText.IndexOf('Get-AzSubscriptionDeploymentWhatIfResult @deployParams')
    }

    It 'answers stop with an [ERROR] naming the setting, both day counts and Lab 5.2 when restore is on with more days' {
        Mock Get-AzStorageBlobServiceProperty { [pscustomobject]@{ RestorePolicy = [pscustomobject]@{ Enabled = $true; Days = 30 } } }
        Test-LabBlobRestoreConflict -ResourceGroupName 'prod-skycraft-swc-rg' -StorageAccountName 'prodskycraftswcsa' -SoftDeleteDays $blobSoftDeleteDays | Should -BeTrue
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            "$Object" -match '\[ERROR\]' -and "$Object" -match 'Blob soft delete retention' -and
            "$Object" -match "\($blobSoftDeleteDays days\)" -and "$Object" -match '\(30 days\)' -and "$Object" -match "Lab 5\.2's blob backup" }
    }

    It 'warns with the same text and answers go on under -WhatIf' {
        Mock Get-AzStorageBlobServiceProperty { [pscustomobject]@{ RestorePolicy = [pscustomobject]@{ Enabled = $true; Days = 30 } } }
        Test-LabBlobRestoreConflict -ResourceGroupName 'prod-skycraft-swc-rg' -StorageAccountName 'prodskycraftswcsa' -SoftDeleteDays $blobSoftDeleteDays -WhatIfMode | Should -BeFalse
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            "$Object" -match '\[WARNING\]' -and "$Object" -notmatch '\[ERROR\]' -and "$Object" -match 'Blob soft delete retention' -and
            "$Object" -match "\($blobSoftDeleteDays days\)" -and "$Object" -match '\(30 days\)' -and "$Object" -match "Lab 5\.2's blob backup" }
    }

    It 'prints nothing and goes on when <case>' -ForEach @(
        @{ case = 'restore is off'; restore = @{ Enabled = $false; Days = 30 } }
        @{ case = 'there is no restore policy'; restore = $null }
        @{ case = 'the restore days equal the soft delete days'; restore = @{ Enabled = $true; Days = 7 } }
        @{ case = 'the restore days are below the soft delete days'; restore = @{ Enabled = $true; Days = 3 } }
    ) {
        $policy = if ($restore) { [pscustomobject]$restore } else { $null }
        Mock Get-AzStorageBlobServiceProperty { [pscustomobject]@{ RestorePolicy = $policy } }
        Test-LabBlobRestoreConflict -ResourceGroupName 'prod-skycraft-swc-rg' -StorageAccountName 'prodskycraftswcsa' -SoftDeleteDays $blobSoftDeleteDays | Should -BeFalse
        Should -Invoke Write-Host -Times 0
    }

    It 'prints nothing, and does not look up the account, when it does not exist yet' {
        Mock Get-AzStorageBlobServiceProperty { throw 'stub: must not be called' }
        Test-LabBlobRestoreConflict -ResourceGroupName 'prod-skycraft-swc-rg' -StorageAccountName 'prodskycraftswcsa' -SoftDeleteDays $blobSoftDeleteDays -AccountExists $false | Should -BeFalse
        Should -Invoke Get-AzStorageBlobServiceProperty -Times 0
        Should -Invoke Write-Host -Times 0
    }

    It 'warns with the error text and goes on when the lookup throws' {
        Mock Get-AzStorageBlobServiceProperty { throw 'stub: lookup failed' }
        Test-LabBlobRestoreConflict -ResourceGroupName 'prod-skycraft-swc-rg' -StorageAccountName 'prodskycraftswcsa' -SoftDeleteDays $blobSoftDeleteDays | Should -BeFalse
        Should -Invoke Write-Host -ParameterFilter { "$Object" -match '\[WARNING\]' -and "$Object" -match 'stub: lookup failed' }
        Should -Invoke Write-Host -Times 0 -ParameterFilter { "$Object" -match '\[ERROR\]' }
    }
}
