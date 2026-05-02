<#
    Eigenverft.Manifested.Sandbox Package - path registration
#>

. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.Module.TestHelpers.ps1"

Invoke-TestPackageDescribe -Name 'Eigenverft.Manifested.Sandbox Package - path registration' -Body {
    It 'skips PATH registration when mode is none' {
        $installRoot = Join-Path $TestDrive 'path-registration-none'
        $null = New-Item -ItemType Directory -Path $installRoot -Force
        $packageResult = [pscustomobject]@{
            PackageConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @()
                        apps     = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode = 'none'
                    }
                }
            }
            InstallDirectory = $installRoot
            InstallOrigin    = 'PackageInstalled'
        }

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageResult = Register-PackagePath -PackageResult $packageResult

        $packageResult.PathRegistration.Status | Should -Be 'Skipped'
        Assert-MockCalled Set-EnvironmentVariableValue -Times 0
    }

    It 'registers a command entry point directory in Process and User PATH for user mode' {
        $installRoot = Join-Path $TestDrive 'path-registration-user'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content '@echo off'

        $packageResult = [pscustomobject]@{
            PackageConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @(
                            @{
                                name         = 'code'
                                relativePath = 'bin/code.cmd'
                            }
                        )
                        apps = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode   = 'user'
                        source = @{
                            kind  = 'commandEntryPoint'
                            value = 'code'
                        }
                    }
                }
            }
            InstallDirectory = $installRoot
            InstallOrigin    = 'PackageInstalled'
        }

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

        $packageResult = Register-PackagePath -PackageResult $packageResult

        $packageResult.PathRegistration.Status | Should -Be 'Registered'
        @($packageResult.PathRegistration.UpdatedTargets) | Should -Be @('Process', 'User')
        $packageResult.PathRegistration.RegisteredPath | Should -Be $binDirectory
        @($writes | ForEach-Object { $_.Target }) | Should -Be @('Process', 'User')
        $expectedBinPattern = [regex]::Escape($binDirectory)
        @($writes | Where-Object { $_.Target -eq 'Process' })[0].Value | Should -Match $expectedBinPattern
        @($writes | Where-Object { $_.Target -eq 'User' })[0].Value | Should -Match $expectedBinPattern
    }

    It 'resolves shipped GitRuntime PATH registration to the cmd directory' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $installRoot = Join-Path $TestDrive 'path-registration-shipped-git'
        $cmdDirectory = Join-Path $installRoot 'cmd'
        $null = New-Item -ItemType Directory -Path $cmdDirectory -Force
        Write-TestTextFile -Path (Join-Path $cmdDirectory 'git.exe') -Content 'fake git'

        $config = Get-PackageConfig -DefinitionId 'GitRuntime'
        $packageResult = New-PackageResult -PackageConfig $config
        $packageResult = Resolve-PackagePackage -PackageResult $packageResult
        $packageResult.InstallDirectory = $installRoot
        $packageResult.InstallOrigin = 'PackageInstalled'

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageResult = Register-PackagePath -PackageResult $packageResult

        $packageResult.PathRegistration.Status | Should -Be 'Registered'
        $packageResult.PathRegistration.RegisteredPath | Should -Be $cmdDirectory
    }

    It 'resolves shipped GitHubCli PATH registration to the bin directory' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $installRoot = Join-Path $TestDrive 'path-registration-shipped-ghcli'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $binDirectory 'gh.exe') -Content 'fake gh'

        $config = Get-PackageConfig -DefinitionId 'GitHubCli'
        $packageResult = New-PackageResult -PackageConfig $config
        $packageResult = Resolve-PackagePackage -PackageResult $packageResult
        $packageResult.InstallDirectory = $installRoot
        $packageResult.InstallOrigin = 'PackageInstalled'

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageResult = Register-PackagePath -PackageResult $packageResult

        $packageResult.PathRegistration.Status | Should -Be 'Registered'
        $packageResult.PathRegistration.RegisteredPath | Should -Be $binDirectory
    }

    It 'resolves shipped NodeRuntime PATH registration to the install directory' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $installRoot = Join-Path $TestDrive 'path-registration-shipped-node'
        $null = New-Item -ItemType Directory -Path $installRoot -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'node.exe') -Content 'fake node'

        $config = Get-PackageConfig -DefinitionId 'NodeRuntime'
        $packageResult = New-PackageResult -PackageConfig $config
        $packageResult = Resolve-PackagePackage -PackageResult $packageResult
        $packageResult.InstallDirectory = $installRoot
        $packageResult.InstallOrigin = 'PackageInstalled'

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageResult = Register-PackagePath -PackageResult $packageResult

        $packageResult.PathRegistration.Status | Should -Be 'Registered'
        $packageResult.PathRegistration.RegisteredPath | Should -Be $installRoot
    }

    It 'resolves shipped npm-backed CLI PATH registrations to the install directory' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $cases = @(
            [pscustomobject]@{ DefinitionId = 'CodexCli'; CommandFile = 'codex.cmd' }
            [pscustomobject]@{ DefinitionId = 'GeminiCli'; CommandFile = 'gemini.cmd' }
            [pscustomobject]@{ DefinitionId = 'OpenCodeCli'; CommandFile = 'opencode.cmd' }
            [pscustomobject]@{ DefinitionId = 'QwenCli'; CommandFile = 'qwen.cmd' }
        )

        foreach ($case in $cases) {
            $installRoot = Join-Path $TestDrive ("path-registration-shipped-" + $case.DefinitionId)
            $null = New-Item -ItemType Directory -Path $installRoot -Force
            Write-TestTextFile -Path (Join-Path $installRoot $case.CommandFile) -Content '@echo off'

            $config = Get-PackageConfig -DefinitionId $case.DefinitionId
            $packageResult = New-PackageResult -PackageConfig $config
            $packageResult = Resolve-PackagePackage -PackageResult $packageResult
            $packageResult.InstallDirectory = $installRoot
            $packageResult.InstallOrigin = 'PackageInstalled'

            Mock Get-EnvironmentVariableValue {}
            Mock Set-EnvironmentVariableValue {}

            $packageResult = Register-PackagePath -PackageResult $packageResult

            $packageResult.PathRegistration.Status | Should -Be 'Registered'
            $packageResult.PathRegistration.RegisteredPath | Should -Be $installRoot
        }
    }

    It 'resolves shipped PythonRuntime PATH registration to the install directory' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $installRoot = Join-Path $TestDrive 'path-registration-shipped-python'
        $null = New-Item -ItemType Directory -Path $installRoot -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'python.exe') -Content 'fake python'

        $config = Get-PackageConfig -DefinitionId 'PythonRuntime'
        $packageResult = New-PackageResult -PackageConfig $config
        $packageResult = Resolve-PackagePackage -PackageResult $packageResult
        $packageResult.InstallDirectory = $installRoot
        $packageResult.InstallOrigin = 'PackageInstalled'

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageResult = Register-PackagePath -PackageResult $packageResult

        $packageResult.PathRegistration.Status | Should -Be 'Registered'
        $packageResult.PathRegistration.RegisteredPath | Should -Be $installRoot
    }

    It 'resolves shipped PowerShell7 PATH registration to the install directory' {
        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')

        $installRoot = Join-Path $TestDrive 'path-registration-shipped-ps7'
        $null = New-Item -ItemType Directory -Path $installRoot -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'pwsh.exe') -Content 'fake pwsh'

        $config = Get-PackageConfig -DefinitionId 'PowerShell7'
        $packageResult = New-PackageResult -PackageConfig $config
        $packageResult = Resolve-PackagePackage -PackageResult $packageResult
        $packageResult.InstallDirectory = $installRoot
        $packageResult.InstallOrigin = 'PackageInstalled'

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageResult = Register-PackagePath -PackageResult $packageResult

        $packageResult.PathRegistration.Status | Should -Be 'Registered'
        $packageResult.PathRegistration.RegisteredPath | Should -Be $installRoot
    }

    It 'skips PATH registration for adopted external installs' {
        $installRoot = Join-Path $TestDrive 'path-registration-adopted-external'
        $binDirectory = Join-Path $installRoot 'bin'
        $null = New-Item -ItemType Directory -Path $binDirectory -Force
        Write-TestTextFile -Path (Join-Path $binDirectory 'code.cmd') -Content '@echo off'

        $packageResult = [pscustomobject]@{
            PackageConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @(
                            @{
                                name         = 'code'
                                relativePath = 'bin/code.cmd'
                            }
                        )
                        apps = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode   = 'user'
                        source = @{
                            kind  = 'commandEntryPoint'
                            value = 'code'
                        }
                    }
                }
            }
            InstallDirectory = $installRoot
            InstallOrigin    = 'AdoptedExternal'
        }

        Mock Get-EnvironmentVariableValue {}
        Mock Set-EnvironmentVariableValue {}

        $packageResult = Register-PackagePath -PackageResult $packageResult

        $packageResult.PathRegistration.Status | Should -Be 'SkippedNotPackageOwned'
        Assert-MockCalled Set-EnvironmentVariableValue -Times 0
    }

    It 'removes stale Package-owned paths for the same install slot before registering the active path' {
        $oldInstallRoot = Join-Path $TestDrive 'path-registration-stale-owned\old'
        $newInstallRoot = Join-Path $TestDrive 'path-registration-stale-owned\new'
        $oldBinDirectory = Join-Path $oldInstallRoot 'bin'
        $newBinDirectory = Join-Path $newInstallRoot 'bin'
        $null = New-Item -ItemType Directory -Path $oldBinDirectory -Force
        $null = New-Item -ItemType Directory -Path $newBinDirectory -Force
        Write-TestTextFile -Path (Join-Path $newBinDirectory 'code.cmd') -Content '@echo off'

        $packageResult = [pscustomobject]@{
            PackageConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @(
                            @{
                                name         = 'code'
                                relativePath = 'bin/code.cmd'
                            }
                        )
                        apps = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode   = 'user'
                        source = @{
                            kind  = 'commandEntryPoint'
                            value = 'code'
                        }
                    }
                }
            }
            ExistingPackage = [pscustomobject]@{
                InstallDirectory = $oldInstallRoot
                Classification   = 'PackageTarget'
                Decision         = 'ReplacePackageOwnedInstall'
            }
            Ownership = [pscustomobject]@{
                InstallSlotId   = 'VSCodeRuntime:stable:win32-x64'
                Classification  = 'PackageTarget'
                OwnershipRecord = [pscustomobject]@{
                    installDirectory = $oldInstallRoot
                    ownershipKind    = 'PackageInstalled'
                }
            }
            InstallDirectory = $newInstallRoot
            InstallOrigin    = 'PackageInstalled'
        }

        $writes = New-Object System.Collections.Generic.List[object]
        Mock Get-EnvironmentVariableValue {
            param([string]$Name, [string]$Target)
            switch ($Target) {
                'Process' { "C:\\Windows\\System32;$oldBinDirectory" }
                'User' { "C:\\Users\\Test\\bin;$oldBinDirectory;C:\\Users\\Test\\ExternalVSCode\\bin" }
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

        $packageResult = Register-PackagePath -PackageResult $packageResult

        $packageResult.PathRegistration.Status | Should -Be 'Registered'
        @($packageResult.PathRegistration.CleanedTargets) | Should -Be @('Process', 'User')
        $packageResult.PathRegistration.CleanupDirectories | Should -Contain $oldBinDirectory
        @($writes | ForEach-Object { $_.Target }) | Should -Be @('Process', 'User')
        @($writes | Where-Object { $_.Target -eq 'Process' })[0].Value | Should -Not -Match ([regex]::Escape($oldBinDirectory))
        @($writes | Where-Object { $_.Target -eq 'Process' })[0].Value | Should -Match ([regex]::Escape($newBinDirectory))
        @($writes | Where-Object { $_.Target -eq 'User' })[0].Value | Should -Not -Match ([regex]::Escape($oldBinDirectory))
        @($writes | Where-Object { $_.Target -eq 'User' })[0].Value | Should -Match ([regex]::Escape($newBinDirectory))
    }

    It 'registers an install-relative directory in Process and Machine PATH for machine mode' {
        $installRoot = Join-Path $TestDrive 'path-registration-machine'
        $null = New-Item -ItemType Directory -Path $installRoot -Force

        $packageResult = [pscustomobject]@{
            PackageConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @()
                        apps     = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode   = 'machine'
                        source = @{
                            kind  = 'installRelativeDirectory'
                            value = '.'
                        }
                    }
                }
            }
            InstallDirectory = $installRoot
            InstallOrigin    = 'PackageInstalled'
        }

        $writes = New-Object System.Collections.Generic.List[object]
        Mock Get-EnvironmentVariableValue {
            param([string]$Name, [string]$Target)
            switch ($Target) {
                'Process' { 'C:\Windows\System32' }
                'Machine' { 'C:\Program Files\Common Files' }
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

        $packageResult = Register-PackagePath -PackageResult $packageResult

        $packageResult.PathRegistration.Status | Should -Be 'Registered'
        @($packageResult.PathRegistration.UpdatedTargets) | Should -Be @('Process', 'Machine')
        $packageResult.PathRegistration.RegisteredPath | Should -Be $installRoot
        @($writes | ForEach-Object { $_.Target }) | Should -Be @('Process', 'Machine')
    }

    It 'fails clearly when shim PATH registration is requested' {
        $installRoot = Join-Path $TestDrive 'path-registration-shim'
        $null = New-Item -ItemType Directory -Path $installRoot -Force

        $packageResult = [pscustomobject]@{
            PackageConfig = ConvertTo-TestPsObject @{
                Definition = @{
                    providedTools = @{
                        commands = @()
                        apps     = @()
                    }
                }
            }
            Package = ConvertTo-TestPsObject @{
                install = @{
                    pathRegistration = @{
                        mode   = 'user'
                        source = @{
                            kind  = 'shim'
                            value = 'bin/code.cmd'
                        }
                    }
                }
            }
            InstallDirectory = $installRoot
            InstallOrigin    = 'PackageInstalled'
        }

        { Register-PackagePath -PackageResult $packageResult } | Should -Throw '*shim*not implemented*'
    }

}
