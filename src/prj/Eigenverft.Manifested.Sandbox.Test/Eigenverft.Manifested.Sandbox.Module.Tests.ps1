<#
    Minimal Pester sketch for the module.
#>

Describe 'Eigenverft.Manifested.Sandbox module' {
    BeforeAll {
        $moduleManifestPath = $null
        $testProjectRoot = $null

        if ($PSCommandPath) {
            $testProjectRoot = Split-Path -Parent $PSCommandPath
        }
        elseif ($PSScriptRoot) {
            $testProjectRoot = $PSScriptRoot
        }

        if ($testProjectRoot) {
            $moduleManifestPath = Join-Path (Split-Path -Parent $testProjectRoot) 'Eigenverft.Manifested.Sandbox\Eigenverft.Manifested.Sandbox.psd1'
        }

        if (-not $moduleManifestPath -or -not (Test-Path -LiteralPath $moduleManifestPath)) {
            $moduleManifestPath = Join-Path (Get-Location) 'src\prj\Eigenverft.Manifested.Sandbox\Eigenverft.Manifested.Sandbox.psd1'
        }

        if (-not (Test-Path -LiteralPath $moduleManifestPath)) {
            throw "Could not find module manifest at '$moduleManifestPath'. Run the test from the repository root or update the test path."
        }

        $script:SandboxModule = Import-Module $moduleManifestPath -Force -PassThru
    }

    AfterAll {
        if ($script:SandboxModule) {
            Remove-Module $script:SandboxModule.Name -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns the loaded module version from Get-SandboxVersion' {
        $versionText = & $script:SandboxModule { Get-SandboxVersion }

        $versionText | Should -Match '^Eigenverft\.Manifested\.Sandbox \d+\.\d+\.\d+'
    }
}
