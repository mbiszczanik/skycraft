<#
.SYNOPSIS
    Pester 5 tests for tools/guide-drift/parse.py, the guide-to-steps parser of the guide drift tool.

.DESCRIPTION
    The parser is Python standard library only, so this suite runs on the ubuntu-latest runner
    without a browser. Two kinds of test:

      FIXTURES - small guides written here, parsed through a temp file, asserting the rules of
      issue #189: only '### Step X.Y.N:' sections are read; fenced code is skipped; where a step
      has '#### Option N:' headings only Option 1 is read (plus the step's Expected Result);
      bold spans that are not UI elements are dropped; 'A -> B' chains become navigation;
      Field | Value tables become fields; images are collected with their pixel width.

      THE 17 GUIDES - every module-*/X.Y-*/lab-guide-X.Y.md parses, its step ids match its
      headings in order, and every step marked portal has at least one label. This does NOT
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
        $script:Core.steps[0].items[2].kind | Should -Be 'action'
        @($script:Core.steps[0].items[3].labels) | Should -Be @('Curly Label')
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
        # A PNG header is enough: parse.py reads the width from IHDR (bytes 16..19) and never decodes.
        function New-PngFixture {
            param([string]$Path, [int]$Width)
            $widthBytes = [System.BitConverter]::GetBytes([int32]$Width)
            [array]::Reverse($widthBytes)   # IHDR is big-endian
            $bytes = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52) +
                     $widthBytes + [byte[]](0, 0, 0, 1, 8, 2, 0, 0, 0)
            [System.IO.File]::WriteAllBytes($Path, $bytes)
        }

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

| Name   | Value        | Notes                       |
| ------ | ------------ | --------------------------- |
| Region | `westeurope` | three columns, still a form |

1. Click **Review + create**
'@
        $dir = Join-Path $TestDrive 'tables'
        New-Item -ItemType Directory -Path (Join-Path $dir 'images') -Force | Out-Null
        New-PngFixture -Path (Join-Path $dir 'images/Step-9.9.1.png') -Width 861
        New-PngFixture -Path (Join-Path $dir 'images/Step-9.9.1b.png') -Width 2279
        $script:Table = ConvertFrom-GuideFixture -Markdown $tableFixture -Directory $dir
    }

    It 'turns Field | Value rows into fields, stripping markup from label and value' {
        $fields = @($script:Table.steps[0].items | Where-Object kind -eq 'field')
        @($fields.label) | Should -Be @('Group type', 'Group name', 'Tier', 'Region')
        @($fields.value) | Should -Be @('Security', 'SkyCraft-Admins', 'Hot', 'Sweden Central')
    }

    It 'keeps actions before and after the table in document order' {
        @($script:Table.steps[0].items.kind) | Should -Be @('action', 'field', 'field', 'field', 'field', 'action')
        @($script:Table.steps[0].items[5].labels) | Should -Be @('Create')
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

    It 'collects the images a step references, with and without "./"' {
        @($script:Table.steps[0].images) | Should -Be @('images/Step-9.9.1.png', 'images/Step-9.9.1b.png')
    }

    It 'lists every PNG under images/ with its pixel width' {
        $widths = @{}
        foreach ($image in $script:Table.images) { $widths[$image.path] = $image.width }
        $widths['images/Step-9.9.1.png']  | Should -Be 861
        $widths['images/Step-9.9.1b.png'] | Should -Be 2279
    }
}
