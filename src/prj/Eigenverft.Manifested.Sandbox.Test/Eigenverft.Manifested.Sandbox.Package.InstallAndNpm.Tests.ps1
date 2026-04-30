<#
    Eigenverft.Manifested.Sandbox Package - install and npm
#>

. "$PSScriptRoot\Eigenverft.Manifested.Sandbox.Module.TestHelpers.ps1"

Invoke-TestPackageDescribe -Name 'Eigenverft.Manifested.Sandbox Package - install and npm' -Body {
    It 'routes Package archive installs through PackageInstallStage' {
        $rootPath = Join-Path $TestDrive 'package-install-archive-route'
        $packageFilePath = Join-Path $rootPath 'package.zip'
        $stagePath = Join-Path $rootPath 'stage'
        $layoutRoot = Join-Path $rootPath 'layout\payload'
        $installDirectory = Join-Path $rootPath 'install'
        $null = New-Item -ItemType Directory -Path $layoutRoot -Force
        Write-TestTextFile -Path (Join-Path $layoutRoot 'Code.exe') -Content 'binary'
        Write-TestZipFromDirectory -SourceDirectory (Join-Path $rootPath 'layout') -ZipPath $packageFilePath

        $packageResult = [pscustomobject]@{
            PackageId                    = 'VSCodeRuntime'
            PackageFilePath              = $packageFilePath
            PackageInstallStageDirectory = $stagePath
            InstallDirectory             = $installDirectory
            Package                      = [pscustomobject]@{
                install = [pscustomobject]@{
                    kind              = 'expandArchive'
                    expandedRoot      = 'auto'
                    createDirectories = @('data')
                }
            }
            ExistingPackage = $null
        }

        $installResult = Install-PackageArchive -PackageResult $packageResult

        $installResult.InstallKind | Should -Be 'expandArchive'
        Test-Path -LiteralPath $stagePath -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $installDirectory 'Code.exe') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $installDirectory 'data') -PathType Container | Should -BeTrue
    }

    It 'installs npmGlobalPackage through a ready dependency command into a staged prefix' {
        $rootPath = Join-Path $TestDrive 'npm-package-manager-install'
        $fakeNpmPath = Join-Path $rootPath 'node\npm.cmd'
        $installDirectory = Join-Path $rootPath 'install'
        $workspaceDirectory = Join-Path $rootPath 'workspace'
        $stageDirectory = Join-Path $rootPath 'PackageInstallStage\packages\CodexCli\stable\0.125.0\win32-x64'
        $packageStateIndexPath = Join-Path (Join-Path $rootPath 'State') 'package-state-index.json'
        Write-TestTextFile -Path $fakeNpmPath -Content @"
@echo off
set PREFIX=
:loop
if "%~1"=="" goto done
if "%~1"=="--prefix" (
  set PREFIX=%~2
  shift
)
shift
goto loop
:done
if "%PREFIX%"=="" exit /b 2
mkdir "%PREFIX%\node_modules\@openai\codex" >nul 2>nul
echo @echo off>"%PREFIX%\codex.cmd"
echo {"name":"@openai/codex"}>"%PREFIX%\node_modules\@openai\codex\package.json"
exit /b 0
"@
        $packageResult = [pscustomobject]@{
            PackageId              = 'codex-runtime-win32-x64-stable'
            DefinitionId           = 'CodexCli'
            InstallDirectory       = $installDirectory
            PackageInstallStageDirectory = $stageDirectory
            ExistingPackage        = $null
            PackageConfig     = [pscustomobject]@{
                DefinitionId                  = 'CodexCli'
                PackageFileStagingRootDirectory = $workspaceDirectory
                PackageStateIndexFilePath     = $packageStateIndexPath
            }
            Dependencies           = @(
                [pscustomobject]@{
                    DefinitionId = 'NodeRuntime'
                    Commands     = @(
                        [pscustomobject]@{
                            Name = 'npm'
                            Path = $fakeNpmPath
                        }
                    )
                    EntryPoints  = [pscustomobject]@{
                        Commands = @(
                            [pscustomobject]@{
                                Name = 'npm'
                                Path = $fakeNpmPath
                            }
                        )
                    }
                }
            )
            Package                = [pscustomobject]@{
                id           = 'codex-runtime-win32-x64-stable'
                version      = '0.125.0'
                releaseTrack = 'stable'
                flavor       = 'win32-x64'
                install      = [pscustomobject]@{
                    kind              = 'npmGlobalPackage'
                    installerCommand  = 'npm'
                    packageSpec       = '@openai/codex@{version}'
                }
            }
        }

        $installResult = Install-PackageNpmPackage -PackageResult $packageResult

        $installResult.InstallKind | Should -Be 'npmGlobalPackage'
        $installResult.InstallerCommand | Should -Be 'npm'
        $installResult.InstallerCommandPath | Should -Be ([System.IO.Path]::GetFullPath($fakeNpmPath))
        $installResult.PackageSpec | Should -Be '@openai/codex@0.125.0'
        $installResult.CacheDirectory | Should -Match '\\Caches\\npm\\'
        $installResult.GlobalConfigPath | Should -Match 'Configuration\\External\\npm\\npmrc$'
        Test-Path -LiteralPath (Join-Path $installDirectory 'codex.cmd') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $installDirectory 'node_modules\@openai\codex\package.json') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $installResult.StagePath | Should -BeFalse
    }

    It 'does not replace the final install when npmGlobalPackage fails' {
        $rootPath = Join-Path $TestDrive 'npm-package-manager-install-fail'
        $fakeNpmPath = Join-Path $rootPath 'node\npm.cmd'
        $installDirectory = Join-Path $rootPath 'install'
        $workspaceDirectory = Join-Path $rootPath 'workspace'
        $stageDirectory = Join-Path $rootPath 'PackageInstallStage\packages\CodexCli\stable\0.125.0\win32-x64'
        $packageStateIndexPath = Join-Path (Join-Path $rootPath 'State') 'package-state-index.json'
        Write-TestTextFile -Path $fakeNpmPath -Content "@echo off`r`nexit /b 7`r`n"
        Write-TestTextFile -Path (Join-Path $installDirectory 'sentinel.txt') -Content 'keep-me'

        $packageResult = [pscustomobject]@{
            PackageId              = 'codex-runtime-win32-x64-stable'
            DefinitionId           = 'CodexCli'
            InstallDirectory       = $installDirectory
            PackageInstallStageDirectory = $stageDirectory
            ExistingPackage        = $null
            PackageConfig     = [pscustomobject]@{
                DefinitionId                  = 'CodexCli'
                PackageFileStagingRootDirectory = $workspaceDirectory
                PackageStateIndexFilePath     = $packageStateIndexPath
            }
            Dependencies           = @(
                [pscustomobject]@{
                    DefinitionId = 'NodeRuntime'
                    Commands     = @(
                        [pscustomobject]@{
                            Name = 'npm'
                            Path = $fakeNpmPath
                        }
                    )
                }
            )
            Package                = [pscustomobject]@{
                id           = 'codex-runtime-win32-x64-stable'
                version      = '0.125.0'
                releaseTrack = 'stable'
                flavor       = 'win32-x64'
                install      = [pscustomobject]@{
                    kind              = 'npmGlobalPackage'
                    installerCommand  = 'npm'
                    packageSpec       = '@openai/codex@{version}'
                }
            }
        }

        { Install-PackageNpmPackage -PackageResult $packageResult } | Should -Throw '*exit code 7*'
        Test-Path -LiteralPath (Join-Path $installDirectory 'sentinel.txt') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $stageDirectory -PathType Container | Should -BeTrue
    }

    It 'fails npmGlobalPackage clearly when no ready dependency exposes the installer command' {
        $rootPath = Join-Path $TestDrive 'npm-missing-installer-command'
        $packageResult = [pscustomobject]@{
            PackageId              = 'codex-runtime-win32-x64-stable'
            DefinitionId           = 'CodexCli'
            InstallDirectory       = Join-Path $rootPath 'install'
            ExistingPackage        = $null
            PackageConfig     = [pscustomobject]@{
                DefinitionId                  = 'CodexCli'
                PackageFileStagingRootDirectory = Join-Path $rootPath 'workspace'
                PackageStateIndexFilePath     = Join-Path (Join-Path $rootPath 'State') 'package-state-index.json'
            }
            Dependencies           = @(
                [pscustomobject]@{
                    DefinitionId = 'NodeRuntime'
                    Commands     = @()
                }
            )
            Package                = [pscustomobject]@{
                id           = 'codex-runtime-win32-x64-stable'
                version      = '0.125.0'
                releaseTrack = 'stable'
                flavor       = 'win32-x64'
                install      = [pscustomobject]@{
                    kind              = 'npmGlobalPackage'
                    installerCommand  = 'npm'
                    packageSpec       = '@openai/codex@{version}'
                }
            }
        }

        { Install-PackageNpmPackage -PackageResult $packageResult } | Should -Throw '*no ready dependency exposes that command*'
    }

    It 'accepts package-file Authenticode verification without a SHA256 hash' {
        $packageFilePath = Join-Path $TestDrive 'authenticode-package\vc_redist.x64.exe'
        Write-TestTextFile -Path $packageFilePath -Content 'signed installer placeholder'

        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status            = [System.Management.Automation.SignatureStatus]::Valid
                SignerCertificate = [pscustomobject]@{
                    Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
                }
            }
        }

        $verification = [pscustomobject]@{
            mode = 'required'
            authenticode = [pscustomobject]@{
                requireValid    = $true
                subjectContains = 'Microsoft Corporation'
            }
        }

        $result = Test-PackageSavedFile -Path $packageFilePath -Verification $verification

        $result.Accepted | Should -BeTrue
        $result.Status | Should -Be 'AuthenticodePassed'
        $result.SignatureStatus | Should -Be 'Valid'
    }

    It 'validates registry-only machine prerequisites without an install directory' {
        $registryPath = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
        $packageResult = [pscustomobject]@{
            InstallDirectory = $null
            Validation = $null
            PackageConfig = [pscustomobject]@{}
            Package = [pscustomobject]@{
                validation = [pscustomobject]@{
                    files = @()
                    directories = @()
                    commandChecks = @()
                    metadataFiles = @()
                    signatures = @()
                    fileDetails = @()
                    registryChecks = @(
                        [pscustomobject]@{
                            paths = @($registryPath)
                            valueName = 'Installed'
                            expectedValue = '1'
                        },
                        [pscustomobject]@{
                            paths = @($registryPath)
                            valueName = 'Version'
                            operator = '>='
                            expectedValue = '14.0'
                        }
                    )
                }
            }
        }

        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $registryPath }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                Installed = 1
                Version   = '14.44.35211.0'
            }
        } -ParameterFilter { $LiteralPath -eq $registryPath }

        $packageResult = Test-PackageInstalledPackage -PackageResult $packageResult

        $packageResult.Validation.Accepted | Should -BeTrue
        @($packageResult.Validation.Registry | ForEach-Object { $_.Status }) | Should -Be @('Ready', 'Ready')
    }

    It 'resolves registry values through the generic execution-engine helper' {
        $registryPath = 'HKLM:\SOFTWARE\Vendor\Product'

        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $registryPath }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                Version = '1.2.3'
            }
        } -ParameterFilter { $LiteralPath -eq $registryPath -and $Name -eq 'Version' }

        $result = Resolve-RegistryValueFromPaths -Paths @($registryPath) -ValueName 'Version'

        $result.Path | Should -Be $registryPath
        $result.ActualValue | Should -Be '1.2.3'
        $result.Status | Should -Be 'Ready'
    }

    It 'returns missing when no registry candidate path exists' {
        $paths = @(
            'HKLM:\SOFTWARE\Vendor\MissingA',
            'HKLM:\SOFTWARE\Vendor\MissingB'
        )

        Mock Test-Path { $false }

        $result = Resolve-RegistryValueFromPaths -Paths $paths -ValueName 'Version'

        $result.Path | Should -Be $paths[0]
        $result.Paths | Should -Be $paths
        $result.ActualValue | Should -BeNullOrEmpty
        $result.Status | Should -Be 'Missing'
    }

    It 'reads a direct Windows uninstall registry key and resolves display-icon directory' {
        $registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Notepad++'

        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $registryPath }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                DisplayName     = 'Notepad++ (64-bit x64)'
                DisplayVersion  = '8.9.4'
                Publisher       = 'Notepad++ Team'
                InstallLocation = ''
                DisplayIcon     = '"C:\Program Files\Notepad++\notepad++.exe",0'
                UninstallString = '"C:\Program Files\Notepad++\uninstall.exe" /S'
            }
        } -ParameterFilter { $LiteralPath -eq $registryPath }

        $entry = Get-WindowsUninstallRegistryEntry -Path $registryPath
        $displayIconDirectory = Resolve-WindowsUninstallRegistryEntryPath -Entry $entry -Source 'displayIconDirectory'
        $uninstallPath = Resolve-WindowsUninstallRegistryEntryPath -Entry $entry -Source 'uninstallString'

        $entry.Status | Should -Be 'Ready'
        $entry.DisplayVersion | Should -Be '8.9.4'
        $displayIconDirectory.Status | Should -Be 'Ready'
        $displayIconDirectory.ResolvedPath | Should -Be ([System.IO.Path]::GetFullPath('C:\Program Files\Notepad++'))
        $uninstallPath.ResolvedPath | Should -Be ([System.IO.Path]::GetFullPath('C:\Program Files\Notepad++\uninstall.exe'))
    }

    It 'resolves windows uninstall registry discovery to an install directory candidate' {
        $registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Notepad++'
        $installDirectory = Join-Path $TestDrive 'Program Files\Notepad++'
        $displayIconPath = Join-Path $installDirectory 'notepad++.exe'
        $null = New-Item -ItemType Directory -Path $installDirectory -Force

        Mock Test-Path { $false }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $registryPath }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $installDirectory -and $PathType -eq 'Container' }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                DisplayName    = 'Notepad++ (64-bit x64)'
                DisplayVersion = '8.9.4'
                DisplayIcon    = '"' + $displayIconPath + '",0'
            }
        } -ParameterFilter { $LiteralPath -eq $registryPath }

        $packageResult = [pscustomobject]@{
            InstallDirectory = $null
            Package          = [pscustomobject]@{
                id = 'notepad-plus-plus-8.9.4-win-x64'
                existingInstallDiscovery = [pscustomobject]@{
                    enableDetection = $true
                    searchLocations = @(
                        [pscustomobject]@{
                            kind = 'windowsUninstallRegistryKey'
                            paths = @($registryPath)
                            installDirectorySource = 'displayIconDirectory'
                        }
                    )
                    installRootRules = @()
                }
            }
            ExistingPackage  = $null
        }

        $packageResult = Find-PackageExistingPackage -PackageResult $packageResult

        $packageResult.ExistingPackage.SearchKind | Should -Be 'windowsUninstallRegistryKey'
        $packageResult.ExistingPackage.CandidatePath | Should -Be ([System.IO.Path]::GetFullPath($installDirectory))
        $packageResult.ExistingPackage.InstallDirectory | Should -Be ([System.IO.Path]::GetFullPath($installDirectory))
        $packageResult.ExistingPackage.DiscoveryDetails.RegistryEntry.DisplayName | Should -Be 'Notepad++ (64-bit x64)'
    }

    It 'marks a satisfied machine prerequisite so acquisition and installer execution can be skipped' {
        $packageResult = [pscustomobject]@{
            InstallOrigin = $null
            Install       = $null
            Validation    = $null
            Package       = [pscustomobject]@{
                install = [pscustomobject]@{
                    kind       = 'runInstaller'
                    targetKind = 'machinePrerequisite'
                }
            }
        }

        Mock Test-PackageInstalledPackage {
            param([psobject]$PackageResult)
            $PackageResult.Validation = [pscustomobject]@{
                Accepted      = $true
                Files         = @()
                Directories   = @()
                Commands      = @()
                MetadataFiles = @()
                Signatures    = @()
                FileDetails   = @()
                Registry      = @([pscustomobject]@{ Status = 'Ready' })
            }
            $PackageResult
        }

        $packageResult = Resolve-PackagePreInstallSatisfaction -PackageResult $packageResult

        $packageResult.InstallOrigin | Should -Be 'AlreadySatisfied'
        $packageResult.Install.Status | Should -Be 'AlreadySatisfied'
        $packageResult.Install.TargetKind | Should -Be 'machinePrerequisite'
    }

    It 'runs required-elevation installers with RunAs and quoted log-path arguments' {
        $rootPath = Join-Path $TestDrive 'installer path with space'
        $installerPath = Join-Path $rootPath 'vc_redist.x64.exe'
        $workspacePath = Join-Path $rootPath 'workspace'
        Write-TestTextFile -Path $installerPath -Content 'installer'

        $process = [pscustomobject]@{
            Id       = 42
            ExitCode = 0
        }
        $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param([int]$Timeout) $true }
        $process | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }

        $startProcessCalls = New-Object System.Collections.Generic.List[object]
        Mock Test-ProcessElevation { $false }
        Mock Start-Process {
            param(
                [string]$FilePath,
                [object[]]$ArgumentList,
                [string]$WorkingDirectory,
                [switch]$PassThru,
                [string]$Verb
            )
            $startProcessCalls.Add([pscustomobject]@{
                FilePath         = $FilePath
                ArgumentList     = @($ArgumentList)
                WorkingDirectory = $WorkingDirectory
                Verb             = $Verb
            }) | Out-Null
            $process
        }

        $packageResult = [pscustomobject]@{
            PackageFilePath           = $installerPath
            PackageFileStagingDirectory = $workspacePath
            PackageInstallStageDirectory = $workspacePath
            InstallDirectory          = $null
            PackageConfig        = [pscustomobject]@{
                PreferredTargetInstallRootDirectory = $rootPath
                PackageStateIndexFilePath           = Join-Path (Join-Path $rootPath 'State') 'package-state-index.json'
            }
            Package = [pscustomobject]@{
                install = [pscustomobject]@{
                    kind           = 'runInstaller'
                    targetKind     = 'machinePrerequisite'
                    installerKind  = 'burn'
                    uiMode         = 'quiet'
                    elevation      = 'required'
                    logRelativePath = 'visual-cpp-redist/{timestamp}.log'
                    commandArguments = @('/install', '/quiet', '/norestart', '/log', '{logPath}')
                    successExitCodes = @(0)
                    restartExitCodes = @(3010)
                }
            }
        }

        $result = Invoke-PackageInstallerProcess -PackageResult $packageResult

        $startProcessCalls.Count | Should -Be 1
        $startProcessCalls[0].Verb | Should -Be 'RunAs'
        $startProcessCalls[0].WorkingDirectory | Should -Be $workspacePath
        $startProcessCalls[0].ArgumentList[-1].StartsWith('"') | Should -BeTrue
        $startProcessCalls[0].ArgumentList[-1].EndsWith('"') | Should -BeTrue
        $result.TargetKind | Should -Be 'machinePrerequisite'
        $result.Elevation.ShouldElevate | Should -BeTrue
        $result.LogPath | Should -Match '\\Logs\\visual-cpp-redist\\[0-9]{8}-[0-9]{6}\.log$'
    }

    It 'runs NSIS installers from PackageInstallStage and appends target directory argument last without quoting' {
        $rootPath = Join-Path $TestDrive 'nsis installer path with space'
        $packageFilePath = Join-Path $rootPath 'file-stage\npp.8.9.4.Installer.x64.exe'
        $installStageDirectory = Join-Path $rootPath 'install-stage'
        $installDirectory = Join-Path $rootPath 'Installed\Notepad++ Target'
        Write-TestTextFile -Path $packageFilePath -Content 'installer'

        $process = [pscustomobject]@{
            Id       = 43
            ExitCode = 0
        }
        $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param([int]$Timeout) $true }
        $process | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }

        $startProcessCalls = New-Object System.Collections.Generic.List[object]
        Mock Test-ProcessElevation { $false }
        Mock Start-Process {
            param(
                [string]$FilePath,
                [object[]]$ArgumentList,
                [string]$WorkingDirectory,
                [switch]$PassThru,
                [string]$Verb
            )
            $startProcessCalls.Add([pscustomobject]@{
                FilePath         = $FilePath
                ArgumentList     = @($ArgumentList)
                WorkingDirectory = $WorkingDirectory
                Verb             = $Verb
            }) | Out-Null
            $process
        }

        $packageResult = [pscustomobject]@{
            PackageId                    = 'NotepadPlusPlus'
            PackageFilePath              = $packageFilePath
            PackageFileStagingDirectory  = Split-Path -Parent $packageFilePath
            PackageInstallStageDirectory = $installStageDirectory
            InstallDirectory             = $installDirectory
            PackageConfig                = [pscustomobject]@{}
            Package                      = [pscustomobject]@{
                install = [pscustomobject]@{
                    kind = 'nsisInstaller'
                    elevation = 'none'
                    commandArguments = @('/S', '/noUpdater', '/closeRunningNpp')
                    targetDirectoryArgument = [pscustomobject]@{
                        enabled = $true
                        prefix  = '/D='
                    }
                    successExitCodes = @(0)
                    restartExitCodes = @()
                }
            }
        }

        $result = Invoke-PackageNsisInstallerProcess -PackageResult $packageResult

        $stagedInstallerPath = Join-Path $installStageDirectory 'npp.8.9.4.Installer.x64.exe'
        $startProcessCalls.Count | Should -Be 1
        $startProcessCalls[0].FilePath | Should -Be $stagedInstallerPath
        $startProcessCalls[0].WorkingDirectory | Should -Be $installStageDirectory
        $startProcessCalls[0].ArgumentList | Should -Be @('/S', '/noUpdater', '/closeRunningNpp', ('/D=' + $installDirectory))
        $startProcessCalls[0].ArgumentList[-1].StartsWith('"') | Should -BeFalse
        Test-Path -LiteralPath $stagedInstallerPath -PathType Leaf | Should -BeTrue
        $result.InstallKind | Should -BeNullOrEmpty
        $result.InstallerKind | Should -Be 'nsis'
    }

    It 'installs a single package file into the configured target-relative path' {
        $rootPath = Join-Path $TestDrive 'package-install-file-route'
        $packageFilePath = Join-Path $rootPath 'package\Qwen3.5-2B-Q8_0.gguf'
        $installDirectory = Join-Path $rootPath 'install'
        Write-TestTextFile -Path $packageFilePath -Content 'gguf-binary'

        $packageResult = [pscustomobject]@{
            PackageId        = 'Qwen35_2B_Q8_0_Model'
            PackageFilePath  = $packageFilePath
            InstallDirectory = $installDirectory
            Package          = [pscustomobject]@{
                packageFile = [pscustomobject]@{
                    fileName = 'Qwen3.5-2B-Q8_0.gguf'
                }
                install = [pscustomobject]@{
                    kind               = 'placePackageFile'
                    targetRelativePath = 'models/Qwen3.5-2B-Q8_0.gguf'
                }
            }
            ExistingPackage = $null
        }

        $installResult = Install-PackagePackageFile -PackageResult $packageResult

        $installResult.InstallKind | Should -Be 'placePackageFile'
        $installResult.InstalledFilePath | Should -Be (Join-Path $installDirectory 'models\Qwen3.5-2B-Q8_0.gguf')
        Test-Path -LiteralPath $installResult.InstalledFilePath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $installResult.InstalledFilePath -Raw) | Should -Be 'gguf-binary'
    }

    It 'installs a shipped single-file resource from the default package depot and validates it' {
        $rootPath = Join-Path $TestDrive 'resource-package-flow'
        $packageFileStagingDirectory = Join-Path $rootPath 'workspace'
        $defaultPackageDepotDirectory = Join-Path $rootPath 'default-depot'
        $preferredTargetInstallDirectory = Join-Path $rootPath 'installs'
        $packageStateIndexFilePath = Join-Path $rootPath 'package-state.json'
        $definitionDocument = @{
            schemaVersion = '1.0'
            id = 'Qwen35_2B_Q8_0_Model'
            display = @{
                default = @{
                    name = 'Qwen 3.5 2B Q8_0'
                    publisher = 'Unsloth'
                    corporation = 'Unsloth AI'
                    summary = 'Quantized GGUF model resource'
                }
                localizations = @{}
            }
            upstreamSources = @{
                huggingFaceDownload = @{
                    kind = 'download'
                    baseUri = 'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/'
                }
            }
            providedTools = @{
                commands = [object[]]@()
                apps = [object[]]@()
            }
            releaseDefaults = @{
                compatibility = @{
                    checks = @(
                        @{
                            kind = 'physicalOrVideoMemoryGiB'
                            operator = '>='
                            value = 4
                            onFail = 'warn'
                        }
                    )
                }
                install = @{
                    kind = 'placePackageFile'
                    installDirectory = 'qwen35-2b/{releaseTrack}/{version}/{flavor}'
                    targetRelativePath = 'Qwen3.5-2B-Q8_0.gguf'
                    pathRegistration = @{
                        mode = 'none'
                    }
                }
                validation = @{
                    files = @('Qwen3.5-2B-Q8_0.gguf')
                    directories = [object[]]@()
                    commandChecks = [object[]]@()
                    metadataFiles = [object[]]@()
                    signatures = [object[]]@()
                    fileDetails = [object[]]@()
                    registryChecks = [object[]]@()
                }
                existingInstallDiscovery = @{
                    enableDetection = $false
                    searchLocations = [object[]]@()
                    installRootRules = [object[]]@()
                }
                existingInstallPolicy = @{
                    allowAdoptExternal = $false
                    upgradeAdoptedInstall = $false
                    requirePackageOwnership = $false
                }
            }
            releases = @(
                @{
                    id = 'qwen35-2b-q8-0-stable'
                    version = '3.5.0'
                    releaseTrack = 'stable'
                    flavor = 'q8-0'
                    constraints = @{
                        os = @('windows')
                        cpu = @('x64')
                    }
                    packageFile = @{
                        fileName = 'Qwen3.5-2B-Q8_0.gguf'
                        format = 'gguf'
                        portable = $true
                        autoUpdateSupported = $false
                    }
                    acquisitionCandidates = @(
                        @{
                            kind = 'packageDepot'
                            searchOrder = 250
                            verification = @{
                                mode = 'none'
                            }
                        }
                    )
                }
            )
        }
        $documents = Write-TestPackageDocuments -RootPath $rootPath -GlobalDocument (New-TestPackageGlobalDocument -PackageFileStagingDirectory $packageFileStagingDirectory -DefaultPackageDepotDirectory $defaultPackageDepotDirectory -PreferredTargetInstallDirectory $preferredTargetInstallDirectory -PackageStateIndexFilePath $packageStateIndexFilePath) -DefinitionDocument $definitionDocument

        [Environment]::SetEnvironmentVariable($script:SourceInventoryEnvVarName, (Join-Path $TestDrive 'missing-inventory.json'), 'Process')
        Mock Get-PackageGlobalConfigPath { $documents.GlobalConfigPath }
        Mock Get-PackageDefinitionPath { param($DefinitionId) $documents.DefinitionPath }

        $config = Get-PackageConfig -DefinitionId 'Qwen35_2B_Q8_0_Model'
        $result = New-PackageResult -CommandName 'test' -PackageConfig $config
        $result = Resolve-PackagePackage -PackageResult $result
        $result = Resolve-PackagePaths -PackageResult $result
        $result = Build-PackageAcquisitionPlan -PackageResult $result

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $result.DefaultPackageDepotFilePath) -Force
        Write-TestTextFile -Path $result.DefaultPackageDepotFilePath -Content 'gguf-binary'

        $result = Prepare-PackageInstallFile -PackageResult $result
        $result = Install-PackagePackage -PackageResult $result
        $result = Test-PackageInstalledPackage -PackageResult $result

        $result.PackageFilePreparation.Status | Should -Be 'HydratedFromDefaultPackageDepot'
        $result.Install.InstallKind | Should -Be 'placePackageFile'
        $result.Install.InstalledFilePath | Should -Be (Join-Path $result.InstallDirectory 'Qwen3.5-2B-Q8_0.gguf')
        Test-Path -LiteralPath $result.Install.InstalledFilePath -PathType Leaf | Should -BeTrue
        $result.Validation.Accepted | Should -BeTrue
    }

    It 'cleans package-specific staging directories after a successful run' {
        $rootPath = Join-Path $TestDrive 'install-preparation-cleanup'
        $preparationDirectory = Join-Path $rootPath 'PackageFileStaging\packages\VSCodeRuntime\stable\2.0.0\win32-x64'
        $installStageDirectory = Join-Path $rootPath 'PackageInstallStage\packages\VSCodeRuntime\stable\2.0.0\win32-x64'
        $npmCacheDirectory = Join-Path $rootPath 'Caches\npm\CodexCli\stable\0.125.0\win32-x64'
        Write-TestTextFile -Path (Join-Path $preparationDirectory 'package.zip') -Content 'package'
        Write-TestTextFile -Path (Join-Path $installStageDirectory 'expanded\Code.exe') -Content 'binary'
        Write-TestTextFile -Path (Join-Path $npmCacheDirectory 'cache-entry') -Content 'cache'

        $result = Clear-PackageWorkDirectories -PackageResult ([pscustomobject]@{
                PackageFileStagingDirectory = $preparationDirectory
                PackageInstallStageDirectory = $installStageDirectory
            })

        $result.PackageFileStagingDirectory | Should -Be $preparationDirectory
        Test-Path -LiteralPath $preparationDirectory | Should -BeFalse
        Test-Path -LiteralPath $installStageDirectory | Should -BeFalse
        Test-Path -LiteralPath $npmCacheDirectory -PathType Container | Should -BeTrue
    }

    It 'discovers command-based existing installs through Get-ResolvedApplicationPath' {
        $rootPath = Join-Path $TestDrive 'command-discovery-route'
        $installRoot = Join-Path $rootPath 'existing-install'
        $commandPath = Join-Path $installRoot 'bin\code.cmd'
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $commandPath) -Force
        Write-TestTextFile -Path (Join-Path $installRoot 'Code.exe') -Content 'fake'
        Write-TestTextFile -Path $commandPath -Content '@echo off'

        $packageResult = [pscustomobject]@{
            InstallDirectory = $null
            ExistingPackage  = $null
            Package          = [pscustomobject]@{
                id = 'VSCodeRuntime'
                existingInstallDiscovery = [pscustomobject]@{
                    enableDetection = $true
                    searchLocations = @(
                        [pscustomobject]@{
                            kind = 'command'
                            name = 'code'
                        }
                    )
                    installRootRules = @(
                        [pscustomobject]@{
                            match = [pscustomobject]@{
                                kind  = 'fileName'
                                value = 'code.cmd'
                            }
                            installRootRelativePath = '..'
                        }
                    )
                }
            }
        }

        Mock Get-ResolvedApplicationPath { $commandPath } -ParameterFilter { $CommandName -eq 'code' }

        $packageResult = Find-PackageExistingPackage -PackageResult $packageResult

        Assert-MockCalled Get-ResolvedApplicationPath -Times 1 -ParameterFilter { $CommandName -eq 'code' }
        $packageResult.ExistingPackage.SearchKind | Should -Be 'command'
        $packageResult.ExistingPackage.CandidatePath | Should -Be $commandPath
        $packageResult.ExistingPackage.InstallDirectory | Should -Be ([System.IO.Path]::GetFullPath($installRoot))
    }

    It 'routes filesystem package saves through Copy-FileToPath' {
        $sourcePath = Join-Path $TestDrive 'filesystem-save\source.zip'
        $targetPath = Join-Path $TestDrive 'filesystem-save\target.zip'
        Write-TestTextFile -Path $sourcePath -Content 'archive'

        Mock Copy-FileToPath { $TargetPath } -ParameterFilter { $SourcePath -eq $sourcePath -and $TargetPath -eq $targetPath -and $Overwrite }

        $resolvedPath = Save-PackageFilesystemFile -SourcePath $sourcePath -TargetPath $targetPath

        Assert-MockCalled Copy-FileToPath -Times 1 -ParameterFilter { $SourcePath -eq $sourcePath -and $TargetPath -eq $targetPath -and $Overwrite }
        $resolvedPath | Should -Be $targetPath
    }

}
