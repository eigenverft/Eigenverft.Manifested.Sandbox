<#
    Eigenverft.Manifested.Sandbox Package - resources and system checks
#>

. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.Module.TestHelpers.ps1"

Invoke-TestPackageDescribe -Name 'Eigenverft.Manifested.Sandbox Package - resources and system checks' -Body {
    It 'returns physical memory GiB from Win32_ComputerSystem' {
        Mock Get-CimInstance { [pscustomobject]@{ TotalPhysicalMemory = [uint64](16GB) } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }

        $physicalMemoryGiB = Get-PhysicalMemoryGiB

        $physicalMemoryGiB | Should -Be 16
    }

    It 'returns the highest valid video memory GiB from Win32_VideoController' {
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ AdapterRAM = [uint64](2GB) }
                [pscustomobject]@{ AdapterRAM = [uint64](8GB) }
                [pscustomobject]@{ AdapterRAM = [uint64]0 }
            )
        } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }

        $videoMemoryGiB = Get-VideoMemoryGiB

        $videoMemoryGiB | Should -Be 8
    }

    It 'evaluates physicalMemoryGiB and videoMemoryGiB compatibility checks with mocked helper outputs' {
        $packageConfig = [pscustomobject]@{
            Platform     = 'windows'
            Architecture = 'x64'
            OSVersion    = '10.0'
        }
        $compatibility = [pscustomobject]@{
            checks = @(
                [pscustomobject]@{
                    kind     = 'physicalMemoryGiB'
                    operator = '>='
                    value    = 8
                },
                [pscustomobject]@{
                    kind     = 'videoMemoryGiB'
                    operator = '>='
                    value    = 4
                }
            )
        }
        Mock Get-PhysicalMemoryGiB { 16.0 }
        Mock Get-VideoMemoryGiB { 8.0 }

        $evaluation = Test-PackageCompatibilityChecks -PackageConfig $packageConfig -Compatibility $compatibility

        $evaluation.Accepted | Should -BeTrue
        $evaluation.BlockingAccepted | Should -BeTrue
        @($evaluation.Checks | ForEach-Object { $_.Accepted }) | Should -Be @($true, $true)
        @($evaluation.Checks | ForEach-Object { $_.OnFail }) | Should -Be @('fail', 'fail')
    }

    It 'passes a physicalOrVideoMemoryGiB requirement when either RAM or VRAM satisfies it' {
        Mock Get-PhysicalMemoryGiB { 2.0 }
        Mock Get-VideoMemoryGiB { 8.0 }

        $evaluation = Test-PhysicalOrVideoMemoryRequirement -Operator '>=' -ValueGiB 4

        $evaluation.Accepted | Should -BeTrue
        $evaluation.PhysicalMemoryGiB | Should -Be 2
        $evaluation.VideoMemoryGiB | Should -Be 8
    }

    It 'fails a physicalOrVideoMemoryGiB requirement when neither RAM nor VRAM satisfies it' {
        Mock Get-PhysicalMemoryGiB { 2.0 }
        Mock Get-VideoMemoryGiB { 1.0 }

        $evaluation = Test-PhysicalOrVideoMemoryRequirement -Operator '>=' -ValueGiB 4

        $evaluation.Accepted | Should -BeFalse
    }

    It 'registers PATH from generic inputs without a Package result object' {
        $registeredDirectory = Join-Path $TestDrive 'generic-path-registration\bin'
        $null = New-Item -ItemType Directory -Path $registeredDirectory -Force

        $writes = New-Object System.Collections.Generic.List[object]
        Mock Get-EnvironmentVariableValue {
            param([string]$Name, [string]$Target)
            switch ($Target) {
                'Process' { 'C:\Windows\System32' }
                'User' { 'C:\Users\Test\bin' }
                default { $null }
            }
        }
        Mock Set-EnvironmentVariableValue {
            param([string]$Name, [string]$Value, [string]$Target)
            $writes.Add([pscustomobject]@{
                Name   = $Name
                Value  = $Value
                Target = $Target
            }) | Out-Null
        }

        $registration = Register-PathEnvironment -Mode 'user' -RegisteredPath $registeredDirectory -CleanupDirectories @()

        $registration.Status | Should -Be 'Registered'
        @($registration.UpdatedTargets) | Should -Be @('Process', 'User')
        $registration.RegisteredPath | Should -Be $registeredDirectory
        @($writes | ForEach-Object { $_.Target }) | Should -Be @('Process', 'User')
    }

    It 'writes inventory records keyed by install slot and updates current release metadata' {
        $rootPath = Join-Path $TestDrive 'ownership-record'
        $installRoot = Join-Path $rootPath 'managed-install'
        $packageStateIndexPath = Join-Path $rootPath 'package-inventory.json'
        $null = New-Item -ItemType Directory -Path $installRoot -Force

        $globalDocument = New-TestPackageGlobalDocument -PackageInventoryFilePath $packageStateIndexPath
        $release = New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '3.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '3.0.0')
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument $globalDocument -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @($release) -ReleaseDefaultsValidation (New-TestValidation -Version '3.0.0'))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'
        $result = New-PackageResult -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result.InstallDirectory = $installRoot
        $result.Validation = [pscustomobject]@{
            Accepted = $true
        }
        $result.InstallOrigin = 'PackageInstalled'

        $result = Update-PackageInventoryRecord -PackageResult $result
        $savedDocument = Read-PackageJsonDocument -Path $packageStateIndexPath
        $record = $savedDocument.Document.records[0]

        $record.installSlotId | Should -Be 'VSCodeRuntime:stable:win32-x64'
        $record.definitionRepositoryId | Should -Be 'EigenverftModule'
        $record.definitionFileName | Should -Be 'VSCodeRuntime.json'
        $record.definitionSourcePath | Should -Be ([System.IO.Path]::GetFullPath($documents.DefinitionPath))
        $record.definitionLocalPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $record.definitionLocalPath -PathType Leaf | Should -BeTrue
        (Read-PackageJsonDocument -Path $record.definitionLocalPath).Document.id | Should -Be 'VSCodeRuntime'
        $record.currentReleaseId | Should -Be 'vsCode-win-x64-stable'
        $record.currentVersion | Should -Be '3.0.0'
        $record.installDirectory | Should -Be $installRoot
    }

    It 'resolves source inventory absence as no additional environment sources' {
        $rootPath = Join-Path $TestDrive 'no-inventory'
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument) -DefinitionDocument (New-TestVSCodeDefinitionDocument -Releases @(
                New-TestPackageRelease -Id 'vsCode-win-x64-stable' -Version '2.0.0' -Architecture 'x64' -Flavor 'win32-x64' -Install @{ kind = 'reuseExisting' } -Validation (New-TestValidation -Version '2.0.0')
            ))

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $rootPath 'missing-source-inventory.json'), 'Process')
        [Environment]::SetEnvironmentVariable($script:SiteCodeEnvVarName, 'BER', 'Process')

        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'VSCodeRuntime'

        @($config.EnvironmentSources.PSObject.Properties.Name) | Should -Be @('defaultPackageDepot')
    }
}
