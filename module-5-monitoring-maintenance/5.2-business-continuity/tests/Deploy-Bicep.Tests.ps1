<#
.SYNOPSIS
    Pester 5 tests that Lab 5.2 - Business Continuity Deploy-Bicep.ps1 changes nothing under -WhatIf (#370).

.DESCRIPTION
    Every state-changing Az cmdlet call in the script must sit where -WhatIf cannot reach it:
    in the else of an if ($WhatIf), under -not $WhatIf, or after an if ($WhatIf) that leaves
    the loop or script. Those tests read the script with the PowerShell parser, not run it: the deployment
    cmdlets are aliases in Az.Resources, so a run whose guard regressed could reach Azure. The last
    Describe runs the script through tests/Support/LabScriptStub.psm1, which stubs every Az command
    it calls and refuses to run otherwise: step 7 waits for the vault to list a VM as a backup item,
    and a VM that never appears fails the run instead of skipping its backup.

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Deploy-Bicep.ps1')).Path
    $parseErrors = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { throw "$($script:ScriptPath) does not parse: $($parseErrors[0].Message)" }

    $script:IfAst = [System.Management.Automation.Language.IfStatementAst]
    $script:Mutating = '^(New|Set|Register|Update|Remove|Add|Install|Enable|Disable|Start|Stop|Invoke)-Az'

    function script:Test-WhatIfCondition {
        param($Condition)
        $Condition.Extent.Text -match '^\$WhatIf$'
    }

    function script:Test-NotReachableUnderWhatIf {
        param($Node)
        $child = $Node
        $parent = $Node.Parent
        while ($parent) {
            if ($parent -is $script:IfAst) {
                for ($i = 0; $i -lt $parent.Clauses.Count; $i++) {
                    $clause = $parent.Clauses[$i]
                    if (-not $clause.Item2.Extent.Text.Contains($child.Extent.Text)) { continue }
                    if ($clause.Item1.Extent.Text -match '-not\s+\$WhatIf') { return $true }
                    for ($j = 0; $j -lt $i; $j++) {
                        if (script:Test-WhatIfCondition $parent.Clauses[$j].Item1) { return $true }
                    }
                }
                if ($parent.ElseClause -and $parent.ElseClause.Extent.StartOffset -le $child.Extent.StartOffset -and
                    $child.Extent.EndOffset -le $parent.ElseClause.Extent.EndOffset -and
                    (script:Test-WhatIfCondition $parent.Clauses[0].Item1)) { return $true }
            }
            if ($parent -is [System.Management.Automation.Language.StatementBlockAst] -or
                $parent -is [System.Management.Automation.Language.NamedBlockAst]) {
                foreach ($stmt in $parent.Statements) {
                    if ($stmt.Extent.StartOffset -ge $child.Extent.StartOffset) { break }
                    if ($stmt -is $script:IfAst -and (script:Test-WhatIfCondition $stmt.Clauses[0].Item1) -and
                        $stmt.Clauses[0].Item2.Extent.Text -match '\b(continue|exit|return|Exit-Lab)\b') { return $true }
                }
            }
            $child = $parent
            $parent = $parent.Parent
        }
        $false
    }

    $script:Calls = @($script:Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match $script:Mutating
            }, $true))
}

Describe 'Lab 5.2 - Business Continuity Deploy-Bicep.ps1 under -WhatIf (#370)' {
    It 'declares the -WhatIf switch' {
        $script:Ast.ParamBlock.Parameters.Name.VariablePath.UserPath | Should -Contain 'WhatIf'
    }

    It 'finds the state-changing calls it is meant to guard' {
        $script:Calls.Count | Should -BeGreaterThan 0
    }

    It 'guards the resource provider registration' {
        $reg = @($script:Calls | Where-Object { $_.GetCommandName() -eq 'Register-AzResourceProvider' })
        $reg.Count | Should -BeGreaterThan 0
        foreach ($c in $reg) { script:Test-NotReachableUnderWhatIf $c | Should -BeTrue }
    }

    It 'keeps every state-changing call out of the -WhatIf path' {
        $exposed = @($script:Calls | Where-Object { -not (script:Test-NotReachableUnderWhatIf $_) } |
                ForEach-Object { "$($_.GetCommandName()) at line $($_.Extent.StartLineNumber)" })
        $exposed | Should -BeNullOrEmpty -Because 'these calls run under -WhatIf'
    }
}

