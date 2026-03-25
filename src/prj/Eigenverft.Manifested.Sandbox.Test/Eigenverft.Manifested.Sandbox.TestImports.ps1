<#
    Eigenverft.Manifested.Sandbox test import loader
#>

$moduleProjectRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Eigenverft.Manifested.Sandbox'

# Dotsource the compatibility facade so tests follow the live module load shape.
. "$moduleProjectRoot\Eigenverft.Manifested.Sandbox.psm1"

