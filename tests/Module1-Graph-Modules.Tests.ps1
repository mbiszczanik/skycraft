<#
.SYNOPSIS
    Pester 5 test: Module 1's Microsoft Graph scripts name the modules they need, check them
    themselves and tell the learner how to install a missing one (issue #375).

.DESCRIPTION
    Azure Cloud Shell ships Azure PowerShell and a basic set of Microsoft Graph modules, but not
    Microsoft.Graph.Users. The Lab 1.1 scripts and Lab 1.2's New-LabRoleAssignment.ps1 declared it
    in '#Requires -Modules', so in Cloud Shell they stopped before their first line with
    PowerShell's own error, which names no install command, and the Module 1 prerequisites named
    no Graph module at all.

    The scripts now keep their Graph modules in a $labModule list, check it with Test-LabModule
    from tools/LabCommon.psm1 right after importing that module, and end with
    'Exit-Lab -FailureCount 1' when one is missing. This suite holds that in place:

      - Test-LabModule itself: $true when every module is installed; $false, with the missing
        module and 'Install-Module <name> -Scope CurrentUser' printed, when one is not.
      - No script under module-*/ or scripts/ declares a Microsoft.Graph module in #Requires.
      - Every module-* script that calls a Microsoft Graph cmdlet has a $labModule list that
        holds exactly the modules of the cmdlets it calls (no fewer, no more), checks it before
        its first Graph call and ends through Exit-Lab when the check fails.
      - Run for real (tests/Support/LabScriptStub.psm1, nothing reaches a tenant) with
        Microsoft.Graph.Users hidden, each script exits 1, names the module and the install
        command, and calls no Graph or Az command.
      - The Module 1 README's prerequisites and each Module 1 lab guide's prerequisites name every
        module their scripts require, with an 'Install-Module ... -Scope CurrentUser' line, and
        any prerequisites section in a module README or lab guide that offers Cloud Shell says
        what a session without a storage account does.

.EXAMPLE
    Invoke-Pester -Path .\tests\Module1-Graph-Modules.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #375
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    # Module directories first, then recurse: 'Get-ChildItem -Path module-* -Recurse -File
    # -Filter' returns nothing at all on pwsh 7.6.
    $moduleDirs = @(Get-ChildItem -LiteralPath $RepoRoot -Directory -Filter 'module-*')
    if ($moduleDirs.Count -eq 0) { throw 'No module-* directory found - the discovery is broken.' }

    $labScripts = @(foreach ($dir in $moduleDirs) {
            Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter '*.ps1' |
                Where-Object { $_.Directory.Name -eq 'scripts' }
        })
    $rootScripts = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -File -Filter '*.ps1')
    if ($labScripts.Count -eq 0) { throw 'No lab script found under module-*/**/scripts/ - the discovery is broken.' }

    $ScriptCases = @(foreach ($file in @($labScripts) + @($rootScripts)) {
            @{ file = $file.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'; path = $file.FullName }
        })

    # Every module-* script that calls a Microsoft Graph cmdlet (Verb-Mg...), outside comments.
    $GraphScriptCases = @(foreach ($file in $labScripts) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $mgCall = $ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                    $args[0].GetCommandName() -match '^[A-Za-z]+-Mg[A-Za-z]+$'
                }, $true)
            if (@($mgCall).Count -gt 0) {
                @{ file = $file.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'; path = $file.FullName }
            }
        })

    $module1 = Join-Path $RepoRoot 'module-1-identities-governance'
    $GuideCases = @(foreach ($lab in Get-ChildItem -LiteralPath $module1 -Directory | Where-Object { $_.Name -match '^\d+\.\d+-' }) {
            $guide = @(Get-ChildItem -LiteralPath $lab.FullName -File -Filter 'lab-guide-*.md')
            if ($guide.Count -eq 1) { @{ lab = $lab.Name; guide = $guide[0].FullName; scripts = (Join-Path $lab.FullName 'scripts') } }
        })

    $PrerequisiteDocs = @(foreach ($dir in $moduleDirs) {
            $readme = Join-Path $dir.FullName 'README.md'
            if (Test-Path -LiteralPath $readme) { $readme }
            Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter 'lab-guide-*.md' | ForEach-Object { $_.FullName }
        }) | ForEach-Object { @{ file = $_.Substring($RepoRoot.Length + 1) -replace '\\', '/'; path = $_ } }
}