Describe 'Lab 5.2 - Business Continuity Deploy-Bicep.ps1 step 7 cannot end the script silently (#366)' {
    BeforeAll {
        $script:TryAst = [System.Management.Automation.Language.TryStatementAst]
        $script:VmLoop = $script:Ast.Find({
                param($n)
                $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Variable.VariablePath.UserPath -eq 'vmName'
            }, $true)
    }

    It 'finds the loop over the VMs' {
        $script:VmLoop | Should -Not -BeNullOrEmpty
    }

    It 'runs the loop inside a try whose finally fails the run with Exit-Lab when the loop did not finish' {
        $try = $script:VmLoop.Parent
        while ($try -and $try -isnot $script:TryAst) { $try = $try.Parent }
        $try | Should -Not -BeNullOrEmpty -Because 'a stopped pipeline throws past every catch, so only a finally still runs'
        $try.Finally | Should -Not -BeNullOrEmpty
        $try.Finally.Extent.Text | Should -Match 'Exit-Lab\s+-FailureCount\s+1'
        $try.Finally.Extent.Text | Should -Match '-not\s+\$vmStepsDone'
    }

    It 'sets the finished flag after the loop, inside the try' {
        $try = $script:VmLoop.Parent
        while ($try -and $try -isnot $script:TryAst) { $try = $try.Parent }
        $last = $try.Body.Statements[-1]
        $last.Extent.Text | Should -Match '^\$vmStepsDone\s*=\s*\$true$'
        $last.Extent.StartOffset | Should -BeGreaterThan $script:VmLoop.Extent.EndOffset
    }

    It 'collects the Az pipelines before taking the first element' {
        $names = 'Get-AzResourceProvider', 'Get-AzRecoveryServicesBackupJob'
        foreach ($name in $names) {
            $cmd = $script:Ast.Find({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $name }, $true)
            $cmd | Should -Not -BeNullOrEmpty
            $pipeline = $cmd.Parent
            $pipeline.PipelineElements.Count | Should -BeGreaterThan 0
            ($pipeline.PipelineElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandAst] -and $_.GetCommandName() -in 'Select-Object', 'select' }) |
                Should -BeNullOrEmpty -Because "$name ran with -ErrorAction SilentlyContinue into Select-Object -First and ended the script silently"
        }
    }
}

Describe 'Lab 5.2 - Business Continuity Deploy-Bicep.ps1 step 7 waits for the backup item instead of skipping the backup' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

        # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
        $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.RecoveryServices', 'Az.DataProtection', 'Az.Compute', 'Az.OperationalInsights')
        $script:StubCommands = @(
            'Get-AzContext'
            'Get-AzResourceProvider'
            'Register-AzResourceProvider'
            'Get-AzResourceGroup'
            'Get-AzOperationalInsightsWorkspace'
            'Get-AzResource'
            'Get-AzADServicePrincipal'
            'New-AzSubscriptionDeployment'
            'Get-AzRecoveryServicesVault'
            'Get-AzRecoveryServicesBackupProperty'
            'Set-AzRecoveryServicesBackupProperty'
            'Get-AzRecoveryServicesBackupProtectionPolicy'
            'Get-AzVM'
            'Enable-AzRecoveryServicesBackupProtection'
            'Get-AzRecoveryServicesBackupItem'
            'Get-AzRecoveryServicesBackupRecoveryPoint'
            'Get-AzRecoveryServicesBackupJob'
            'Get-AzRecoveryServicesBackupJobDetail'
            'Backup-AzRecoveryServicesBackupItem'
            'Start-Sleep'
        )

        # Every call is logged to SKYCRAFT_STUB_LOG. The vault lists a VM as a backup item only after
        # Enable was called for it and the item was read SKYCRAFT_STUB_LISTAFTER times since: the
        # listing delay seen live on 2026-10-31. The key vault is absent, so no role grant or wait.
        $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall { param([string]$Name) Add-Content -LiteralPath $script:LogPath -Value $Name }

function Get-AzContext { [CmdletBinding()] param() [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'stub-account' } } }
function Get-AzResourceProvider { [CmdletBinding()] param([string]$ProviderNamespace) [pscustomobject]@{ RegistrationState = 'Registered' } }
function Register-AzResourceProvider { [CmdletBinding()] param([string]$ProviderNamespace) Write-StubCall "Register-AzResourceProvider:$ProviderNamespace" }
function Get-AzResourceGroup { [CmdletBinding()] param([string]$Name) [pscustomobject]@{ ResourceGroupName = $Name } }
function Get-AzOperationalInsightsWorkspace { [CmdletBinding()] param([string]$ResourceGroupName, [string]$Name) [pscustomobject]@{ ResourceId = "/stub/workspaces/$Name" } }
function Get-AzADServicePrincipal { [CmdletBinding()] param([string]$ApplicationId) throw 'stub: no key vault, so no service principal lookup' }

