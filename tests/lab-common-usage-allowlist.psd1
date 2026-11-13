@{
    # Lab scripts excused from a rule of tests/Lab-Common-Usage.Tests.ps1. Each entry names its
    # rule; an entry whose script no longer violates it fails the suite, so none outlives its fix.
    # Rules: NoImport, DirectSetShouldExit, BareCountExit.
    Entries = @(
        @{
            Rule   = 'NoImport'
            File   = 'module-1-identities-governance/1.3-governance/scripts/LabPolicyAssignment.ps1'
            Reason = 'Recorded when the gate was introduced, #301 moves the script over. A helper the lab scripts dot-source; it ends nothing and the script that dot-sources it imports the module.'
        }
    )
}
