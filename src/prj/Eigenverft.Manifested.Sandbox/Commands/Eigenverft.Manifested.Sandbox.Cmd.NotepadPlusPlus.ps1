<#
    Eigenverft.Manifested.Sandbox.Cmd.NotepadPlusPlus
#>

function Invoke-NotepadPlusPlus {
<#
.SYNOPSIS
Ensures the configured Notepad++ package is present.

.DESCRIPTION
Loads the shipped Notepad++ package definition, adopts a valid existing install
when the uninstall registry key points to one, or runs the fixed NSIS installer
through Package installer staging.

.EXAMPLE
Invoke-NotepadPlusPlus
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -DefinitionId 'NotepadPlusPlus' -CommandName 'Invoke-NotepadPlusPlus')
}