function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$ResourceType, [string]$Name, [string]$ApiVersion)
    if ($ResourceType -eq 'Microsoft.Insights/actionGroups') { return [pscustomobject]@{ ResourceId = "/stub/actionGroups/$Name" } }
}

function New-AzSubscriptionDeployment {
    [CmdletBinding()]
    param([string]$Name, [string]$Location, [string]$TemplateFile, [string]$parWorkspaceId, [string]$parBackupManagementServicePrincipalId, [string]$parKeyVaultName)
    Write-StubCall 'New-AzSubscriptionDeployment'
    $outputs = @{}
    foreach ($pair in @{ outRsvId = '/stub/rsv'; outBvId = '/stub/bv'; outBvPrincipalId = 'stub-principal'; outSnapshotRgName = 'stub-rpc1-rg'
            outSnapshotRgPrefix = 'stub-rpc'; outSnapshotRgSuffix = 'rg'; outAlertProcessingRuleId = '/stub/apr' }.GetEnumerator()) {
        $outputs[$pair.Key] = [pscustomobject]@{ Value = $pair.Value }
    }
    [pscustomobject]@{ ProvisioningState = 'Succeeded'; Outputs = $outputs }
}

function Get-AzRecoveryServicesVault { [CmdletBinding()] param([string]$ResourceGroupName, [string]$Name) [pscustomobject]@{ ID = '/stub/rsv'; Name = $Name } }
function Get-AzRecoveryServicesBackupProperty { [CmdletBinding()] param($Vault) [pscustomobject]@{ BackupStorageRedundancy = 'LocallyRedundant'; StorageTypeState = 'Unlocked' } }
function Set-AzRecoveryServicesBackupProperty { [CmdletBinding()] param($Vault, [string]$BackupStorageRedundancy) Write-StubCall 'Set-AzRecoveryServicesBackupProperty' }

function Get-AzRecoveryServicesBackupProtectionPolicy {
    [CmdletBinding()]
    param([string]$Name, [string]$WorkloadType, [string]$BackupManagementType, [string]$PolicySubType, [string]$VaultId)
    [pscustomobject]@{ Name = 'SkyCraft-Daily-Prod'; AzureBackupRGName = 'stub-rpc'; AzureBackupRGNameSuffix = 'rg' }
}

function Get-AzVM {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    [pscustomobject]@{ Name = $Name; ResourceGroupName = $ResourceGroupName }
}

function Enable-AzRecoveryServicesBackupProtection {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, $Policy, [string]$VaultId)
    Write-StubCall "Enable:$Name"
    [pscustomobject]@{ Status = 'Completed'; JobId = "enable-$Name" }
}

function Get-AzRecoveryServicesBackupItem {
    [CmdletBinding()]
    param([string]$VaultId, [string]$BackupManagementType, [string]$WorkloadType)
    Write-StubCall 'ItemList'
    [string[]]$lines = @(Get-Content -LiteralPath $script:LogPath)
    foreach ($vm in 'dev-skycraft-swc-auth-vm', 'dev-skycraft-swc-world-vm') {
        $enabledAt = [array]::LastIndexOf($lines, "Enable:$vm")
        if ($enabledAt -lt 0) { continue }
        $reads = @($lines[($enabledAt + 1)..($lines.Count - 1)] | Where-Object { $_ -eq 'ItemList' }).Count
        if ($reads -ge [int]$env:SKYCRAFT_STUB_LISTAFTER) {
            [pscustomobject]@{ Name = "VM;iaasvmcontainerv2;dev-skycraft-swc-rg;$vm"; FriendlyName = ''; ContainerName = "iaasvmcontainerv2;dev-skycraft-swc-rg;$vm"; ProtectionPolicyName = 'SkyCraft-Daily-Prod' }
        }
    }
}

function Get-AzRecoveryServicesBackupRecoveryPoint { [CmdletBinding()] param($Item, [string]$VaultId) }

function Get-AzRecoveryServicesBackupJob {
    [CmdletBinding()]
    param([string]$VaultId, [string]$BackupManagementType, [string]$Operation, [string]$Status, [string]$JobId)
    if ($JobId) { [pscustomobject]@{ JobId = $JobId; Status = 'Completed'; WorkloadName = 'stub' } }
}

