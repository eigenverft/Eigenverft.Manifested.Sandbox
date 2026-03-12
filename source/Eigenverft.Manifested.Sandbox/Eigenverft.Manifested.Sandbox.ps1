#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor `
        [Net.SecurityProtocolType]::Tls12
}
catch {
    # Best effort only. Older hosts may already be configured appropriately.
}

<#

# Import the module into the current PowerShell session
Import-Module Eigenverft.Manifested.Sandbox -Force

# Initialize both sandbox prerequisites
Initialize-Sandbox

# Refresh the cached Node.js runtime before extraction
Initialize-Sandbox -RefreshNode

# Refresh the cached VC++ bootstrapper before validation/install
Initialize-Sandbox -RefreshVCRuntime

# Skip VC++ initialization and only prepare Node.js
Initialize-Sandbox -SkipVCRuntime

# Use a custom local cache and tools root
Initialize-Sandbox -LocalRoot 'C:\Sandbox'

# Preview the work without changing the machine
Initialize-Sandbox -WhatIf

#>

function Initialize-Sandbox {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshNode,
        [switch]$RefreshVCRuntime,
        [switch]$SkipNodeRuntime,
        [switch]$SkipVCRuntime,
        [int]$InstallTimeoutSec = 300,
        [string]$LocalRoot = (Get-SandboxDefaultLocalRoot)
    )

    $layout = Get-SandboxLayout -LocalRoot $LocalRoot

    if ($SkipNodeRuntime) {
        $nodeRuntime = [pscustomobject]@{
            Action = 'skipped'
            Reason = 'SkipNodeRuntime'
        }
    }
    elseif ($PSCmdlet.ShouldProcess($layout.NodeToolsRoot, 'Initialize managed Node.js runtime')) {
        $nodeRuntime = Ensure-SandboxNodeRuntime -RefreshNode:$RefreshNode -LocalRoot $layout.LocalRoot
    }
    else {
        $nodeRuntime = [pscustomobject]@{
            Action = 'whatif'
            Reason = 'WhatIf'
        }
    }

    if ($SkipVCRuntime) {
        $vcRuntime = [pscustomobject]@{
            Action = 'skipped'
            Reason = 'SkipVCRuntime'
        }
    }
    elseif ($PSCmdlet.ShouldProcess('Microsoft Visual C++ Redistributable (x64)', 'Initialize sandbox prerequisite runtime')) {
        $vcRuntime = Ensure-SandboxVCRuntime -RefreshVCRuntime:$RefreshVCRuntime -InstallTimeoutSec $InstallTimeoutSec -LocalRoot $layout.LocalRoot
    }
    else {
        $vcRuntime = [pscustomobject]@{
            Action = 'whatif'
            Reason = 'WhatIf'
        }
    }

    [pscustomobject]@{
        LocalRoot   = $layout.LocalRoot
        Layout      = $layout
        NodeRuntime = $nodeRuntime
        VCRuntime   = $vcRuntime
    }
}