BeforeAll {
    $script:RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:LabCommonPath = Join-Path $script:RepoRoot 'tools/LabCommon.psm1'

    # The module of every Microsoft Graph cmdlet a Module 1 script calls. A script that starts
    # calling another one fails 'calls only Graph cmdlets this suite knows the module of' until
    # it is added here (and to the script's $labModule list).
    $script:CmdletModule = @{
        'Connect-MgGraph'       = 'Microsoft.Graph.Authentication'
        'Disconnect-MgGraph'    = 'Microsoft.Graph.Authentication'
        'Get-MgContext'         = 'Microsoft.Graph.Authentication'
        'Invoke-MgGraphRequest' = 'Microsoft.Graph.Authentication'
        'Get-MgUser'            = 'Microsoft.Graph.Users'
        'New-MgUser'            = 'Microsoft.Graph.Users'
        'Update-MgUser'         = 'Microsoft.Graph.Users'
        'Remove-MgUser'         = 'Microsoft.Graph.Users'
        'Get-MgGroup'           = 'Microsoft.Graph.Groups'
        'New-MgGroup'           = 'Microsoft.Graph.Groups'
        'Remove-MgGroup'        = 'Microsoft.Graph.Groups'
        'Get-MgGroupMember'     = 'Microsoft.Graph.Groups'
        'New-MgGroupMember'     = 'Microsoft.Graph.Groups'
        'Get-MgDomain'          = 'Microsoft.Graph.Identity.DirectoryManagement'
        'New-MgInvitation'      = 'Microsoft.Graph.Identity.SignIns'
    }

    function Get-ScriptAst {
        param([string]$Path)
        $parseError = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseError)
        if ($parseError) { throw "$(Split-Path -Leaf $Path) does not parse: $($parseError[0].Message)" }
        $ast
    }

    function Test-InsideFunction {
        param($Node)
        for ($parent = $Node.Parent; $parent; $parent = $parent.Parent) {
            if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $true }
        }
        return $false
    }

    # The string constants of the script's top-level '$labModule = ...' assignment.
    function Get-LabModuleList {
        param($Ast)
        $assignment = @($Ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -eq 'labModule'
                }, $false))
        if ($assignment.Count -ne 1) { return $null }
        , @($assignment[0].Right.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value)
    }

    # Every module a script needs: its '#Requires -Modules' line, then its $labModule list.
    function Get-ScriptModule {
        param([string]$Path)
        $ast = Get-ScriptAst -Path $Path
        $required = @($ast.ScriptRequirements.RequiredModules | ForEach-Object { $_.Name })
        $listed   = Get-LabModuleList -Ast $ast
        @($required) + @($listed) | Where-Object { $_ } | Select-Object -Unique
    }

    # The '## ... Prerequisites' section of a Markdown file, up to the next level-2 heading.
    function Get-PrerequisiteSection {
        param([string]$Path)
        $text = (Get-Content -Raw -LiteralPath $Path) -replace "`r`n", "`n"
        $match = [regex]::Match($text, '(?ms)^##\s[^\n]*Prerequisites[^\n]*\n(?<body>.*?)(?=^##\s|\z)')
        if ($match.Success) { $match.Groups['body'].Value } else { '' }
    }

    # The module names of every 'Install-Module <a>, <b> -Scope CurrentUser' line in a text.
    function Get-InstalledByCommand {
        param([string]$Text)
        foreach ($m in [regex]::Matches($Text, 'Install-Module\s+(?<names>[A-Za-z0-9.]+(?:\s*,\s*[A-Za-z0-9.]+)*)\s+-Scope\s+CurrentUser')) {
            $m.Groups['names'].Value -split '\s*,\s*'
        }
    }
}

