<#
    The lab cycle manifest - the only place in the orchestrator that holds lab-specific knowledge.

    ONE PHASE PER LAB, sixteen of them, in the order issue #73 states: 1.2, 1.3, 2.1, 2.2, 2.3,
    3.1, 3.2, 3.3, 3.4, 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3. That is the order the v0.8.0 live cycle
    ran and reported 16/16 green, so it is a measured order rather than a proposed one.

    Every argument below is checked against the target script's own parameter block by
    tests/LabCycle.Tests.ps1, and every .bicepparam in the repository must appear exactly once -
    as a phase's ParamFile or as an entry in CompileOnly carrying a reason. Add a parameter file
    to the repository without adding it here and that test fails; that is what makes the phase
    count a measured fact rather than a claim.

    PATHS. 'Lab' is relative to the repository root. Every phase runs with its own scripts/ folder
    as the working directory.

    ARGUMENTS ARE SPARSE, AND DELIBERATELY SO. After the AVM conversion (PRs #84-#102) each lab
    ships a single bicep/parameters/main.bicepparam - lab 3.1 and lab 1.2 are the only exceptions -
    and no deploy script declares -TemplateParameterFile any more. Environment selection is a
    parameter with a default that already matches what the cycle wants, so most phases pass
    nothing at all. Passing a value equal to the script's own default would be four more places to
    keep agreeing about a name, so a phase names only what it actually needs to change:

      4.1  -All          deploys dev, prod and platform in one invocation. Its Test-Lab already
                         defaults to -Environment all, so the validator matches without an argument.
      5.1  -OpsEmail     mandatory on that script, and the only argument the orchestrator takes
                         from its caller. -Force answers the confirmation prompt.
      3.2, 5.2, 5.3      -Force, for the same reason.

    HOW A PHASE ANSWERS A PROMPT IT CANNOT BE GIVEN A SWITCH FOR. Lab 2.2's Deploy-Bicep.ps1 asks
    'Do you want to deploy Azure Bastion? (y/N)' through Read-Host and declares no -Force. It is
    the one prompt in the chain with no parameter behind it, so the phase answers it on stdin -
    see StdinAnswers. The answer is empty, which the script reads as 'no': Bastion is the single
    resource in this repository with a standing hourly cost (~$140/month), and an unattended cycle
    must not be the thing that starts it.

    Labs 3.2, 5.1, 5.2 and 5.3 used to need the same treatment. They no longer do - issues #103 and
    the module-5 work gave each of them a real -Force - so the workaround is down to one lab, and
    the moment 2.2 grows a -DeployBastion switch on its deploy script it can go entirely.

    HOW MUCH TO TRUST AN EDGE. DependsOn entries come from two sources and do not carry the same
    confidence, which matters when a live phase fails and someone has to decide whether the lab is
    wrong or the graph is.

      VERIFIED - a hard prerequisite gate was read in the lab's own deploy script, one that prints
      [ERROR] and exits 1. All of module 5, read on 2026-08-30 against this tree:
        5.1 gates on the platform resource group, on at least one lab-3.2 VM, and on a storage
            account in the platform group;
        5.2 gates on the platform resource group and on 5.1's Log Analytics workspace;
        5.3 gates on the platform resource group, lab 2.1's prod VNet, lab 4.1's platform storage
            account, 5.1's workspace, and on TWO distinct lab-3.2 VMs for Connection Monitor.
      Those phases carry a 'gate:' note. Note that 5.1's and 5.3's VM checks are gates in this
      tree - they exit 1 - which is a change from the pre-AVM scripts, where a missing VM only
      warned.

      DECLARED - follows each lab's stated prerequisites, with no gate read to confirm it.
      Everything else. Reasonable, and re-tested by every live run.

    TIMEOUTS ARE ESTIMATES, not measurements: 20 minutes by default, 40 for the VM phases, 30 for
    containers and module 5. A phase killed by one is far more likely to mean the estimate was low
    than that the lab hung, which is why a timeout gets its own status rather than being reported
    as an ordinary failure.
#>

@{
    Phases = @(

        # -- Module 1 ------------------------------------------------------------------------
        @{
            Id           = '1.2'
            Lab          = 'module-1-identities-governance/1.2-rbac'
            ParamFile    = 'bicep/parameters/resource-groups.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @()
            TimeoutMs    = 1200000
            StdinAnswers = $null
            Excluded     = $null
            # The three resource groups every later lab deploys into. Root of the graph.
            #
            # Its validator also checks role assignments for Entra principals that lab 1.1
            # creates. That is left live rather than excluded: on a subscription whose identity
            # can also see Entra ID the checks pass, and baking one tenant's identity split into
            # the manifest would hide a real failure everywhere else. If those five checks fail on
            # your subscription, see TROUBLESHOOTING.md - the split is an environment fact, not a
            # lab defect.
        }
        @{
            Id           = '1.3'
            Lab          = 'module-1-identities-governance/1.3-governance'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('1.2')
            TimeoutMs    = 1200000
            StdinAnswers = $null
            Excluded     = $null
            # Locks and subscription-scope policy assignments. Both outlive the resource groups
            # they guard, which is why teardown takes this lab FIRST rather than last: a
            # CanNotDelete lock blocks every delete below it.
        }

        # -- Module 2 ------------------------------------------------------------------------
        @{
            Id           = '2.1'
            Lab          = 'module-2-networking/2.1-virtual-networks'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('1.2')
            TimeoutMs    = 1200000
            StdinAnswers = $null
            Excluded     = $null
        }
        @{
            Id           = '2.2'
            Lab          = 'module-2-networking/2.2-secure-access'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('2.1')
            TimeoutMs    = 1200000
            # The empty line answers 'Do you want to deploy Azure Bastion? (y/N)' with the default,
            # which is no. Fed rather than left to end-of-file on purpose: Read-Host on a closed
            # stdin throws under $ErrorActionPreference = 'Stop', and the phase would fail on the
            # prompt rather than on anything to do with the lab.
            StdinAnswers = @('')
            Excluded     = $null
        }
        @{
            Id           = '2.3'
            Lab          = 'module-2-networking/2.3-name-resolution'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('2.1')
            TimeoutMs    = 1200000
            StdinAnswers = $null
            Excluded     = $null
        }

        # -- Module 3 ------------------------------------------------------------------------
        @{
            Id           = '3.1'
            Lab          = 'module-3-compute/3.1-infrastructure-as-code'
            ParamFile    = 'bicep/parameters/dev.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('1.2')
            TimeoutMs    = 1800000
            StdinAnswers = $null
            Excluded     = $null
            # Deploys at subscription scope and declares the three resource groups itself, so it
            # does not strictly need 1.2. The edge is declared anyway: without it this phase joins
            # the first ready batch and the run order stops matching the one issue #73 states and
            # the v0.8.0 cycle measured.
            #
            # -Environment defaults to 'dev' on both the deploy script and the validator, so the
            # phase passes neither. prod.bicepparam is in CompileOnly below.
        }
        @{
            Id           = '3.2'
            Lab          = 'module-3-compute/3.2-virtual-machines'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            # -Force skips the deploy confirmation. Before #103 this script read stdin, printed
            # 'Deployment cancelled.' and exited 0, so an unattended chain recorded a success and
            # the VMs were silently never created - which is the failure this whole orchestrator
            # exists to make impossible.
            #
            # -EncryptionStrategy is left at its default of 'None'. The AzureDiskEncryption path
            # creates a Key Vault with purge protection, and nothing in this cycle removes it.
            Deploy       = @{ Force = $true }
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('2.1')
            TimeoutMs    = 2400000
            StdinAnswers = $null
            Excluded     = $null
        }
        @{
            Id           = '3.3'
            Lab          = 'module-3-compute/3.3-containers'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('1.2')
            TimeoutMs    = 1800000
            StdinAnswers = $null
            Excluded     = $null
            # -ResourceGroupName and -Environment both default to dev on the deploy script, the
            # validator and the teardown script, so all three agree without an argument.
        }
        @{
            Id           = '3.4'
            Lab          = 'module-3-compute/3.4-app-service'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('2.1')
            TimeoutMs    = 1200000
            StdinAnswers = $null
            Excluded     = $null
            # Its validator takes resource names rather than an environment, and every default
            # already names the dev resources this phase deploys.
        }

        # -- Module 4 ------------------------------------------------------------------------
        @{
            Id           = '4.1'
            Lab          = 'module-4-storage/4.1-storage-accounts'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            # -All, exactly as issue #73 states. Labs 4.4, 5.1 and 5.3 each need a storage account
            # this lab creates in a different environment - prod, platform and platform - so a
            # single-environment deploy here would break three phases below.
            Deploy       = @{ All = $true }
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('1.2')
            TimeoutMs    = 1200000
            StdinAnswers = $null
            Excluded     = $null
        }
        @{
            Id           = '4.2'
            Lab          = 'module-4-storage/4.2-blob-storage'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('4.1')
            TimeoutMs    = 1200000
            StdinAnswers = $null
            Excluded     = $null
            # Its validator checks both the prod and the dev storage account, which is the second
            # reason 4.1 runs with -All.
        }
        @{
            Id           = '4.3'
            Lab          = 'module-4-storage/4.3-azure-files'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('4.1')
            TimeoutMs    = 1200000
            StdinAnswers = $null
            Excluded     = $null
            # -Environment defaults to 'prod' here, not 'dev'. Deploy, validate and teardown all
            # share that default, so the three agree; it is called out because it is the one lab
            # in module 4 where the default is not dev.
        }
        @{
            Id           = '4.4'
            Lab          = 'module-4-storage/4.4-storage-security'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{}
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('2.2', '4.1')
            TimeoutMs    = 1200000
            StdinAnswers = $null
            Excluded     = $null
            # Puts the prod storage account behind a firewall that admits WorldSubnet, which only
            # carries the Microsoft.Storage service endpoint after lab 2.2 - hence the edge to 2.2
            # rather than to 2.1. -Environment defaults to 'prod' and its ValidateSet is dev|prod,
            # so there is no platform variant to get wrong any more.
        }

        # -- Module 5 ------------------------------------------------------------------------
        @{
            Id         = '5.1'
            Lab        = 'module-5-monitoring-maintenance/5.1-azure-monitor'
            ParamFile  = 'bicep/parameters/main.bicepparam'
            # OpsEmail is filled in by the orchestrator from its own -OpsEmail parameter. It is
            # mandatory on this script, so leaving it out makes the phase hang on a prompt.
            Deploy     = @{ Force = $true }
            PostDeploy = $null
            Test       = @{}
            DependsOn  = @('3.2', '4.1')
            TimeoutMs  = 1800000
            StdinAnswers = $null
            Excluded   = $null
            # gate: verified - exits 1 on a missing platform resource group, on finding no lab-3.2
            # VM in either dev or prod, and on an empty platform resource group.
            RequiresOpsEmail = $true
        }
        @{
            Id           = '5.2'
            Lab          = 'module-5-monitoring-maintenance/5.2-business-continuity'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{ Force = $true }
            # Its validator asserts a blob backup instance that the Bicep does not create, so the
            # phase runs New-LabBlobBackup.ps1 between deploy and validate. Without it the lab
            # deploys correctly and then fails its own check.
            PostDeploy   = @{ Script = 'New-LabBlobBackup.ps1'; Arguments = @{} }
            Test         = @{}
            DependsOn    = @('5.1')
            TimeoutMs    = 1800000
            StdinAnswers = $null
            Excluded     = $null
            # gate: verified - exits 1 on a missing platform resource group or a missing 5.1
            # workspace. Its VM check only warns.
            #
            # This is the lab that creates the Recovery Services Vault. See Remove-LabCycle.ps1 and
            # TROUBLESHOOTING.md for why its teardown needs a minimum az CLI / Az PowerShell.
        }
        @{
            Id           = '5.3'
            Lab          = 'module-5-monitoring-maintenance/5.3-network-monitoring'
            ParamFile    = 'bicep/parameters/main.bicepparam'
            Deploy       = @{ Force = $true }
            PostDeploy   = $null
            Test         = @{}
            DependsOn    = @('2.1', '3.2', '4.1', '5.1')
            TimeoutMs    = 1800000
            StdinAnswers = $null
            Excluded     = $null
            # gate: verified - exits 1 on a missing platform resource group, a missing prod VNet, a
            # missing platform storage account, a missing 5.1 workspace, or fewer than two distinct
            # lab-3.2 VMs. The two-VM requirement is Connection Monitor's, and it is why the edge
            # to 3.2 is a gate here rather than a preference.
            #
            # Deploys into NetworkWatcherRG, a resource group Azure owns and this repository must
            # not delete. Remove-LabCycle.ps1 removes this lab's children from it and leaves the
            # group standing.
        }
    )

    # -- Parameter files this cycle compiles but never deploys ---------------------------------
    # Recorded rather than omitted. The manifest accounting test requires every .bicepparam in the
    # repository to appear exactly once across Phases and CompileOnly, so a file that quietly stops
    # being deployed cannot also quietly stop being counted.
    CompileOnly = @(
        @{
            Lab       = 'module-3-compute/3.1-infrastructure-as-code'
            ParamFile = 'bicep/parameters/prod.bicepparam'
            Reason    = "Lab 3.1's deploy script takes one -Environment per invocation and the cycle runs one phase per lab, so only dev.bicepparam is deployed. Deploying prod here would add nothing the cycle does not already have: 3.1's prod parameters declare the same prod resource group and 10.2.0.0/16 VNet that lab 2.1 already creates and that lab 2.1's validator already checks. The file is still compiled by the repository's parameter-file tests, so a syntax or schema break in it still fails CI."
        }
    )

    # -- Soft-delete guards ---------------------------------------------------------------------
    # Names this run needs that a PREVIOUS run can still be holding. Key Vaults, Log Analytics
    # workspaces and Recovery Services Vaults are not deleted immediately - the name stays
    # reserved - so a teardown that looked clean can block the next deployment, in the Key Vault
    # case for up to 90 days when purge protection is on.
    #
    # Preflight reports these and stops. It never purges: purging is irreversible, and an
    # unattended orchestrator should not be the thing that makes that call.
    #
    # 'Needle' is what the manifest test greps for in the lab's own files. It is a stem rather than
    # the full name because lab 3.2 builds its vault name at run time as
    # "$Environment-skycraft-swc-kv", so the whole name appears nowhere in the source.
    #
    # ON LAB 3.2's KEY VAULT: no phase passes -EncryptionStrategy, which defaults to 'None', and
    # the vault is created only for 'AzureDiskEncryption'. So this cycle does not create it. It is
    # guarded anyway, because an earlier manual run with encryption enabled leaves exactly this
    # obstacle behind, and the cost of looking is one query.
    SoftDeleteGuards = @(
        @{ Kind = 'KeyVault';              Name = 'dev-skycraft-swc-kv';       Needle = 'skycraft-swc-kv';  ResourceGroup = 'dev-skycraft-swc-rg';      Lab = 'module-3-compute/3.2-virtual-machines' }
        @{ Kind = 'KeyVault';              Name = 'prod-skycraft-swc-kv';      Needle = 'skycraft-swc-kv';  ResourceGroup = 'prod-skycraft-swc-rg';     Lab = 'module-3-compute/3.2-virtual-machines' }
        @{ Kind = 'LogAnalytics';          Name = 'platform-skycraft-swc-law'; Needle = 'skycraft-swc-law'; ResourceGroup = 'platform-skycraft-swc-rg'; Lab = 'module-5-monitoring-maintenance/5.1-azure-monitor' }
        @{ Kind = 'RecoveryServicesVault'; Name = 'platform-skycraft-swc-rsv'; Needle = 'skycraft-swc-rsv'; ResourceGroup = 'platform-skycraft-swc-rg'; Lab = 'module-5-monitoring-maintenance/5.2-business-continuity' }
    )

    # -- Teardown -------------------------------------------------------------------------------
    # ONE ENTRY PER LAB, and the order here is the order Remove-LabCycle.ps1 runs them in. It is
    # NOT simply the reverse of the deploy order: lab 1.3 is hoisted to the front because it owns
    # the CanNotDelete locks, and a lock left in place blocks every delete below it.
    #
    # After 1.3, the remainder IS reverse deploy order, for the reason the deploy order existed:
    # a lab is removed only once everything that depended on it is gone.
    #
    # INVOCATIONS, and why an entry holds a list rather than one argument set. Measured against
    # this tree: labs 3.1 and 4.1 offer -Environment 'all' and take one call; lab 3.2 allows only
    # dev|prod and lab 4.3 and 4.4 only their own two or three, with no 'all' anywhere. A single
    # call for those would delete one environment and silently leave the rest standing, which the
    # report would record as a completed teardown. So a lab lists one invocation per call it
    # actually needs, and the calls differ in their arguments, so none repeats another's work.
    #
    # Only the environments this cycle actually deployed are torn down. Lab 4.4 deploys prod only,
    # so its teardown is prod only; asking it to remove a dev deployment that was never made turns
    # a clean teardown into a reported failure.
    Teardowns = @(
        @{ Lab = 'module-1-identities-governance/1.3-governance';           Invocations = @(@{ Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-5-monitoring-maintenance/5.3-network-monitoring';  Invocations = @(@{ Force = $true }); TimeoutMs = 1800000 }
        @{ Lab = 'module-5-monitoring-maintenance/5.2-business-continuity'; Invocations = @(@{ Force = $true }); TimeoutMs = 1800000 }
        @{ Lab = 'module-5-monitoring-maintenance/5.1-azure-monitor';       Invocations = @(@{ Force = $true }); TimeoutMs = 1200000
           LeavesBehind = @(@{ What = "the name 'platform-skycraft-swc-law'"; Why = 'the workspace is deleted into a 14-day soft-delete window that keeps the name reserved. Not a failure and not a cost: Azure recovers the workspace when the same name is redeployed to the same resource group, which preflight reports as a warning rather than a stop.' }) }
        @{ Lab = 'module-4-storage/4.4-storage-security';                   Invocations = @(@{ Environment = 'prod'; Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-4-storage/4.3-azure-files';                        Invocations = @(@{ Environment = 'prod'; Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-4-storage/4.2-blob-storage';                       Invocations = @(@{ Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-4-storage/4.1-storage-accounts';                   Invocations = @(@{ Environment = 'all'; Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-3-compute/3.4-app-service';                        Invocations = @(@{ Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-3-compute/3.3-containers';                         Invocations = @(@{ Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-3-compute/3.2-virtual-machines';                   Invocations = @(@{ Environment = 'dev'; Force = $true }); TimeoutMs = 1800000
           LeavesBehind = @(@{ What = "Key Vault '<env>-skycraft-swc-kv', if an earlier run created one"; Why = 'removal requires -IncludeKeyVault, which this cycle deliberately does not pass, so the vault is left untouched rather than soft-deleted. This cycle never creates one: it deploys with -EncryptionStrategy at its default of None.' }) }
        @{ Lab = 'module-3-compute/3.1-infrastructure-as-code';             Invocations = @(@{ Environment = 'all'; Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-2-networking/2.3-name-resolution';                 Invocations = @(@{ Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-2-networking/2.2-secure-access';                   Invocations = @(@{ Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-2-networking/2.1-virtual-networks';                Invocations = @(@{ Force = $true }); TimeoutMs = 1200000 }
        @{ Lab = 'module-1-identities-governance/1.2-rbac';                 Invocations = @(@{ Force = $true }); TimeoutMs = 1200000 }
    )

    # -- Residue the per-lab teardown scripts do not collect --------------------------------------
    # Swept by Remove-LabCycle.ps1 after every lab has been through its own Remove-LabResource.ps1.
    #
    # AzureBackupRG_<region>_1 is created by Azure, not by this repository: the Recovery Services
    # Vault puts a Microsoft.Compute/restorePointCollections in it while a VM is protected, and
    # both the group and the collection survive the vault. Verified on 2026-08-30 against this
    # tree: the string 'AzureBackupRG' appears in no script in the repository, so nothing else
    # removes it. Issue #73 allowed relying on the fix in #105; #105 shipped without it, so the
    # sweep is here.
    #
    # NetworkWatcherRG is Azure's own resource group and is NEVER deleted - only lab 5.3's children
    # inside it. Deleting the group would take out Network Watcher for every other workload in the
    # subscription.
    ResidualSweep = @{
        # Matched as a prefix against resource group names, then deleted only if the group holds
        # nothing but restore point collections. Anything else in it means it is not the group this
        # rule means, and the sweep leaves it alone and says so.
        BackupResourceGroupPrefix = 'AzureBackupRG_'

        # Vaults that must be gone once teardown has run. Issue #73 is explicit that a surviving
        # vault is a failure, not expected residue, so these are asserted rather than reported.
        AssertAbsent = @(
            @{ Kind = 'RecoveryServicesVault'; Name = 'platform-skycraft-swc-rsv'; ResourceGroup = 'platform-skycraft-swc-rg' }
            @{ Kind = 'DataProtectionBackupVault'; Name = 'platform-skycraft-swc-bv'; ResourceGroup = 'platform-skycraft-swc-rg' }
        )

        # Deleted last, after every lab teardown has run against them. Emptied by the per-lab
        # scripts; removed here so the subscription is left as the cycle found it.
        ResourceGroups = @(
            'dev-skycraft-swc-rg'
            'prod-skycraft-swc-rg'
            'platform-skycraft-swc-rg'
        )
    }

    # -- Tooling floor ----------------------------------------------------------------------------
    # Asserted by Remove-LabCycle.ps1 before it touches anything, and the reason is specific rather
    # than general hygiene. Azure Backup lets you delete a Recovery Services Vault that holds only
    # SOFT-DELETED items; the vault then enters a soft-deleted state itself, at no cost, and stops
    # being an active ARM resource. Older tooling does not use that path: it insists on a fully
    # empty vault, which cannot happen while soft delete is on, and the operator is left waiting
    # out the 14-day window. That is almost certainly the origin of the 'permanent RSV residual'
    # this repository believed in until PR #102 disproved it.
    #
    # Failing fast here, with this message, is much better than letting the delete fail deep in a
    # teardown that has already removed fifteen other labs.
    ToolingFloor = @{
        AzCli        = '2.75.0'
        AzPowerShell = '7.5.0'
    }
}
