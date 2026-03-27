function New-ManifestedPlanStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$Target,

        [bool]$IsMutation = $true,

        [bool]$RequiresElevation = $false,

        [string]$HandlerFunction,

        [hashtable]$HandlerArguments = @{}
    )

    return [pscustomobject]@{
        Name              = $Name
        Kind              = $Kind
        Reason            = $Reason
        Action            = $Action
        Target            = $Target
        IsMutation        = [bool]$IsMutation
        RequiresElevation = [bool]$RequiresElevation
        HandlerFunction   = $HandlerFunction
        HandlerArguments  = $HandlerArguments
    }
}

function Convert-ManifestedPlanStepForOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Step
    )

    return [pscustomobject]@{
        Name              = $Step.Name
        Kind              = $Step.Kind
        Reason            = $Step.Reason
        Action            = $Step.Action
        Target            = $Step.Target
        IsMutation        = [bool]$Step.IsMutation
        RequiresElevation = [bool]$Step.RequiresElevation
    }
}