Describe 'Test-LabModule - names a missing module and its install command (#375)' {

    BeforeAll {
        $script:LabCommon = Import-Module $script:LabCommonPath -Force -PassThru

        function Invoke-TestLabModule {
            param([string[]]$Name)
            $output = @(Test-LabModule -Name $Name 6>&1)
            [pscustomobject]@{
                Result = @($output | Where-Object { $_ -is [bool] })
                Text   = (@($output | Where-Object { $_ -isnot [bool] }) | ForEach-Object { "$_" }) -join "`n"
            }
        }
    }

    AfterAll {
        Remove-Module -ModuleInfo $script:LabCommon -Force -ErrorAction SilentlyContinue
    }

    It 'returns $true and prints nothing when every module is installed' {
        $run = Invoke-TestLabModule -Name 'Microsoft.PowerShell.Utility', 'Microsoft.PowerShell.Management'
        $run.Result | Should -Be @($true)
        $run.Text | Should -BeNullOrEmpty
    }

    It 'returns $false and names the missing module and the install command' {
        $run = Invoke-TestLabModule -Name 'Microsoft.PowerShell.Utility', 'SkyCraft.NoSuchModule375'
        $run.Result | Should -Be @($false)
        $run.Text | Should -Match '\[ERROR\] This script needs the PowerShell module SkyCraft\.NoSuchModule375, which is not installed\.'
        $run.Text | Should -Match ([regex]::Escape('Install-Module SkyCraft.NoSuchModule375 -Scope CurrentUser'))
        $run.Text | Should -Not -Match 'Microsoft\.PowerShell\.Utility' -Because 'only the missing module is named'
        $run.Text | Should -Match 'without a storage account' -Because 'Cloud Shell learners must know the install does not last'
    }

    It 'names every missing module in one install command' {
        $run = Invoke-TestLabModule -Name 'SkyCraft.NoSuchModuleA', 'Microsoft.PowerShell.Utility', 'SkyCraft.NoSuchModuleB'
        $run.Result | Should -Be @($false)
        $run.Text | Should -Match 'these PowerShell modules, which are not installed: SkyCraft\.NoSuchModuleA, SkyCraft\.NoSuchModuleB\.'
        $run.Text | Should -Match ([regex]::Escape('Install-Module SkyCraft.NoSuchModuleA, SkyCraft.NoSuchModuleB -Scope CurrentUser'))
    }
}

Describe 'Microsoft Graph modules are never a #Requires line (#375)' {

    It "'<file>' declares no Microsoft.Graph module in #Requires -Modules" -ForEach $ScriptCases {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $graph = @($ast.ScriptRequirements.RequiredModules | Where-Object { $_.Name -like 'Microsoft.Graph*' } | ForEach-Object { $_.Name })
        $graph | Should -BeNullOrEmpty -Because 'Azure Cloud Shell does not ship every Graph module; list them in $labModule and check them with Test-LabModule (docs/powershell-standards.md section 1)'
    }
}

