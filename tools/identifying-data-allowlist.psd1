@{
    # Reviewed allowlist of tools/Test-IdentifyingData.ps1 (issue #523). Every entry carries a
    # Reason; the gate refuses an entry without one. Add an entry only for a value that names no
    # real environment, person or organization. A real id belongs in the private notes, not here.

    # Built-in Azure ids, checked against the provider on 2026-11-12 (az role definition list,
    # az policy definition show): they are the same in every tenant.
    GuidValue       = @(
        @{ Value = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; Reason = 'built-in role Owner' }
        @{ Value = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; Reason = 'built-in role Contributor' }
        @{ Value = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; Reason = 'built-in role Reader' }
        @{ Value = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'; Reason = 'built-in role Storage Blob Data Contributor' }
        @{ Value = '00482a5a-887f-4fb3-b363-3b7fe8e74483'; Reason = 'built-in role Key Vault Administrator' }
        @{ Value = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'; Reason = 'built-in role Storage Blob Data Owner' }
        @{ Value = 'e5e2a7ff-d759-4cd2-bb51-3152d37e2eb1'; Reason = 'built-in role Storage Account Backup Contributor' }
        @{ Value = '96670d01-0a4d-4649-9c89-2d3abc0a5025'; Reason = 'built-in policy definition Require a tag on resource groups' }
        @{ Value = '1e30110a-5ceb-460c-a204-c1c3969c6d62'; Reason = 'built-in policy definition Require a tag and its value on resources' }
        @{ Value = 'ea3f2387-9b95-492a-a190-fcdc54f7b070'; Reason = 'built-in policy definition Inherit a tag from the resource group if missing' }
        @{ Value = 'cd3aa116-8754-49c9-a813-ad46512ece54'; Reason = 'built-in policy definition Inherit a tag from the resource group' }
        @{ Value = 'e56962a6-4747-49cd-b67b-bf8b01975c4c'; Reason = 'built-in policy definition Allowed locations' }
        @{ Value = 'e765b5de-1225-4ba3-bd56-1ac6695af988'; Reason = 'built-in policy definition Allowed locations for resource groups' }
        @{ Value = '262044b1-e2ce-469f-a196-69ab7ada62d3'; Reason = 'application id of the Backup Management Service app, the same in every tenant (Lab 5.2 guide)' }
        @{ Value = '00000003-0000-0000-c000-000000000000'; Reason = 'application id of Microsoft Graph, the same in every tenant (TROUBLESHOOTING.md)' }
        @{ Value = '9188040d-6c67-4c5b-b112-36a304b66dad'; Reason = 'Microsoft''s fixed tenant id for personal Microsoft accounts, compared against in New-LabUser.ps1' }
        # Invented values in tests and fixtures, none taken from an environment.
        @{ Value = '11111111-2222-3333-4444-555555555555'; Reason = 'invented sequence used as a stub object id in tests' }
        @{ Value = '99999999-2222-3333-4444-555555555555'; Reason = 'invented sequence used as a second stub object id in tests' }
        @{ Value = '11111111-2222-4333-8444-555555555555'; Reason = 'invented sequence used as a stub object id in the guide-drift tests' }
        @{ Value = '00000000-1111-2222-3333-444444444444'; Reason = 'invented sequence used as a stub subscription id in tests' }
        @{ Value = '66666666-7777-8888-9999-000000000000'; Reason = 'invented sequence used as a stub object id in the redaction tests' }
        @{ Value = '99999999-8888-7777-6666-555555555555'; Reason = 'invented sequence used as a stub tenant id in the redaction tests' }
        @{ Value = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; Reason = 'invented sequence used as a stub subscription id in the redaction tests' }
        @{ Value = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d'; Reason = 'invented sequence used as a stub tenant id in the guide-drift redaction tests' }
        @{ Value = '9f8e7d6c-5b4a-4c3d-8e2f-1a0b9c8d7e6f'; Reason = 'invented sequence used as a stub object id in the guide-drift redaction tests' }
    )

    # Placeholder shapes: a GUID built from one repeated digit, or zeros with a short counter.
    GuidPattern     = @(
        @{ Value = '^([0-9a-f])\1{7}-\1{4}-\1{4}-\1{4}-\1{12}$'; Reason = 'one digit repeated, such as 00000000-0000-0000-0000-000000000000: obviously not an id' }
        @{ Value = '^([0-9a-f])\1{7}-0{4}-0{4}-0{4}-0{8}[0-9a-f]{4}$'; Reason = 'one repeated digit, then zeros and a short counter (aaaaaaaa-0000-0000-0000-000000000001): a test fixture id' }
    )

    EmailValue      = @(
        @{ Value = 'smith.john@company.com'; Reason = 'invented address in a guide example' }
        @{ Value = 'jsmith@example.com'; Reason = 'invented address in a guide example' }
        @{ Value = 'illidan@externalcompany.com'; Reason = 'historic CHANGELOG line about the guest address of an old release' }
        @{ Value = 'x@gmail.com'; Reason = 'invented address in a redaction test of the guide-drift tool' }
        @{ Value = 'someone@fabrikam.com'; Reason = 'invented address (Fabrikam is Microsoft''s sample company) in the guide-drift tests' }
        @{ Value = 'chromie@contoso.com'; Reason = 'invented address (Contoso is Microsoft''s sample company) in the guide-drift tests' }
        @{ Value = 'group@2x.png'; Reason = 'an image file name that looks like an address, used by the guide-drift redaction tests' }
        @{ Value = 'p@ss.w0rd'; Reason = 'a made-up password inside a connection-string redaction test' }
        @{ Value = 'a@b.cocontoso'; Reason = 'redaction test input that is deliberately not an address' }
        @{ Value = 'contoso@b.co'; Reason = 'redaction test input that is deliberately not an address' }
    )

    # A domain entry allows every address at that domain; '*.example' allows every address under
    # that top level domain.
    EmailDomain     = @(
        @{ Value = 'example.com'; Reason = 'reserved for documentation (RFC 2606)' }
        @{ Value = 'example.org'; Reason = 'reserved for documentation (RFC 2606)' }
        @{ Value = 'sub.example.org'; Reason = 'subdomain of a domain reserved for documentation' }
        @{ Value = '*.example'; Reason = 'the .example top level domain is reserved for documentation (RFC 2606)' }
        @{ Value = '*.invalid'; Reason = 'the .invalid top level domain is reserved and never resolves (RFC 2606)' }
        @{ Value = '*.test'; Reason = 'the .test top level domain is reserved for testing (RFC 2606)' }
        @{ Value = 'contoso.onmicrosoft.com'; Reason = 'Contoso, Microsoft''s sample tenant name, used as the lab''s stand-in initial domain' }
        @{ Value = 'illidari.com'; Reason = 'the lab''s own fictional guest domain (Lab 1.1 Step 1.1.5)' }
    )

    UserPathName    = @(
        @{ Value = 'Public'; Reason = 'Windows shared profile folder, no person' }
        @{ Value = 'Default'; Reason = 'Windows default profile folder, no person' }
    )

    # Binary files this check cannot read. An unlisted binary extension fails the gate.
    BinaryExtension = @(
        @{ Value = 'png'; Reason = 'screenshots: the pixels cannot be scanned; the review of screenshots stays manual (#486)' }
        @{ Value = 'pdf'; Reason = 'docs/az-104-study-guide.pdf, a document the maintainer reviewed by hand; not readable by this check' }
    )
}
