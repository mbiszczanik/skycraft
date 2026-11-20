@{
    # Allowlist of tools/Test-LabConsistency.ps1 (issues #363, #364, #362). Every entry names its check,
    # the file, a Match (text of the evidence line) and a Reason. An entry that matches no finding fails
    # the gate, so fixing a finding means deleting its entry.
    Allow = @(
        @{ Check = 'NullUnsafeComparison'; File = 'module-2-networking/2.1-virtual-networks/scripts/Test-Lab.ps1'; Match = '$Subnet.DefaultOutboundAccess -eq $false'; Reason = 'Recorded when the lint was introduced (2026-11-12, #363), not yet reviewed against a Portal-built resource: an unset (null) property passes or fails here by accident. Fix with -not or -ne $true in its own pull request, with a live check.' }
        @{ Check = 'NullUnsafeComparison'; File = 'module-2-networking/2.3-name-resolution/scripts/Test-Lab.ps1'; Match = '$hubLink.RegistrationEnabled -eq $false'; Reason = 'Recorded when the lint was introduced (2026-11-12, #363), not yet reviewed against a Portal-built resource: an unset (null) property passes or fails here by accident. Fix with -not or -ne $true in its own pull request, with a live check.' }
        @{ Check = 'NullUnsafeComparison'; File = 'module-4-storage/4.1-storage-accounts/scripts/Test-Lab.ps1'; Match = '$sa.AllowBlobPublicAccess -eq $false'; Reason = 'Recorded when the lint was introduced (2026-11-12, #363), not yet reviewed against a Portal-built resource: an unset (null) property passes or fails here by accident. Fix with -not or -ne $true in its own pull request, with a live check.' }
        @{ Check = 'NullUnsafeComparison'; File = 'module-4-storage/4.2-blob-storage/scripts/Test-Lab.ps1'; Match = '$prodSa.AllowBlobPublicAccess -eq $false'; Reason = 'Recorded when the lint was introduced (2026-11-12, #363), not yet reviewed against a Portal-built resource: an unset (null) property passes or fails here by accident. Fix with -not or -ne $true in its own pull request, with a live check.' }
        @{ Check = 'NullUnsafeComparison'; File = 'module-4-storage/4.2-blob-storage/scripts/Test-Lab.ps1'; Match = '$devSa.AllowBlobPublicAccess -eq $false'; Reason = 'Recorded when the lint was introduced (2026-11-12, #363), not yet reviewed against a Portal-built resource: an unset (null) property passes or fails here by accident. Fix with -not or -ne $true in its own pull request, with a live check.' }
    )
}
