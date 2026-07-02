#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$ChallengeTemplate = Join-Path $ScriptDir 'templates\graftcode-challenge'
$GraftcodeUrl = 'https://wad.graftcode.com'
$WadKnowledgeRepo = 'https://github.com/pladynski/wad-knowledge'
$WorkspaceMetadataCleanupDelay = 10
$CursorChatMaxWidth = 400

$Mode = ''
$Ide = ''
$WorkDir = ''

function Show-Banner {
    Clear-Host
    Write-Host @'
   ____ ____      _    _____ _____ ____ ___  ____  _____
  / ___|  _ \    / \  |_   _| ____/ ___|  _ \|  _ \| ____|
 | |  _| |_) |  / _ \   | | |  _|| |   | | | | | | |  _|
 | |_| |  _ <  / ___ \  | | | |__| |___| |_| | |_| | |___|
  \____|_| \_\/_/   \_\ |_| |_____\____|____/|____/|_____|

   ____ _   _    _    _       _     _____ _   _ _____ ____  _____
  / ___| | | |  / \  | |     | |   | ____| \ | |_   _|  _ \| ____|
 | |   | |_| | / _ \ | |     | |   |  _| |  \| | | | | |_) |  _|
 | |___|  _  |/ ___ \| |___  | |___| |___| |\  | | | |  _ <| |___|
  \____|_| |_/_/   \_\_____| |_____|_____|_| \_| |_| |_| \_\_____|
'@ -ForegroundColor Cyan
    Write-Host 'Welcome to the world of Graftcode!' -ForegroundColor Yellow
    Write-Host ''
}

function Choose-Mode {
    Write-Host 'What would you like to do?'
    Write-Host '  1) Graftcode Challenge'
    Write-Host '  2) Build a distributed system using Graftcode'
    Write-Host ''

    while ($true) {
        $choice = Read-Host 'Your choice [1/2]'
        switch ($choice) {
            '1' { $script:Mode = 'challenge'; return }
            '2' { $script:Mode = 'distributed'; return }
            default { Write-Host 'Invalid choice. Enter 1 or 2.' -ForegroundColor Red }
        }
    }
}

function Choose-Ide {
    Write-Host 'Choose your IDE:'
    Write-Host '  1) Cursor'
    Write-Host '  2) Visual Studio Code'
    Write-Host ''

    while ($true) {
        $choice = Read-Host 'Your choice [1/2]'
        switch ($choice) {
            '1' { $script:Ide = 'cursor'; return }
            '2' { $script:Ide = 'vscode'; return }
            default { Write-Host 'Invalid choice. Enter 1 or 2.' -ForegroundColor Red }
        }
    }
}

function Find-IdeCmd {
    param([string]$TargetIde)

    if ($TargetIde -eq 'cursor') {
        $cmd = Get-Command cursor -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }

        $paths = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\cursor\resources\app\bin\cursor.cmd'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Cursor\resources\app\bin\cursor.cmd'),
            (Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe')
        )
        foreach ($path in $paths) {
            if (Test-Path $path) { return $path }
        }
    }

    if ($TargetIde -eq 'vscode') {
        $cmd = Get-Command code -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }

        $paths = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
            (Join-Path ${env:ProgramFiles} 'Microsoft VS Code\bin\code.cmd')
        )
        foreach ($path in $paths) {
            if (Test-Path $path) { return $path }
        }
    }

    return $null
}

function New-WorkspaceDir {
    $folderName = [guid]::NewGuid().ToString()
    $script:WorkDir = Join-Path $env:USERPROFILE "dev\$folderName"
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    Write-Host "Created folder: $WorkDir" -ForegroundColor Green
}

function Copy-ChallengeTemplate {
    if (-not (Test-Path $ChallengeTemplate)) {
        Write-Error "Challenge template not found: $ChallengeTemplate"
    }

    Copy-Item -Path (Join-Path $ChallengeTemplate '*') -Destination $WorkDir -Recurse -Force
    Write-Host 'Workspace template ready.' -ForegroundColor Green
}