Describe 'Module 1 Graph scripts check exactly the modules they call (#375)' {

    It 'finds the four Graph scripts of Labs 1.1 and 1.2' -ForEach @(@{ count = @($GraphScriptCases).Count }) {
        $count | Should -BeGreaterOrEqual 4 -Because 'the discovery of scripts that call Microsoft Graph must not come back empty'
    }

    It "'<file>' calls only Graph cmdlets this suite knows the module of" -ForEach $GraphScriptCases {
        $ast = Get-ScriptAst -Path $path
        $called = @($ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                    $args[0].GetCommandName() -match '^[A-Za-z]+-Mg[A-Za-z]+$'
                }, $true) | ForEach-Object { $_.GetCommandName() } | Select-Object -Unique)
        $unknown = @($called | Where-Object { -not $script:CmdletModule.ContainsKey($_) })
        $unknown | Should -BeNullOrEmpty -Because 'add the cmdlet and its module to $CmdletModule in this suite'
    }

    It "'<file>' lists in `$labModule exactly the modules of the Graph cmdlets it calls" -ForEach $GraphScriptCases {
        $ast = Get-ScriptAst -Path $path
        $called = @($ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                    $args[0].GetCommandName() -match '^[A-Za-z]+-Mg[A-Za-z]+$'
                }, $true) | ForEach-Object { $_.GetCommandName() } | Select-Object -Unique)
        $needed = @($called | ForEach-Object { $script:CmdletModule[$_] } | Where-Object { $_ } | Sort-Object -Unique)

        $listed = Get-LabModuleList -Ast $ast
        $listed | Should -Not -BeNullOrEmpty -Because 'the script keeps its Graph modules in one top-level $labModule list'
        @($listed | Sort-Object -Unique) | Should -Be $needed -Because 'the list holds every module the script calls and no other (the smallest set)'
    }

    It "'<file>' checks `$labModule with Test-LabModule and ends through Exit-Lab, before any Graph call" -ForEach $GraphScriptCases {
        $ast = Get-ScriptAst -Path $path

        $check = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.IfStatementAst] -and
                    @($node.Clauses[0].Item1.FindAll({
                                $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                                $args[0].GetCommandName() -eq 'Test-LabModule' -and
                                $args[0].Extent.Text -match '-Name\s+\$labModule\b'
                            }, $true)).Count -gt 0
                }, $true) | Where-Object { -not (Test-InsideFunction -Node $_) })
        $check.Count | Should -Be 1 -Because "'if (-not (Test-LabModule -Name `$labModule)) { Exit-Lab -FailureCount 1 }' runs once, at the top level"

        $exitCall = @($check[0].Clauses[0].Item2.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Exit-Lab'
                }, $true))
        $exitCall.Count | Should -Be 1
        $exitCall[0].Extent.Text | Should -Match '-FailureCount\s+1\b'

        # Every top-level call that reaches Graph - a Graph cmdlet, or a function of the script
        # that calls one (Connect-LabGraph) - comes after the check.
        $graphFunction = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                Where-Object {
                    @($_.Body.FindAll({
                                $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                                $args[0].GetCommandName() -match '^[A-Za-z]+-Mg[A-Za-z]+$'
                            }, $true)).Count -gt 0
                } | ForEach-Object { $_.Name })
        $reach = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    ($node.GetCommandName() -match '^[A-Za-z]+-Mg[A-Za-z]+$' -or $graphFunction -contains $node.GetCommandName())
                }, $true) | Where-Object { -not (Test-InsideFunction -Node $_) })
        $reach.Count | Should -BeGreaterThan 0
        foreach ($call in $reach) {
            $call.Extent.StartOffset | Should -BeGreaterThan $check[0].Extent.EndOffset -Because "'$($call.GetCommandName())' must not run before the module check"
        }

        $import = @($ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                    $args[0].GetCommandName() -eq 'Import-Module' -and
                    $args[0].Extent.Text -match '-Name\s+\$labModule\b'
                }, $true) | Where-Object { -not (Test-InsideFunction -Node $_) })
        $import.Count | Should -Be 1 -Because 'the modules are imported in the order #Requires imported them'
        $import[0].Extent.StartOffset | Should -BeGreaterThan $check[0].Extent.EndOffset
    }

    It "the module each cmdlet is mapped to exports it (where Microsoft Graph is installed)" -Skip:(-not (Get-Module -ListAvailable -Name 'Microsoft.Graph.Users')) {
        # Read from the installed manifests: Get-Command would import the Graph modules into the
        # test session, next to whatever Az assemblies another suite loaded.
        foreach ($cmdlet in $script:CmdletModule.Keys) {
            $module = @(Get-Module -ListAvailable -Name $script:CmdletModule[$cmdlet] | Sort-Object Version -Descending)[0]
            $module | Should -Not -BeNullOrEmpty -Because "$($script:CmdletModule[$cmdlet]) is installed with Microsoft.Graph.Users"
            @($module.ExportedCommands.Keys) | Should -Contain $cmdlet -Because "$cmdlet is mapped to $($module.Name)"
        }
    }
}

