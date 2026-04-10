<#
    Minimal Pester sketch for the module.
#>

Describe 'Eigenverft.Manifested.Sandbox module' {
    BeforeAll {
        $moduleManifestPath = $null
        $moduleProjectRoot = $null
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

        $moduleProjectRoot = Split-Path -Parent $moduleManifestPath

        Import-Module $moduleManifestPath -Force

        . (Join-Path $moduleProjectRoot 'Private\Infra\Eigenverft.Manifested.Sandbox.Base.Invoke-WebRequestEx.ps1')
    }

    AfterAll {
        Remove-Variable ConsoleLogMinLevel -Scope Global -Force -ErrorAction SilentlyContinue
        Remove-Module Eigenverft.Manifested.Sandbox -Force -ErrorAction SilentlyContinue
    }

    It 'returns the loaded module version from Get-SandboxVersion' {
        $versionText = Get-SandboxVersion

        $versionText | Should -Match '^Eigenverft\.Manifested\.Sandbox \d+\.\d+\.\d+'
    }

    It 'exposes EnforceCertificateCheck and no longer exposes the AllowSelfSigned alias' {
        $command = Get-Command Invoke-WebRequestEx -CommandType Function

        $command.Parameters.ContainsKey('EnforceCertificateCheck') | Should -BeTrue
        $command.Parameters['SkipCertificateCheck'].Aliases | Should -Not -Contain 'AllowSelfSigned'
    }

    It 'defaults to skipping certificate validation on PowerShell 7+' -Skip:($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.0') {
        $global:ConsoleLogMinLevel = 'FTL'

        Mock Invoke-WebRequest {
            [pscustomobject]@{
                StatusCode = 200
                Content = 'ok'
            }
        }

        $null = Invoke-WebRequestEx -Uri 'https://example.org' -UseBasicParsing

        Assert-MockCalled Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter { $SkipCertificateCheck }
    }

    It 'enforces certificate validation when requested on PowerShell 7+' -Skip:($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.0') {
        $global:ConsoleLogMinLevel = 'FTL'

        Mock Invoke-WebRequest {
            [pscustomobject]@{
                StatusCode = 200
                Content = 'ok'
            }
        }

        $null = Invoke-WebRequestEx -Uri 'https://example.org' -UseBasicParsing -EnforceCertificateCheck

        Assert-MockCalled Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter { -not $SkipCertificateCheck }
    }
}