function Get-AzRecoveryServicesBackupJobDetail {
    [CmdletBinding()]
    param([string]$JobId, [string]$VaultId)
    [pscustomobject]@{ SubTasks = @([pscustomobject]@{ Name = 'Take Snapshot'; Status = 'Completed' }); ErrorDetails = @() }
}

function Backup-AzRecoveryServicesBackupItem {
    [CmdletBinding()]
    param($Item, [string]$VaultId, [datetime]$ExpiryDateTimeUTC)
    $vm = ($Item.ContainerName -split ';')[-1]
    Write-StubCall "Backup:$vm"
    [pscustomobject]@{ JobId = "backup-$vm"; Status = 'InProgress'; StartTime = (Get-Date) }
}

function Start-Sleep { [CmdletBinding()] param([int]$Seconds) Write-StubCall "Sleep:$Seconds" }
'@

        function Invoke-DeployScript {
            param([int]$ListAfter, [string[]]$ArgumentList)
            $log = Join-Path $script:Stub.Directory ('calls-' + [guid]::NewGuid().ToString('N') + '.log')
            New-Item -ItemType File -Path $log | Out-Null
            $run = Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
                SKYCRAFT_STUB_LOG       = $log
                SKYCRAFT_STUB_LISTAFTER = $ListAfter
            }
            [pscustomobject]@{ ExitCode = $run.ExitCode; Refused = $run.Refused; Output = $run.Output; Calls = @(Get-Content -LiteralPath $log) }
        }

        $script:Stub = Initialize-LabScriptStub -Name 'SkyCraftLab52DeployStub' -Command $script:StubCommands `
            -Body $script:StubBody -RequiredModule $script:RequiredModules

        $script:Listed      = Invoke-DeployScript -ListAfter 1 -ArgumentList '-Force', '-SkipSiteRecovery', '-BackupItemPollSeconds', '0', '-BackupItemWaitMinutes', '5'
        $script:ListedLate  = Invoke-DeployScript -ListAfter 3 -ArgumentList '-Force', '-SkipSiteRecovery', '-BackupItemPollSeconds', '0', '-BackupItemWaitMinutes', '5'
        $script:NeverListed = Invoke-DeployScript -ListAfter 999 -ArgumentList '-Force', '-SkipSiteRecovery', '-BackupItemPollSeconds', '0', '-BackupItemWaitMinutes', '0'
    }

    AfterAll {
        if ($script:Stub.Directory) { Remove-Item -LiteralPath $script:Stub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:Listed, $script:ListedLate, $script:NeverListed) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'reaches step 7 and enables protection for both VMs' {
        foreach ($run in $script:Listed, $script:ListedLate, $script:NeverListed) {
            $run.Calls | Should -Contain 'Enable:dev-skycraft-swc-auth-vm' -Because "output was:`n$($run.Output)"
            $run.Calls | Should -Contain 'Enable:dev-skycraft-swc-world-vm'
        }
    }

    It 'triggers the backup and exits 0 when the vault lists the item at the first look' {
        $run = $script:Listed
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Contain 'Backup:dev-skycraft-swc-auth-vm'
        $run.Calls | Should -Contain 'Backup:dev-skycraft-swc-world-vm'
        $run.Output | Should -Not -Match 'Poll \d+:'
    }

    It 'polls with a progress line, triggers the backup once the item is listed and exits 0' {
        $run = $script:ListedLate
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Poll 1: dev-skycraft-swc-auth-vm is not listed as a backup item yet'
        $run.Output | Should -Match 'Poll 2: dev-skycraft-swc-auth-vm is not listed as a backup item yet'
        $run.Output | Should -Not -Match 'Poll 3:'
        $run.Calls | Should -Contain 'Backup:dev-skycraft-swc-auth-vm'
        $run.Calls | Should -Contain 'Backup:dev-skycraft-swc-world-vm'
        $run.Output | Should -Match 'Deployment Complete'
    }

    It 'counts a VM that is never listed as a failure, exits 1 and says why' {
        $run = $script:NeverListed
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -like 'Backup:*' }) | Should -BeNullOrEmpty
        $run.Output | Should -Match 'dev-skycraft-swc-auth-vm was not listed as a backup item within 0 minutes of enabling protection'
        $run.Output | Should -Match 'Deployment finished with 2 failure\(s\)'
        $run.Output | Should -Not -Match 'Deployment Complete'
    }
}
