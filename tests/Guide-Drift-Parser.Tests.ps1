<#
.SYNOPSIS
    Pester 5 tests for tools/guide-drift/parse.py, the guide-to-steps parser of the guide drift tool.

.DESCRIPTION
    The parser is Python standard library only, so this suite runs on the ubuntu-latest runner
    without a browser. Two kinds of test:

      FIXTURES - small guides written here, parsed through a temp file, asserting the rules of
      issue #189: only '### Step X.Y.N:' sections are read; fenced code is skipped; where a step
      has '#### Option 1:' or '#### Option A:' headings only the first option is read (plus the
      step's Expected Result); bold spans that are not UI elements are dropped; 'A -> B' chains
      become navigation; 'Search for **X**' becomes a search of the Portal;
      '- **Label**: value' list items and Field | Value tables become fields, and so does
      '- Label: value' when the value is a bold or code span (#198); a field value that is an
      instruction or holds a bracket token is marked literal: false (#202);
      Name | Value and Tag | Value tables become tags; the images a step references are collected.
      A list after 'verify:' or after an Expected Result ending in a colon holds checks for the
      Expected Result, not steps (#224; pinned on labs 2.2 and 4.1, rules in test_parse.py).

      THE 17 GUIDES - every module-*/X.Y-*/lab-guide-X.Y.md parses, its step ids match its
      headings in order, and no label or value carries markup or comment residue. This does NOT
      enforce the multi-modal structure of docs/lab-guide-standards.md section 5; only 3 guides
      use it today.

    -ForEach cases are computed at discovery time (file scope), as every suite in this directory
    does; fixtures are parsed in BeforeAll, because It blocks cannot see file-scope variables.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Drift-Parser.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #189
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester 5 runs It blocks in a later phase than file scope, so everything they use is set up in
# BeforeAll. Only -ForEach case data must be computed at file scope (discovery time).
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Parser   = Join-Path $script:RepoRoot 'tools/guide-drift/parse.py'
    $script:Python   = if ($IsWindows) { 'python' } else { 'python3' }

    # Parses markdown text through a temp file and returns the steps object. Images are resolved
    # relative to the temp file's directory, so fixtures that need images create them beside it.
    function ConvertFrom-GuideFixture {
        param([string]$Markdown, [string]$Directory = (Join-Path $TestDrive ("guide-" + [guid]::NewGuid())))
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        $guide = Join-Path $Directory 'lab-guide-9.9.md'
        $out   = Join-Path $Directory 'steps.json'
        $err   = Join-Path $Directory 'stderr.txt'
        Set-Content -LiteralPath $guide -Value $Markdown -Encoding utf8 -NoNewline
        # The JSON goes through --out and is read back as UTF-8: a piped stdout is re-encoded
        # by the console code page on Windows, which this test must not depend on.
        & $script:Python $script:Parser $guide --out $out 2> $err
        if ($LASTEXITCODE -ne 0) { throw "parse.py failed ($LASTEXITCODE): $(Get-Content -Raw -LiteralPath $err)" }
        Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json
    }

    $script:CoreFixture = @'
# Lab 9.9: Fixture

- Click **Situation** before any step

### Step 9.9.1: Navigate and act

1. In the left sidebar, click **Users** → **All users**
2. Click **+ New user** → **Create new user**
3. Search for **"Microsoft Entra ID"** in the search bar
4. **Note**: a **Tip** is not a UI element, nor is **Important** or **Why** or **SkyCraft Choice** or **Remember:**
5. Search for **“Curly Label”**
6. Click **Save** -> **Close**
7. Open **Settings** > **Advanced**

```powershell
Write-Host "**InFence** is never read"
1. Click **InFence**
### Step 9.9.8: Fake
```

**Expected Result**: New user appears in the list.

### Step 9.9.2: Options

#### Option 1: Azure Portal (GUI)

1. Navigate to **Storage accounts**
2. Click **+ File share**

#### Option 2: Azure CLI

1. Run **OnlyInCli** here

**Expected Result**: Share appears.

### Step 9.9.3: No portal part

1. Run the script and read the output.

## Checklist

- [ ] **NotAStep** bold after the last step is ignored
'@

    $script:Core = ConvertFrom-GuideFixture -Markdown $script:CoreFixture
}

Describe 'parse.py - step sections' {
    It 'reads exactly the "### Step X.Y.N:" sections, in order' {
        @($script:Core.steps.id) | Should -Be @('9.9.1', '9.9.2', '9.9.3')
        $script:Core.steps[0].title | Should -Be 'Navigate and act'
        $script:Core.lab | Should -Be '9.9'
    }

    It 'splits an arrow chain into one navigation item with several labels' {
        $nav = $script:Core.steps[0].items[0]
        $nav.kind | Should -Be 'navigation'
        @($nav.labels) | Should -Be @('Users', 'All users')
        $nav.line | Should -Be 7    # line 1 is the title, line 5 the step heading, line 7 the first item
    }

    It 'keeps a leading "+" in a label and strips surrounding quotes' {
        @($script:Core.steps[0].items[1].labels) | Should -Be @('+ New user', 'Create new user')
        @($script:Core.steps[0].items[2].labels) | Should -Be @('Microsoft Entra ID')
        @($script:Core.steps[0].items[3].labels) | Should -Be @('Curly Label')
    }

    It 'reads "Search for **X**" as one search item, with or without where to search' {
        foreach ($i in 2, 3) {
            $script:Core.steps[0].items[$i].kind | Should -Be 'search'
        }
        $script:Core.steps[0].items[2].scope | Should -Be 'global' -Because 'it says "in the search bar"'
        $script:Core.steps[0].items[3].scope | Should -Be 'blade' -Because 'it names no Portal search'
    }

    It 'reads "Search for" only at the start of the item, after "In Azure Portal,", and only before the first bold' {
        $guide = ConvertFrom-GuideFixture -Markdown (@(
                '### Step 9.9.1: Searches',
                '',
                '1. search for **Backup vaults**.',
                '2. In Azure Portal, search for **Policy**',
                '3. Open **Settings** and search for **Advanced**',
                '4. Search for **Container Apps** in the portal and click **+ Create**.',
                '5. Search for **"Khadgar Archmage"** (individual user)',
                '6. Search for the **Owner** role',
                '7. Search for **Network Watcher** in Azure Portal'
            ) -join "`n")
        @($guide.steps[0].items.kind) | Should -Be @('search', 'search', 'action', 'action', 'action', 'action', 'search')
        @($guide.steps[0].items[0].labels) | Should -Be @('Backup vaults')
        @($guide.steps[0].items[1].labels) | Should -Be @('Policy')
        @($guide.steps[0].items | Where-Object kind -eq 'search' | ForEach-Object { $_.scope }) | Should -Be @('blade', 'global', 'global')
        @($guide.steps[0].items[3].labels) | Should -Be @('Container Apps', '+ Create')
        @($guide.steps[0].items[6].labels) | Should -Be @('Network Watcher')
    }

    It 'treats the ASCII arrow and " > " as chain separators too' {
        foreach ($i in 4, 5) {
            $script:Core.steps[0].items[$i].kind | Should -Be 'navigation'
        }
        @($script:Core.steps[0].items[4].labels) | Should -Be @('Save', 'Close')
        @($script:Core.steps[0].items[5].labels) | Should -Be @('Settings', 'Advanced')
    }

    It 'drops bold spans that are not UI elements, and bold inside code fences' {
        $labels = @($script:Core.steps[0].items | ForEach-Object { $_.labels })
        @($script:Core.steps[0].items).Count | Should -Be 6 -Because 'the Note item has no UI label left and is dropped'
        foreach ($notUi in 'Note', 'Tip', 'Important', 'Why', 'SkyCraft Choice', 'Remember:', 'InFence', 'Expected Result') {
            $labels | Should -Not -Contain $notUi
        }
    }

    It 'captures the Expected Result text' {
        $script:Core.steps[0].expected | Should -Be 'New user appears in the list.'
    }

    It 'reads only Option 1 of a multi-option step, plus its Expected Result' {
        $labels = @($script:Core.steps[1].items | ForEach-Object { $_.labels })
        $labels | Should -Be @('Storage accounts', '+ File share')
        $script:Core.steps[1].expected | Should -Be 'Share appears.'
    }

    It 'marks a step with no UI element as portal: false' {
        $script:Core.steps[2].portal | Should -BeFalse
        $script:Core.steps[0].portal | Should -BeTrue
    }

    It 'ignores bold text before the first step and after the last section' {
        $all = @($script:Core.steps | ForEach-Object { $_.items } | ForEach-Object { $_.labels })
        $all | Should -Not -Contain 'Situation'
        $all | Should -Not -Contain 'NotAStep'
    }
}

Describe 'parse.py - form tables, HTML comments and images' {
    BeforeAll {
        $tableFixture = @'
# Lab 9.9: Tables

### Step 9.9.1: Fill a form

1. Click **+ New group**
2. Fill in:

| Field             | Value                     |
| ----------------- | ------------------------- |
| Group type        | Security                  |
| `Group name`      | `SkyCraft-Admins`         |
<!-- | Hidden field | never read | -->
| Tier              | **Hot**                   |
| Region <!-- was: Location --> | Sweden Central |
| --sku             | Standard_LRS              |

3. Click **Create**

<!--
1. Click **CommentedOut**
-->

![Create group](./images/Step-9.9.1.png)
![Other](images/Step-9.9.1b.png)

### Step 9.9.2: Informational tables are not forms

| Subnet Name | Starting Address | Size |
| ----------- | ---------------- | ---- |
| AppSubnet   | 10.0.1.0         | /24  |

| Property  | Expected Value |
| --------- | -------------- |
| Location  | swedencentral  |

| Parameter | Value | Description |
| --------- | ----- | ----------- |
| --name    | x     | flag        |

| Setting | Value        | Notes                       |
| ------- | ------------ | --------------------------- |
| Region  | `westeurope` | three columns, still a form |

1. Click **Review + create**
'@
        $dir = Join-Path $TestDrive 'tables'
        $script:Table = ConvertFrom-GuideFixture -Markdown $tableFixture -Directory $dir
    }

    It 'turns Field | Value rows into fields, stripping markup from label and value' {
        $fields = @($script:Table.steps[0].items | Where-Object kind -eq 'field')
        @($fields.label) | Should -Be @('Group type', 'Group name', 'Tier', 'Region', '--sku') -Because 'a dash-led cell is a value, not a separator row'
        @($fields.value) | Should -Be @('Security', 'SkyCraft-Admins', 'Hot', 'Sweden Central', 'Standard_LRS')
    }

    It 'keeps actions before and after the table in document order' {
        @($script:Table.steps[0].items.kind) | Should -Be @('action', 'field', 'field', 'field', 'field', 'field', 'action')
        @($script:Table.steps[0].items[6].labels) | Should -Be @('Create')
    }

    It 'never reads text inside an HTML comment' {
        $all = @($script:Table.steps | ForEach-Object { $_.items } | ForEach-Object { if ($_.kind -eq 'field') { $_.label } else { $_.labels } })
        $all | Should -Not -Contain 'Hidden field'
        $all | Should -Not -Contain 'CommentedOut'
        @($all | Where-Object { $_ -like '<!--*' }) | Should -BeNullOrEmpty
    }

    It 'treats only tables whose second header is "Value" as forms' {
        $fields = @($script:Table.steps[1].items | Where-Object kind -eq 'field')
        @($fields.label) | Should -Be @('Region') -Because 'Subnet Name | Starting Address and Property | Expected Value are informational'
        $fields[0].value | Should -Be 'westeurope'
    }

    It 'does not read a Parameter | Value table (CLI flags) as a form' {
        $fields = @($script:Table.steps[1].items | Where-Object kind -eq 'field')
        @($fields.label) | Should -Be @('Region')
        @($fields.label) | Should -Not -Contain '--name'
    }

    It 'reads an empty HTML comment as a complete comment, not an opener' {
        $guide = ConvertFrom-GuideFixture -Markdown "### Step 9.9.1: Empty comments`n`n1. Click **First** <!--> and **Second** <!---> then **Third**`n2. Click **Fourth**`n"
        @($guide.steps[0].items.labels) | Should -Be @('First', 'Second', 'Third', 'Fourth')
    }

    It 'reads a separator row of single dashes, or with a trailing empty cell, as a separator' {
        $guide = ConvertFrom-GuideFixture -Markdown "### Step 9.9.1: Separators`n`n1. Click **Open**`n`n| Field | Value | |`n| :- | -: | |`n| Tier | Hot | |`n"
        @(($guide.steps[0].items | Where-Object kind -eq 'field').label) | Should -Be @('Tier')
    }

    It 'collects the images a step references, with and without "./"' {
        @($script:Table.steps[0].images) | Should -Be @('images/Step-9.9.1.png', 'images/Step-9.9.1b.png')
    }
}

Describe 'parse.py - forms and markers found in the real guides' {
    BeforeAll {
        $fixture = @'
# Lab 9.9: Real-guide shapes

### Step 9.9.1: List-item fields

1. Click **+ Create** → **Container App**
2. On the **Basics** tab:
   - **Resource group**: `dev-skycraft-swc-rg`
   - **Region**: **Sweden Central**
   - **\*Deployment source**: **Container Image**
   - **Note**: this is a caption, not a field
3. **Expected Result**: The app is created.

**Expected Result** (if the quota allows): A second result that must not win.

### Step 9.9.2: Lettered options

#### Option A: Portal

1. Click **Generate new key pair**

**Expected Result**: Option A result.

#### Option B: Store the key in Azure

1. Click **OnlyInOptionB**

**Expected Result**: Option B result.

### Step 9.9.3: Long fences

````markdown
```bash
1. Click **LeakedFromFence**
```
1. Click **LeakedFromFence**
````

1. Click **AfterFence**

### Step 9.9.4: Tags

1. Click **Tags**

| Name        | Value         |
| ----------- | ------------- |
| Environment | `Development` |
| Project     | SkyCraft      |

| Field | Value  |
| ----- | ------ |
| Owner | `ops`  |
'@
        $script:Real = ConvertFrom-GuideFixture -Markdown $fixture
    }

    It 'reads "- **Label**: value" list items as fields' {
        $fields = @($script:Real.steps[0].items | Where-Object kind -eq 'field')
        @($fields.label) | Should -Be @('Resource group', 'Region', 'Deployment source')
        @($fields.value) | Should -Be @('dev-skycraft-swc-rg', 'Sweden Central', 'Container Image')
    }

    It 'strips code spans and a final full stop from list-item field values' {
        $guide = ConvertFrom-GuideFixture -Markdown "### Step 9.9.1: Values`n`n- **Source**: ``staging``.`n- **Stored access policy**: Select ``DevRevokePolicy```n"
        @($guide.steps[0].items.value) | Should -Be @('staging', 'Select DevRevokePolicy')
    }

    It 'does not turn a caption such as **Note** into a field' {
        @($script:Real.steps[0].items | Where-Object { $_.kind -eq 'field' -and $_.label -eq 'Note' }) | Should -BeNullOrEmpty
    }

    It 'reads "- Label: value" with a plain label as a field when the value is a bold or code span (#198)' {
        $guide = ConvertFrom-GuideFixture -Markdown (@(
                '### Step 9.9.1: Plain labels',
                '',
                '1. Click **Locks** → **+ Add**',
                '2. Create lock:',
                '   - Lock name: `lock-no-delete-platform`',
                '   - Lock type: **Delete**',
                '   - Public IP: `prod-skycraft-swc-lb-pip` (use existing)',
                '   - Address space: 10.0.0.0/16',
                '   - Select your VM: `dev-skycraft-swc-auth-vm`.',
                '   - Note: `this` is a caption',
                '   - Logs: **StorageRead** and **StorageWrite**.',
                '3. Click **OK**'
            ) -join "`n")
        $items = @($guide.steps[0].items)
        @($items.kind) | Should -Be @('navigation', 'field', 'field', 'field', 'action', 'action')
        $fields = @($items | Where-Object kind -eq 'field')
        @($fields.label) | Should -Be @('Lock name', 'Lock type', 'Public IP')
        @($fields.value) | Should -Be @('lock-no-delete-platform', 'Delete', 'prod-skycraft-swc-lb-pip') -Because 'a remark after the span is not part of the value'
        @($items[4].labels) | Should -Be @('StorageRead', 'StorageWrite') -Because 'several bold spans after a plain label stay clicks'
        @($items | ForEach-Object { $_.labels }) | Should -Not -Contain 'Delete' -Because 'the value of a field is never clicked'
    }

    It 'keeps chains and actions around list-item fields' {
        @($script:Real.steps[0].items[0].labels) | Should -Be @('+ Create', 'Container App')
        $script:Real.steps[0].items[0].kind | Should -Be 'navigation'
        @($script:Real.steps[0].items[1].labels) | Should -Be @('Basics')
    }

    It 'takes the first Expected Result, including one written as a list item' {
        $script:Real.steps[0].expected | Should -Be 'The app is created.'
    }

    It 'reads only Option A of a lettered-option step, and its own Expected Result' {
        $labels = @($script:Real.steps[1].items | ForEach-Object { $_.labels })
        $labels | Should -Be @('Generate new key pair')
        $script:Real.steps[1].expected | Should -Be 'Option A result.'
    }

    It 'reads Name | Value and Tag | Value tables as tag pairs, and Field | Value as fields' {
        $items = @($script:Real.steps[3].items)
        @($items.kind) | Should -Be @('action', 'tag', 'tag', 'field')
        @(($items | Where-Object kind -eq 'tag').name)  | Should -Be @('Environment', 'Project')
        @(($items | Where-Object kind -eq 'tag').value) | Should -Be @('Development', 'SkyCraft')
        ($items | Where-Object kind -eq 'field').label  | Should -Be 'Owner'
    }

    It 'closes a fence only on a run at least as long as its opener' {
        $labels = @($script:Real.steps[2].items | ForEach-Object { $_.labels })
        $labels | Should -Not -Contain 'LeakedFromFence'
        $labels | Should -Contain 'AfterFence'
    }
}

Describe 'parse.py - Expected Result written as a list or with a qualifier' {
    BeforeAll {
        $fixture = @'
# Lab 9.9: Expected Result shapes

### Step 9.9.1: Result as a list

1. Click **Create**

**Expected Result**:

- Deployment **succeeds**
- Open **Services** -> **Repositories** and see `skycraft-auth`

Then continue:

1. Click **Next**

### Step 9.9.2: Result with a qualifier

1. Click **Save**

**Expected Result** (if the quota allows): The share is saved.
'@
        $script:Results = ConvertFrom-GuideFixture -Markdown $fixture
    }

    It 'joins the list after an empty Expected Result into its text, markup stripped' {
        $script:Results.steps[0].expected | Should -Be 'Deployment succeeds; Open Services -> Repositories and see skycraft-auth'
    }

    It 'does not read the Expected Result list as steps' {
        @($script:Results.steps[0].items | ForEach-Object { $_.labels }) | Should -Be @('Create', 'Next')
    }

    It 'reads an Expected Result with a qualifier before the colon' {
        $script:Results.steps[1].expected | Should -Be 'The share is saved.'
    }
}

# Discovery-time state for the per-guide cases. The file-level BeforeAll does not run at
# discovery, so these are defined here at file scope, as Guide-Step-Numbering.Tests.ps1 does.
$DiscoveryRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$DiscoveryParser   = Join-Path $DiscoveryRepoRoot 'tools/guide-drift/parse.py'
$DiscoveryPython   = if ($IsWindows) { 'python' } else { 'python3' }

# Drops fenced code the way parse.py does: a fence closes only on a run of its own character at
# least as long as the opener, with nothing after the run but whitespace.
function ConvertTo-UnfencedText {
    param([string]$Text)
    $fence = $null
    $kept = foreach ($line in ($Text -split '\r?\n')) {
        $m = [regex]::Match($line, '^[ \t]*(`{3,}|~{3,})(.*)$')
        if ($null -eq $fence) {
            if ($m.Success) { $fence = $m.Groups[1].Value } else { $line }
        } elseif ($m.Success -and $m.Groups[1].Value[0] -eq $fence[0] -and
                  $m.Groups[1].Value.Length -ge $fence.Length -and -not $m.Groups[2].Value.Trim()) {
            $fence = $null
        }
    }
    $kept -join "`n"
}

# The step regex is the one tests/Guide-Step-Numbering.Tests.ps1 uses, narrowed to '###', so the
# parser is held to the same reading of a guide as the numbering test.
$GuideCases = Get-ChildItem -Path $DiscoveryRepoRoot -Directory -Filter 'module-*' |
    Get-ChildItem -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+-' } |
    ForEach-Object {
        $num   = [regex]::Match($_.Name, '^\d+\.\d+').Value
        $guide = Join-Path $_.FullName "lab-guide-$num.md"
        if (-not (Test-Path -LiteralPath $guide)) { return }
        $text  = Get-Content -Raw -LiteralPath $guide
        $text  = ConvertTo-UnfencedText -Text $text
        # Closed HTML comments only (non-greedy): an unclosed '<!--' leaves later headings counted
        # here while the parser hides them, so the id comparison below catches it.
        $text  = [regex]::Replace($text, '(?s)<!--.*?-->', '')
        $headingIds = @([regex]::Matches($text, '(?m)^###[ \t]+Step[ \t]+(\d+\.\d+\.\d+):') | ForEach-Object { $_.Groups[1].Value })
        $out = [System.IO.Path]::GetTempFileName()
        try {
            $stderr = & $DiscoveryPython $DiscoveryParser $guide --out $out --repo-root $DiscoveryRepoRoot 2>&1
            $exit   = $LASTEXITCODE
            $parsed = if ($exit -eq 0) { Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json }
        } finally { Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue }
        # Every text the runner acts on: action and navigation labels, field labels and values,
        # tag names and values.
        $texts = @($parsed.steps | ForEach-Object { $_.items } | ForEach-Object {
            $item = $_
            switch ($item.kind) {
                'field' { $item.label; $item.value }
                'tag'   { $item.name; $item.value }
                default { $item.labels }
            }
        })
        @{
            lab         = $num
            exitCode    = $exit
            output      = ($stderr -join "`n")
            headingIds  = $headingIds
            parsedIds   = @($parsed.steps.id)
            residue     = @($texts | Where-Object { $_ -match '\*\*|`|<!--' })
            guidePath   = $parsed.guide
        }
    }

Describe 'parse.py - every lab guide' {
    It 'has guides to check' -ForEach @(@{ count = @($GuideCases).Count }) {
        $count | Should -Be 17
    }

    It "'<lab>' parses" -ForEach $GuideCases {
        $exitCode | Should -Be 0 -Because $output
    }

    It "'<lab>' yields the same step ids as its headings, in order" -ForEach $GuideCases {
        $parsedIds | Should -Be $headingIds
    }

    It "'<lab>' reports a guide path relative to the repo root" -ForEach $GuideCases {
        $guidePath | Should -Match "^module-\d[^/]*/\d+\.\d+-[^/]+/lab-guide-$lab\.md$"
    }

    It "'<lab>' yields labels and values without markup or comment residue" -ForEach $GuideCases {
        $residue | Should -BeNullOrEmpty
    }
}

Describe 'parse.py - lab 1.1, the first recorded lab' {
    BeforeAll {
        $guide = Join-Path $script:RepoRoot 'module-1-identities-governance/1.1-entra-users-groups/lab-guide-1.1.md'
        $out   = Join-Path $TestDrive 'lab-1.1.json'
        & $script:Python $script:Parser $guide --out $out --repo-root $script:RepoRoot
        $script:Lab11 = Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json
    }

    It 'reads step 1.1.1 as one search for Microsoft Entra ID' {
        $step = $script:Lab11.steps | Where-Object id -eq '1.1.1'
        @($step.items.kind) | Should -Be @('search')
        @($step.items[0].labels) | Should -Be @('Microsoft Entra ID')
        $step.items[0].scope | Should -Be 'global'
    }

    It 'reads every search of lab 1.1 as the Portal''s global search' {
        $searches = @($script:Lab11.steps | ForEach-Object { $_.items } | Where-Object kind -eq 'search')
        $searches.Count | Should -BeGreaterThan 0
        @($searches | Where-Object scope -ne 'global') | Should -BeNullOrEmpty
    }

    It 'reads step 1.1.6 as the way back to Entra, + New group and four fields' {
        $step = $script:Lab11.steps | Where-Object id -eq '1.1.6'
        @($step.items.kind) | Should -Be @('search', 'navigation', 'action', 'field', 'field', 'field', 'field')
        @($step.items[0].labels) | Should -Be @('Microsoft Entra ID')
        @($step.items[1].labels) | Should -Be @('Groups', 'All groups')
        @($step.items[2].labels) | Should -Be @('+ New group')
        @(($step.items | Where-Object kind -eq 'field').label) | Should -Be @('Group type', 'Group name', 'Group description', 'Membership type')
    }

    It 'reads step 1.1.7 as picking the member in the New Group form, then Create and Refresh' {
        $step = $script:Lab11.steps | Where-Object id -eq '1.1.7'
        @($step.items | ForEach-Object { $_.labels }) | Should -Be @('No members selected', 'Malfurion Stormrage', 'Select', 'Create', 'Refresh')
    }

    It 'ends step <id> with the action that shows its Expected Result (#218)' -ForEach @(
        @{ id = '1.1.2'; label = 'Refresh' }
        @{ id = '1.1.9'; label = 'Refresh' }
        @{ id = '1.1.10'; label = 'Properties' }
    ) {
        $last = @(($script:Lab11.steps | Where-Object id -eq $id).items)[-1]
        $last.kind | Should -Be 'action'
        @($last.labels) | Should -Be @($label)
    }

    It 'keeps the guest invitation value of step 1.1.5 verbatim for the recording to override' {
        $email = ($script:Lab11.steps | Where-Object id -eq '1.1.5').items | Where-Object label -eq 'Email'
        $email.value | Should -Be 'istormrage@illidari.com'
    }

    It 'marks only the three [yourtenant] addresses literal: false, for the recording''s placeholder to resolve (#202)' {
        $marked = @($script:Lab11.steps | ForEach-Object { $_.items } | Where-Object { $_.kind -eq 'field' -and $_.literal -eq $false })
        @($marked.value) | Should -Be @('malfurion.stormrage@[yourtenant].onmicrosoft.com',
            'khadgar.archmage@[yourtenant].onmicrosoft.com', 'chromie.timewalker@[yourtenant].onmicrosoft.com')
    }

    It 'marks every one of the 14 steps as portal' {
        @($script:Lab11.steps | Where-Object portal).Count | Should -Be 14
    }
}

Describe 'parse.py - values that are instructions, placeholders or check box states (#202)' {
    BeforeAll {
        # The field a guide gives `label` in step `stepId`.
        function Get-GuideField {
            param([string]$Guide, [string]$StepId, [string]$Label)
            $out = Join-Path $TestDrive ([guid]::NewGuid().ToString() + '.json')
            & $script:Python $script:Parser (Join-Path $script:RepoRoot $Guide) --out $out --repo-root $script:RepoRoot
            $steps = (Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json).steps
            @(($steps | Where-Object id -eq $StepId).items | Where-Object { $_.kind -eq 'field' -and $_.label -ceq $Label })[0]
        }
    }

    It "marks '<label>' of step <step> literal: false" -ForEach @(
        @{ guide = 'module-1-identities-governance/1.3-governance/lab-guide-1.3.md'; step = '1.3.5'; label = 'Scope'; value = 'Click the "..." button' }
        @{ guide = 'module-1-identities-governance/1.3-governance/lab-guide-1.3.md'; step = '1.3.8'; label = 'Allowed locations'; value = 'Select:' }
        @{ guide = 'module-2-networking/2.3-name-resolution/lab-guide-2.3.md'; step = '2.3.2'; label = 'IP address'; value = '[IP of dev-skycraft-swc-lb-pip]' }
    ) {
        $field = Get-GuideField -Guide $guide -StepId $step -Label $label
        $field.value   | Should -Be $value
        $field.literal | Should -BeFalse
        $field.PSObject.Properties.Name | Should -Contain 'literal'
    }

    It "keeps the check box state '<value>' of step <step> a literal, for the runner to apply to the check box" -ForEach @(
        @{ guide = 'module-3-compute/3.3-containers/lab-guide-3.3.md'; step = '3.3.8'; label = 'Insecure connections'; value = 'Uncheck' }
        @{ guide = 'module-5-monitoring-maintenance/5.3-network-monitoring/lab-guide-5.3.md'; step = '5.3.5'; label = 'Enable traffic analytics'; value = 'checked' }
    ) {
        $field = Get-GuideField -Guide $guide -StepId $step -Label $label
        $field.value | Should -Be $value
        $field.PSObject.Properties.Name | Should -Not -Contain 'literal'
    }
}


Describe 'parse.py - lab 1.2, global and in-blade searches' {
    BeforeAll {
        $guide = Join-Path $script:RepoRoot 'module-1-identities-governance/1.2-rbac/lab-guide-1.2.md'
        $out   = Join-Path $TestDrive 'lab-1.2.json'
        & $script:Python $script:Parser $guide --out $out --repo-root $script:RepoRoot
        $script:Lab12 = Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json
    }

    It 'reads "In **Azure Portal**, search for" in step 1.2.1 as the global search for Resource groups' {
        $item = ($script:Lab12.steps | Where-Object id -eq '1.2.1').items[0]
        $item.kind | Should -Be 'search'
        $item.scope | Should -Be 'global'
        @($item.labels) | Should -Be @('Resource groups')
    }

    It 'reads the role and member searches of step 1.2.4 as searches in the open blade' {
        $searches = @(($script:Lab12.steps | Where-Object id -eq '1.2.4').items | Where-Object kind -eq 'search')
        @($searches | ForEach-Object { $_.labels }) | Should -Be @('Owner', 'Malfurion Stormrage')
        @($searches.scope) | Should -Be @('blade', 'blade')
    }
}

Describe 'parse.py - lab 1.3, a lock type is a field, not a click on Delete' {
    BeforeAll {
        $guide = Join-Path $script:RepoRoot 'module-1-identities-governance/1.3-governance/lab-guide-1.3.md'
        $out   = Join-Path $TestDrive 'lab-1.3.json'
        & $script:Python $script:Parser $guide --out $out --repo-root $script:RepoRoot
        $script:Lab13 = Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json
    }

    It 'reads step 1.3.12 as the lock form: name, type and notes as fields' {
        $step = $script:Lab13.steps | Where-Object id -eq '1.3.12'
        @($step.items.kind) | Should -Be @('action', 'navigation', 'field', 'field', 'field', 'action')
        @(($step.items | Where-Object kind -eq 'field').label) | Should -Be @('Lock name', 'Lock type', 'Notes')
        ($step.items | Where-Object label -eq 'Lock type').value | Should -Be 'Delete'
        @($step.items | ForEach-Object { $_.labels }) | Should -Not -Contain 'Delete'
    }
}

Describe 'parse.py - labs 2.2 and 4.1, lists to verify are checks, not fields (#224)' {
    BeforeAll {
        $script:CheckLabs = @{}
        foreach ($guide in 'module-2-networking/2.2-secure-access/lab-guide-2.2.md',
                           'module-4-storage/4.1-storage-accounts/lab-guide-4.1.md') {
            $lab = [regex]::Match($guide, 'lab-guide-(\d+\.\d+)\.md$').Groups[1].Value
            $out = Join-Path $TestDrive "checks-$lab.json"
            & $script:Python $script:Parser (Join-Path $script:RepoRoot $guide) --out $out --repo-root $script:RepoRoot
            $script:CheckLabs[$lab] = Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json
        }
    }

    It 'reads step <id> as <labels> and the list to verify as its Expected Result' -ForEach @(
        @{ lab = '2.2'; id = '2.2.11'; labels = @('Bastions', 'platform-skycraft-swc-bas')
           expected = 'Bastion is operational and ready to provide secure connectivity to VMs in all peered VNets. Status: Succeeded; Virtual network: platform-skycraft-swc-vnet; Subnet: AzureBastionSubnet; Public IP: platform-skycraft-swc-bas-pip' }
        @{ lab = '4.1'; id = '4.1.8'; labels = @('Security + networking', 'Encryption')
           expected = 'Encryption type: Microsoft-managed keys; This is always enabled and cannot be disabled' }
        @{ lab = '4.1'; id = '4.1.10'; labels = @('Configuration')
           expected = 'Minimum TLS version: 1.2; Secure transfer required: Enabled' }
        @{ lab = '4.1'; id = '4.1.11'; labels = @('Configuration')
           expected = 'Allow Blob anonymous access: Disabled' }
    ) {
        $step = $script:CheckLabs[$lab].steps | Where-Object id -eq $id
        @($step.items | Where-Object kind -eq 'field') | Should -BeNullOrEmpty
        @($step.items | ForEach-Object { $_.labels }) | Should -Be $labels
        $step.expected | Should -Be $expected
    }

    It 'reads the list after the Expected Result of step 4.1.2 into its text, not as a Name field' {
        $step = $script:CheckLabs['4.1'].steps | Where-Object id -eq '4.1.2'
        $step.expected | Should -Be ('Deployment succeeds in 30-60 seconds. Navigate to the resource to verify: ' +
            'Name: platformskycraftswcsa; Location: Sweden Central; Replication: Geo-redundant storage (GRS); Access tier: Hot')
        @($step.items | Where-Object { $_.kind -eq 'field' -and $_.label -ceq 'Name' }) | Should -BeNullOrEmpty
        @($step.items)[-1].labels | Should -Be @('Create')
    }
}

Describe 'parse.py - only the first option of a step is read, in every lab guide' {
    BeforeAll {
        # Bold spans of each step, by where they sit: 'first' (before the first Option heading, or
        # in Option 1 or A) and 'other' (Option 2, B or later, up to the next step). Fenced code is
        # skipped as parse.py skips it; 'Expected Result' is a caption, not a label. A bold span
        # that only another option uses must never reach the parser's labels, fields or tags.
        # Lab 4.3 has Option headings in every step but its other options hold only code; today
        # the check bites in 3.2.1, whose Option A is CLI-only and whose Option B is the Portal.
        $script:OtherOnly = [System.Collections.Generic.List[hashtable]]::new()
        $script:Parsed = @{}
        $guides = Get-ChildItem -Path $script:RepoRoot -Directory -Filter 'module-*' |
            Get-ChildItem -Directory | Where-Object { $_.Name -match '^\d+\.\d+-' } |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter 'lab-guide-*.md' }
        foreach ($guide in $guides) {
            $lab = [regex]::Match($guide.Name, '\d+\.\d+').Value
            $out = Join-Path $TestDrive "lab-$lab.json"
            & $script:Python $script:Parser $guide.FullName --out $out --repo-root $script:RepoRoot
            $script:Parsed[$lab] = Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json

            $first = @{}; $other = @{}
            $step = $null; $zone = 'first'; $fence = $null
            foreach ($line in (Get-Content -LiteralPath $guide.FullName -Encoding utf8)) {
                $m = [regex]::Match($line, '^[ \t]*(`{3,}|~{3,})(.*)$')
                if ($null -eq $fence) {
                    if ($m.Success) { $fence = $m.Groups[1].Value; continue }
                } else {
                    if ($m.Success -and $m.Groups[1].Value[0] -eq $fence[0] -and
                        $m.Groups[1].Value.Length -ge $fence.Length -and -not $m.Groups[2].Value.Trim()) { $fence = $null }
                    continue
                }
                if ($line -match '^###\s+Step\s+(\d+\.\d+\.\d+):') {
                    $step = $Matches[1]; $zone = 'first'
                    $first[$step] = [System.Collections.Generic.List[string]]::new()
                    $other[$step] = [System.Collections.Generic.List[string]]::new()
                    continue
                }
                if ($line -match '^##\s') { $step = $null; continue }
                if (-not $step) { continue }
                if ($line -match '^####\s+Option\s+(\d+|[A-Z])\b') {
                    $zone = if ($Matches[1] -in '1', 'A') { 'first' } else { 'other' }
                    continue
                }
                foreach ($bold in [regex]::Matches($line, '\*\*(.+?)\*\*')) {
                    if ($zone -eq 'first') { $first[$step].Add($bold.Groups[1].Value) } else { $other[$step].Add($bold.Groups[1].Value) }
                }
            }
            foreach ($id in $other.Keys) {
                foreach ($bold in ($other[$id] | Select-Object -Unique)) {
                    if ($bold -cne 'Expected Result' -and $first[$id] -cnotcontains $bold) {
                        $script:OtherOnly.Add(@{ lab = $lab; step = $id; bold = $bold })
                    }
                }
            }
        }
    }

    It 'finds bold text that only a later option uses, in lab 4.3 and in step 3.2.1' {
        @($script:OtherOnly | Where-Object { $_.lab -eq '4.3' }).Count | Should -BeGreaterThan 0
        @($script:OtherOnly | Where-Object { $_.step -eq '3.2.1' }).Count | Should -BeGreaterThan 0
    }

    It 'reads no label, field or tag from the body of Option 2, B or later' {
        $leaks = @(foreach ($case in $script:OtherOnly) {
                $parsedStep = $script:Parsed[$case.lab].steps | Where-Object id -eq $case.step
                $texts = @($parsedStep.items | ForEach-Object {
                        $item = $_      # inside switch, $_ is the kind, not the item
                        switch ($item.kind) { 'field' { $item.label } 'tag' { $item.name } default { $item.labels } }
                    })
                if ($texts -ccontains $case.bold) { "step $($case.step): '$($case.bold)'" }
            })
        $leaks | Should -BeNullOrEmpty -Because ($leaks -join '; ')
    }
}
