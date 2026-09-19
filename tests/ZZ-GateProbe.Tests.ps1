<#
.SYNOPSIS
    Throwaway probe for issue #128: one deliberately failing test.

.DESCRIPTION
    Exists only to prove in CI that the Repository Standards (Pester) job turns red
    when a test fails. This branch is never merged.
#>
Describe 'SkyCraft CI - gate probe (#128)' {
    It 'fails on purpose so the Pester job must go red' {
        $true | Should -BeFalse -Because 'issue #128: a failing test must fail the job'
    }
}