Describe 'Module 1 Graph scripts stop with the install command when a module is missing (#375)' {

    BeforeAll {
        Import-Module (Join-Path $script:RepoRoot 'tests' 'Support' 'LabScriptStub.psm1') -Force

        # Every Graph and Az command a Module 1 Graph script calls: each logs its name and throws,
        # so a script that got past the module check is caught and nothing reaches a tenant.
        $script:StubCommand = @($script:CmdletModule.Keys) + @('Get-AzContext', 'Connect-AzAccount', 'Get-AzRoleAssignment', 'New-AzRoleAssignment')
        $stubFunctions = foreach ($name in $script:StubCommand) {
            "function $name { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]`$Rest) Add-Content -LiteralPath `$env:SKYCRAFT_STUB_LOG -Value '$name'; throw 'stub: $name was called' }"
        }
        # Get-Module hides the modules named in SKYCRAFT_STUB_NOMODULE, as a host without them
        # (Azure Cloud Shell and Microsoft.Graph.Users) would, and asks the real cmdlet otherwise.
        $script:StubBody = @'
function Get-Module {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$Name,

        [switch]$ListAvailable,

        [Parameter(ValueFromRemainingArguments)]
        $Rest
    )
    $hidden = @("$env:SKYCRAFT_STUB_NOMODULE" -split ',' | Where-Object { $_ })
    $wanted = @($Name | Where-Object { $_ -and $hidden -notcontains $_ })
    if ($Name -and $wanted.Count -eq 0) { return }
    $splat = @{ ListAvailable = $ListAvailable }
    if ($wanted.Count -gt 0) { $splat['Name'] = $wanted }
    Microsoft.PowerShell.Core\Get-Module @splat
}

'@ + ($stubFunctions -join "`n") + "`n"

        $script:Stubs = @{}
    }

    AfterAll {
        foreach ($stub in $script:Stubs.Values) {
            Remove-Item -LiteralPath $stub.Directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "'<file>' exits 1, names Microsoft.Graph.Users and its install command, and calls nothing" -ForEach $GraphScriptCases {
        $required = @(Get-ScriptModule -Path $path)
        $stub = Initialize-LabScriptStub -Name 'SkyCraftGraphModuleStub' `
            -Command (@('Get-Module') + $script:StubCommand) `
            -Body $script:StubBody `
            -RequiredModule $required
        $script:Stubs[$file] = $stub

        $log = Join-Path $TestDrive ("calls-" + [guid]::NewGuid().ToString('N') + '.log')
        Set-Content -LiteralPath $log -Value $null

        $run = Invoke-LabScriptWithStub -Stub $stub -ScriptPath $path -Environment @{
            SKYCRAFT_STUB_LOG      = $log
            SKYCRAFT_STUB_NOMODULE = 'Microsoft.Graph.Users'
        }

        $run.Refused | Should -BeFalse -Because $run.Output
        $run.ExitCode | Should -Be 1 -Because $run.Output
        $run.Output | Should -Match 'needs the PowerShell module Microsoft\.Graph\.Users, which is not installed'
        $run.Output | Should -Match ([regex]::Escape('Install-Module Microsoft.Graph.Users -Scope CurrentUser'))
        @(Get-Content -LiteralPath $log | Where-Object { $_ }) | Should -BeNullOrEmpty -Because 'the script stops before it signs in or looks anything up'
    }
}

Describe 'Module 1 prerequisites name every module and its install command (#375)' {

    It 'the Module 1 README names every module the Module 1 scripts require, with Install-Module' {
        $readme  = Join-Path $script:RepoRoot 'module-1-identities-governance/README.md'
        $section = Get-PrerequisiteSection -Path $readme
        $section | Should -Not -BeNullOrEmpty

        $scriptsDir = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'module-1-identities-governance') -Directory |
                ForEach-Object { Join-Path $_.FullName 'scripts' } | Where-Object { Test-Path -LiteralPath $_ })
        $needed = @(foreach ($dir in $scriptsDir) {
                Get-ChildItem -LiteralPath $dir -File -Filter '*.ps1' | ForEach-Object { Get-ScriptModule -Path $_.FullName }
            }) | Sort-Object -Unique
        $needed | Should -Contain 'Microsoft.Graph.Users'

        $installed = @(Get-InstalledByCommand -Text $section)
        foreach ($module in $needed) {
            $section | Should -Match ('`' + [regex]::Escape($module) + '`') -Because "the prerequisites name $module"
            $installed | Should -Contain $module -Because "an 'Install-Module ... -Scope CurrentUser' line installs $module"
        }
        $section | Should -Match ([regex]::Escape('Install-Module Microsoft.Graph.Users -Scope CurrentUser')) -Because 'Cloud Shell lacks only this one'
    }

    It "lab <lab>'s guide names every module its scripts require, with Install-Module" -ForEach $GuideCases {
        $section = Get-PrerequisiteSection -Path $guide
        $section | Should -Not -BeNullOrEmpty

        $needed = @(Get-ChildItem -LiteralPath $scripts -File -Filter '*.ps1' | ForEach-Object { Get-ScriptModule -Path $_.FullName }) | Sort-Object -Unique
        $needed.Count | Should -BeGreaterThan 0

        $installed = @(Get-InstalledByCommand -Text $section)
        foreach ($module in $needed) {
            $section | Should -Match ('`' + [regex]::Escape($module) + '`') -Because "the prerequisites name $module"
            $installed | Should -Contain $module -Because "an 'Install-Module ... -Scope CurrentUser' line installs $module"
        }
        if ($needed -contains 'Microsoft.Graph.Users') {
            $section | Should -Match ([regex]::Escape('Install-Module Microsoft.Graph.Users -Scope CurrentUser')) -Because 'Azure Cloud Shell does not ship Microsoft.Graph.Users'
        }
    }

    It "'<file>' says what a Cloud Shell session without a storage account does, where its prerequisites offer Cloud Shell" -ForEach $PrerequisiteDocs {
        $section = Get-PrerequisiteSection -Path $path
        if ($section -match 'Cloud Shell') {
            $section | Should -Match 'without a storage account' -Because 'issue #375: a guide that offers Cloud Shell says whether a session without storage can run the scripts'
        }
    }
}