function Set-DistributedWorkspace {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Error 'Git is not installed.'
    }

    Write-Host ''
    Write-Host 'Cloning wad-knowledge repository...'

    Push-Location $WorkDir
    try {
        git clone $WadKnowledgeRepo .
        Remove-Item -Path (Join-Path $WorkDir 'README.md') -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $WorkDir '.git') -Recurse -Force -ErrorAction SilentlyContinue
    }
    finally {
        Pop-Location
    }

    $vscodeDir = Join-Path $WorkDir '.vscode'
    New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null

    @'
{
  "task.allowAutomaticTasks": "on"
}
'@ | Set-Content -Path (Join-Path $vscodeDir 'settings.json') -Encoding UTF8

    $gitBash = @(
        (Join-Path ${env:ProgramFiles} 'Git\bin\bash.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($gitBash) {
        $gitBashJson = $gitBash.Replace('\', '\\')
        @"
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Install Graft",
      "type": "shell",
      "command": "curl -fsSL https://grft.dev/get | sh",
      "options": {
        "shell": {
          "executable": "$gitBashJson",
          "args": ["-lc"]
        }
      },
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "new",
        "focus": true
      },
      "runOptions": {
        "runOn": "folderOpen"
      }
    }
  ]
}
"@ | Set-Content -Path (Join-Path $vscodeDir 'tasks.json') -Encoding UTF8
    }
    else {
        @'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Install Graft",
      "type": "shell",
      "command": "curl.exe -fsSL https://grft.dev/get | sh",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "new",
        "focus": true
      },
      "runOptions": {
        "runOn": "folderOpen"
      }
    }
  ]
}
'@ | Set-Content -Path (Join-Path $vscodeDir 'tasks.json') -Encoding UTF8
        Write-Host 'Git Bash not found — install Git for Windows for automatic Graft setup.' -ForegroundColor Yellow
    }

    Write-Host 'Distributed system workspace is ready.' -ForegroundColor Green
}

function Clear-Docker {
    Write-Host ''
    Write-Host 'Cleaning up running Docker containers...'

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host 'Docker is not installed — skipping.' -ForegroundColor Yellow
        return
    }

    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Docker is not running — skipping.' -ForegroundColor Yellow
        return
    }

    $running = docker ps -q 2>$null
    if (-not $running) {
        Write-Host 'No running containers.' -ForegroundColor Yellow
        return
    }

    docker rm -f $running
    Write-Host 'Removed running Docker containers.' -ForegroundColor Green
}

function Reset-McpFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parent = Split-Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Set-Content -Path $Path -Value $Content -Encoding UTF8
    Write-Host "Cleared: $Path" -ForegroundColor Green
}

function Clear-Mcp {
    Write-Host ''
    Write-Host 'Cleaning up MCP configuration...'

    $cursorMcp = Join-Path $env:USERPROFILE '.cursor\mcp.json'
    $cursorUserMcp = Join-Path $env:APPDATA 'Cursor\User\mcp.json'
    $vscodeUserMcp = Join-Path $env:APPDATA 'Code\User\mcp.json'

    Reset-McpFile -Path $cursorMcp -Content @'
{
  "mcpServers": {}
}
'@

    Reset-McpFile -Path $cursorUserMcp -Content @'
{
  "mcpServers": {}
}
'@

    Reset-McpFile -Path $vscodeUserMcp -Content @'
{
  "servers": {},
  "inputs": []
}
'@

    Write-Host 'MCP configuration cleared in Cursor and Visual Studio Code.' -ForegroundColor Green
}

function Set-IdeUserSettings {
    param(
        [ValidateSet('cursor', 'vscode')]
        [string]$TargetIde
    )

    $settingsFile = if ($TargetIde -eq 'cursor') {
        Join-Path $env:APPDATA 'Cursor\User\settings.json'
    }
    else {
        Join-Path $env:APPDATA 'Code\User\settings.json'
    }

    $parent = Split-Path $settingsFile -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-Host ''
    Write-Host "Configuring $TargetIde window settings..."

    $settings = @{}
    if (Test-Path $settingsFile) {
        $raw = Get-Content -Path $settingsFile -Raw -Encoding UTF8
        $jsonText = $raw -replace '(?ms)/\*.*?\*/', '' -replace '(?m)//[^\r\n]*', ''
        if ($jsonText.Trim()) {
            ($jsonText | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
                $settings[$_.Name] = $_.Value
            }
        }
    }

    $settings['window.newWindowDimensions'] = 'maximized'
    if ($TargetIde -eq 'cursor') {
        $settings['cursor.chatMaxWidth'] = $CursorChatMaxWidth
    }

    ($settings | ConvertTo-Json -Depth 10) + [Environment]::NewLine | Set-Content -Path $settingsFile -Encoding UTF8

    Write-Host "Set window.newWindowDimensions to maximized in $TargetIde settings." -ForegroundColor Green
    if ($TargetIde -eq 'cursor') {
        Write-Host "Set cursor.chatMaxWidth to $CursorChatMaxWidth in Cursor settings." -ForegroundColor Green
    }
}

function Start-MaximizeIdeWindow {
    param(
        [ValidateSet('cursor', 'vscode')]
        [string]$TargetIde
    )

    $processName = if ($TargetIde -eq 'cursor') { 'Cursor' } else { 'Code' }

    Start-Job -ScriptBlock {
        param($Name)

        Start-Sleep -Seconds 2

        if (-not ('NativeMethods' -as [type])) {
            Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public const int SW_MAXIMIZE = 3;
}
'@
        }

        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            for ($i = 0; $i -lt 40; $i++) {
                $proc = Get-Process -Name $Name -ErrorAction SilentlyContinue |
                    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
                    Sort-Object StartTime -Descending |
                    Select-Object -First 1

                if ($proc) {
                    [NativeMethods]::ShowWindow($proc.MainWindowHandle, [NativeMethods]::SW_MAXIMIZE) | Out-Null
                    break
                }

                Start-Sleep -Milliseconds 250
            }

            Start-Sleep -Seconds 1
        }
    } -ArgumentList $processName | Out-Null
}

function Stop-IdeIfRunning {
    param([string[]]$ProcessNames)

    foreach ($name in $ProcessNames) {
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        if (-not $processes) { continue }

        Write-Host "Closing $name to clear browser session..." -ForegroundColor Yellow
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Clear-BrowserCookies {
    Write-Host ''
    Write-Host 'Cleaning up IDE browser cookies...'

    Stop-IdeIfRunning -ProcessNames @('Cursor', 'Code')

    $bases = @(
        (Join-Path $env:APPDATA 'Cursor\Partitions'),
        (Join-Path $env:APPDATA 'Code\Partitions')
    )

    $cleared = $false
    foreach ($base in $bases) {
        if (-not (Test-Path $base)) { continue }

        Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Removed browser partition: $($_.FullName)" -ForegroundColor Green
            $cleared = $true
        }
    }

    if (-not $cleared) {
        Write-Host 'No IDE browser data found — skipping.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'IDE browser cookies cleared.' -ForegroundColor Green
    }
}

function Schedule-WorkspaceMetadataCleanup {
    param([string]$Directory)

    $delay = $WorkspaceMetadataCleanupDelay
    Start-Job -ScriptBlock {
        param($WorkDirectory, $Seconds)
        Start-Sleep -Seconds $Seconds
        $vscode = Join-Path $WorkDirectory '.vscode'
        if (Test-Path $vscode) {
            Remove-Item -LiteralPath $vscode -Recurse -Force -ErrorAction SilentlyContinue
        }
    } -ArgumentList $Directory, $delay | Out-Null
}

function Start-ChallengeIde {
    param([string]$IdeCmd)

    $workspaceFile = Join-Path $WorkDir 'graftcode.code-workspace'

    Write-Host ''
    Write-Host "Launching $Ide..."

    Start-Process -FilePath $IdeCmd -ArgumentList @('-n', $workspaceFile)
    Start-MaximizeIdeWindow -TargetIde $Ide
    Schedule-WorkspaceMetadataCleanup -Directory $WorkDir

    Write-Host ''
    Write-Host "Done! $Ide is opening $GraftcodeUrl in the internal browser." -ForegroundColor Green
    Write-Host "Workspace: $workspaceFile" -ForegroundColor Cyan
}

function Start-DistributedIde {
    $cursorCmd = Find-IdeCmd -TargetIde 'cursor'
    if (-not $cursorCmd) {
        Write-Error 'Cursor not found. Install Cursor and add it to your PATH.'
    }

    Write-Host ''
    Write-Host 'Launching Cursor...'

    Start-Process -FilePath $cursorCmd -ArgumentList @('-n', $WorkDir)
    Start-MaximizeIdeWindow -TargetIde 'cursor'
    Schedule-WorkspaceMetadataCleanup -Directory $WorkDir

    Write-Host ''
    Write-Host 'Done! Cursor opened in the distributed system folder.' -ForegroundColor Green
    Write-Host "Folder: $WorkDir" -ForegroundColor Cyan
}

function Invoke-Challenge {
    Choose-Ide
    $ideCmd = Find-IdeCmd -TargetIde $Ide
    if (-not $ideCmd) {
        Write-Error "$Ide not found. Install the IDE and add it to your PATH."
    }

    New-WorkspaceDir
    Clear-Docker
    Clear-Mcp
    Clear-BrowserCookies
    Set-IdeUserSettings -TargetIde $Ide
    Copy-ChallengeTemplate
    Start-ChallengeIde -IdeCmd $ideCmd
}

function Invoke-Distributed {
    New-WorkspaceDir
    Clear-Docker
    Clear-Mcp
    Clear-BrowserCookies
    Set-IdeUserSettings -TargetIde 'cursor'
    Set-DistributedWorkspace
    Start-DistributedIde
}

Show-Banner
Choose-Mode

switch ($Mode) {
    'challenge' { Invoke-Challenge }
    'distributed' { Invoke-Distributed }
}
