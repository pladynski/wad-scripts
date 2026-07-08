#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$ChallengeTemplate = Join-Path $ScriptDir 'templates\graftcode-challenge'
$GraftcodeUrl = 'https://wad.graftcode.com'
$WadKnowledgeRepo = 'https://github.com/pladynski/wad-knowledge'
$WorkspaceMetadataCleanupDelay = 10
$CursorChatPanelWidth = 400
$MainStageRoot = 'C:\dev'
$MainStageProjects = @(
    (Join-Path $MainStageRoot 'wad-knowledge'),
    (Join-Path $MainStageRoot 'wad-speckit'),
    (Join-Path $MainStageRoot 'wad-graft-demo'),
    (Join-Path $MainStageRoot 'wad-rest-demo')
)
$MainStageDockerComposeProjects = @(
    (Join-Path $MainStageRoot 'wad-graft-demo'),
    (Join-Path $MainStageRoot 'wad-rest-demo')
)

$Mode = ''
$Ide = ''
$WorkDir = ''

function Show-Banner {
    Clear-Host
    Write-Host @'
   ____ ____      _    _____ _____ ____ ___  ____  _____
  / ___|  _ \    / \  |  ___|_   _/ ___/ _ \|  _ \| ____|
 | |  _| |_) |  / _ \ | |_    | || |  | | | | | | |  _|
 | |_| |  _ <  / ___ \|  _|   | || |__| |_| | |_| | |___
  \____|_| \_\/_/   \_\_|     |_| \____\___/|____/|_____|

   ____ _   _    _    _     _     _____ _   _  ____ _____
  / ___| | | |  / \  | |   | |   | ____| \ | |/ ___| ____|
 | |   | |_| | / _ \ | |   | |   |  _| |  \| | |  _|  _|
 | |___|  _  |/ ___ \| |___| |___| |___| |\  | |_| | |___
  \____|_| |_/_/   \_\_____|_____|_____|_| \_|\____|_____|
'@ -ForegroundColor Cyan
    Write-Host 'Welcome to the world of Graftcode!' -ForegroundColor Yellow
    Write-Host ''
}

function Choose-Mode {
    Write-Host 'What would you like to do?'
    Write-Host '  1) Graftcode Challenge'
    Write-Host '  2) Build a distributed system using Graftcode'
    Write-Host '  3) Main Stage Session'
    Write-Host ''

    while ($true) {
        $choice = Read-Host 'Your choice [1/2/3]'
        switch ($choice) {
            '1' { $script:Mode = 'challenge'; return }
            '2' { $script:Mode = 'distributed'; return }
            '3' { $script:Mode = 'mainstage'; return }
            default { Write-Host 'Invalid choice. Enter 1, 2, or 3.' -ForegroundColor Red }
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

function Stop-BuildProcesses {
    Write-Host ''
    Write-Host 'Stopping esbuild and node processes...'

    $stopped = $false
    foreach ($name in @('esbuild', 'node')) {
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        if (-not $processes) { continue }

        Write-Host "Stopping $name processes..." -ForegroundColor Yellow
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
        $stopped = $true
    }

    if ($stopped) {
        Start-Sleep -Seconds 1
        Write-Host 'Stopped esbuild and node processes.' -ForegroundColor Green
    }
    else {
        Write-Host 'No esbuild or node processes running — skipping.' -ForegroundColor Yellow
    }
}

function Reset-WorkspaceDir {
    $script:WorkDir = Join-Path $env:USERPROFILE 'dev\graftcode_challenge'
    if (Test-Path $WorkDir) {
        Remove-Item -Path $WorkDir -Recurse -Force
        Write-Host "Cleaned existing folder: $WorkDir" -ForegroundColor Yellow
    }
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

function Write-Utf8TextFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parent = Split-Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-PythonLauncher {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        return @{ Command = 'py'; PrefixArgs = @('-3') }
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        return @{ Command = 'python'; PrefixArgs = @() }
    }
    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        return @{ Command = 'python3'; PrefixArgs = @() }
    }

    return $null
}

function Update-JsonSettingsFile {
    param(
        [string]$Path,
        [ValidateSet('cursor', 'vscode', 'workspace')]
        [string]$Scope,
        [string]$WindowDimensions = 'maximized'
    )

    $parent = Split-Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $python = Get-PythonLauncher
    if ($python) {
        $env:SETTINGS_FILE = $Path
        $env:SCOPE = $Scope
        $env:WINDOW_DIMENSIONS = $WindowDimensions
        $env:CHAT_PANEL_WIDTH = [string]$CursorChatPanelWidth

        $pyScript = @'
import json
import os
import re

path = os.environ["SETTINGS_FILE"]
scope = os.environ["SCOPE"]


def load_settings(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = re.sub(r"//.*?$", "", text, flags=re.MULTILINE)
    text = text.strip()
    if not text:
        return {}
    return json.loads(text)


data = {}
if os.path.isfile(path):
    with open(path, encoding="utf-8-sig") as f:
        data = load_settings(f.read())

if scope == "workspace":
    data["task.allowAutomaticTasks"] = "on"
    data["workbench.editor.restoreViewState"] = False
    data["files.hotExit"] = "off"

if scope != "workspace":
    data["window.newWindowDimensions"] = os.environ["WINDOW_DIMENSIONS"]

if scope in ("cursor", "workspace"):
    data["cursor.chatMaxWidth"] = int(os.environ["CHAT_PANEL_WIDTH"])

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
'@

        $pyFile = [System.IO.Path]::GetTempFileName() + '.py'
        try {
            Write-Utf8TextFile -Path $pyFile -Content $pyScript
            & $python.Command @($python.PrefixArgs + $pyFile) | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Python settings update failed with exit code $LASTEXITCODE"
            }
        }
        finally {
            Remove-Item Env:SETTINGS_FILE, Env:SCOPE, Env:WINDOW_DIMENSIONS, Env:CHAT_PANEL_WIDTH -ErrorAction SilentlyContinue
            if (Test-Path $pyFile) {
                Remove-Item -LiteralPath $pyFile -Force -ErrorAction SilentlyContinue
            }
        }

        return
    }

    $content = if (Test-Path $Path) { [System.IO.File]::ReadAllText($Path) } else { '{}' }
    $content = $content.Trim()
    if (-not $content) { $content = '{}' }

    if ($Scope -eq 'workspace') {
        $content = Set-JsonSettingValue -Content $content -Key 'task.allowAutomaticTasks' -Value 'on'
        $content = Set-JsonSettingValue -Content $content -Key 'workbench.editor.restoreViewState' -Value 'false' -IsBoolean
        $content = Set-JsonSettingValue -Content $content -Key 'files.hotExit' -Value 'off'
    }

    if ($Scope -ne 'workspace') {
        $content = Set-JsonSettingValue -Content $content -Key 'window.newWindowDimensions' -Value $WindowDimensions
    }

    if ($Scope -in @('cursor', 'workspace')) {
        $content = Set-JsonSettingValue -Content $content -Key 'cursor.chatMaxWidth' -Value ([string]$CursorChatPanelWidth) -IsNumber
    }

    Write-Utf8TextFile -Path $Path -Content ($content.TrimEnd() + [Environment]::NewLine)
}

function Set-JsonSettingValue {
    param(
        [string]$Content,
        [string]$Key,
        [string]$Value,
        [switch]$IsNumber,
        [switch]$IsBoolean
    )

    $escapedKey = [regex]::Escape($Key)
    $replacement = if ($IsBoolean) {
        "`"$Key`": $Value"
    }
    elseif ($IsNumber) {
        "`"$Key`": $Value"
    }
    else {
        "`"$Key`": `"$Value`""
    }

    if ($Content -match "`"$escapedKey`"\s*:") {
        if ($IsNumber -or $IsBoolean) {
            return [regex]::Replace($Content, "`"$escapedKey`"\s*:\s*[^,\r\n\}]+", $replacement)
        }

        return [regex]::Replace($Content, "`"$escapedKey`"\s*:\s*`"[^`"]*`"", $replacement)
    }

    $entry = "  $replacement"
    if ($Content -match '^\{\s*\}$') {
        return "{`r`n$entry`r`n}"
    }

    return [regex]::Replace($Content, '\}\s*$', ",`r`n$entry`r`n}")
}

function Get-CursorStatePythonScript {
    return @'
import json
import os
import sqlite3

db_path = os.environ["STATE_DB"]
width = int(os.environ["PANEL_WIDTH"])

conn = sqlite3.connect(db_path)
cur = conn.cursor()


def upsert(key, value):
    cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (key, value))


upsert("workbench.auxiliaryBar.size", str(width))

updated_layout_keys = set()
cur.execute("SELECT key, value FROM ItemTable WHERE key LIKE 'agentLayout.shared.%'")
for key, value in cur.fetchall():
    try:
        layout = json.loads(value)
    except json.JSONDecodeError:
        continue
    if not isinstance(layout, dict):
        continue
    layout["auxiliaryBarWidth"] = width
    layout["auxiliaryBarVisible"] = True
    upsert(key, json.dumps(layout, separators=(",", ":")))
    updated_layout_keys.add(key)

if not updated_layout_keys:
    layout = {
        "auxiliaryBarVisible": True,
        "auxiliaryBarWidth": width,
        "editorVisible": True,
        "panelVisible": False,
        "sidebarVisible": True,
        "statusBarVisible": True,
    }
    upsert("agentLayout.shared.v6", json.dumps(layout, separators=(",", ":")))

cur.execute("SELECT key, value FROM ItemTable WHERE value LIKE '%auxiliaryBarWidth%'")
for key, value in cur.fetchall():
    if key in updated_layout_keys or key == "workbench.auxiliaryBar.size":
        continue
    try:
        data = json.loads(value)
    except json.JSONDecodeError:
        continue
    if isinstance(data, dict) and "auxiliaryBarWidth" in data:
        data["auxiliaryBarWidth"] = width
        if "auxiliaryBarVisible" in data:
            data["auxiliaryBarVisible"] = True
        upsert(key, json.dumps(data, separators=(",", ":")))

conn.commit()
conn.close()
'@
}

function Get-Sqlite3Command {
    $paths = @(
        (Join-Path ${env:ProgramFiles} 'Git\usr\bin\sqlite3.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\usr\bin\sqlite3.exe')
    )

    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }

    return $null
}

function Invoke-CursorStateDatabaseUpdate {
    param(
        [string]$StateDbPath,
        [int]$Width
    )

    if (-not $StateDbPath -or -not (Test-Path (Split-Path $StateDbPath -Parent))) {
        return $false
    }

    if (-not (Test-Path $StateDbPath)) {
        $sqlite3 = Get-Sqlite3Command
        if ($sqlite3) {
            & $sqlite3 $StateDbPath "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);" | Out-Null
        }
    }

    if (-not (Test-Path $StateDbPath)) {
        return $false
    }

    $python = Get-PythonLauncher
    if ($python) {
        $env:STATE_DB = $StateDbPath
        $env:PANEL_WIDTH = [string]$Width
        $pyFile = [System.IO.Path]::GetTempFileName() + '.py'

        try {
            Write-Utf8TextFile -Path $pyFile -Content (Get-CursorStatePythonScript)
            $output = & $python.Command @($python.PrefixArgs + $pyFile) 2>&1
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                throw "Python state update failed: $output"
            }
            return $true
        }
        finally {
            Remove-Item Env:STATE_DB, Env:PANEL_WIDTH -ErrorAction SilentlyContinue
            if (Test-Path $pyFile) {
                Remove-Item -LiteralPath $pyFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $sqlite3 = Get-Sqlite3Command
    if ($sqlite3) {
        & $sqlite3 $StateDbPath "INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('workbench.auxiliaryBar.size', '$Width');" | Out-Null
        return $true
    }

    return $false
}

function Get-CursorWorkspaceStorageCandidates {
    param([string]$WorkDirectory)

    $fullPath = [System.IO.Path]::GetFullPath($WorkDirectory)
    $candidates = New-Object System.Collections.Generic.List[string]
    $md5 = [System.Security.Cryptography.MD5]::Create()

    $pathVariants = @(
        $fullPath,
        $fullPath.ToLowerInvariant(),
        ([Uri]$fullPath).AbsoluteUri,
        ([Uri]$fullPath).AbsoluteUri.ToLowerInvariant()
    )

    foreach ($pathVariant in ($pathVariants | Select-Object -Unique)) {
        $hash = -join ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($pathVariant)) | ForEach-Object { $_.ToString('x2') })
        $candidates.Add($hash)
    }

    return $candidates | Select-Object -Unique
}

function Initialize-CursorWorkspaceStorage {
    param(
        [string]$WorkDirectory,
        [int]$Width
    )

    $storageRoot = Join-Path $env:APPDATA 'Cursor\User\workspaceStorage'
    if (-not (Test-Path $storageRoot)) {
        New-Item -ItemType Directory -Path $storageRoot -Force | Out-Null
    }

    $fullPath = [System.IO.Path]::GetFullPath($WorkDirectory)
    $folderUri = ([Uri]$fullPath).AbsoluteUri
    $workspaceJson = (@{ folder = $folderUri } | ConvertTo-Json -Compress)

    foreach ($storageId in Get-CursorWorkspaceStorageCandidates -WorkDirectory $WorkDirectory) {
        $workspaceFolder = Join-Path $storageRoot $storageId
        if (-not (Test-Path $workspaceFolder)) {
            New-Item -ItemType Directory -Path $workspaceFolder -Force | Out-Null
        }

        Write-Utf8TextFile -Path (Join-Path $workspaceFolder 'workspace.json') -Content ($workspaceJson + [Environment]::NewLine)

        $stateDb = Join-Path $workspaceFolder 'state.vscdb'
        if (-not (Test-Path $stateDb)) {
            $sqlite3 = Get-Sqlite3Command
            if ($sqlite3) {
                & $sqlite3 $stateDb "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);" | Out-Null
            }
            else {
                $python = Get-PythonLauncher
                if ($python) {
                    $env:STATE_DB = $stateDb
                    $initFile = [System.IO.Path]::GetTempFileName() + '.py'
                    try {
                        Write-Utf8TextFile -Path $initFile -Content @'
import os, sqlite3
conn = sqlite3.connect(os.environ["STATE_DB"])
conn.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
conn.commit()
conn.close()
'@
                        & $python.Command @($python.PrefixArgs + $initFile) | Out-Null
                    }
                    finally {
                        Remove-Item Env:STATE_DB -ErrorAction SilentlyContinue
                        if (Test-Path $initFile) {
                            Remove-Item -LiteralPath $initFile -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }

        if (Test-Path $stateDb) {
            Invoke-CursorStateDatabaseUpdate -StateDbPath $stateDb -Width $Width | Out-Null
        }
    }
}

function Find-CursorWorkspaceStateDatabases {
    param([string]$WorkDirectory)

    $stateDbs = New-Object System.Collections.Generic.List[string]
    $storageRoot = Join-Path $env:APPDATA 'Cursor\User\workspaceStorage'
    $fullPath = [System.IO.Path]::GetFullPath($WorkDirectory)

    foreach ($storageId in Get-CursorWorkspaceStorageCandidates -WorkDirectory $WorkDirectory) {
        $stateDb = Join-Path $storageRoot "$storageId\state.vscdb"
        if (Test-Path $stateDb) {
            $stateDbs.Add($stateDb)
        }
    }

    if (-not (Test-Path $storageRoot)) {
        return $stateDbs
    }

    foreach ($entry in Get-ChildItem -Path $storageRoot -Directory -ErrorAction SilentlyContinue) {
        $workspaceJson = Join-Path $entry.FullName 'workspace.json'
        $stateDb = Join-Path $entry.FullName 'state.vscdb'
        if (-not (Test-Path $workspaceJson) -or -not (Test-Path $stateDb)) { continue }

        $text = [System.IO.File]::ReadAllText($workspaceJson)
        if ($text -like "*$fullPath*" -or $text -like "*$($fullPath.Replace('\', '/'))*") {
            if (-not $stateDbs.Contains($stateDb)) {
                $stateDbs.Add($stateDb)
            }
        }
    }

    return $stateDbs
}

function Update-CursorChatPanelState {
    param(
        [string]$WorkDirectory,
        [int]$Width
    )

    $updated = $false
    $globalStateDb = Join-Path $env:APPDATA 'Cursor\User\globalStorage\state.vscdb'
    if (Invoke-CursorStateDatabaseUpdate -StateDbPath $globalStateDb -Width $Width) {
        $updated = $true
    }

    if ($WorkDirectory) {
        Initialize-CursorWorkspaceStorage -WorkDirectory $WorkDirectory -Width $Width | Out-Null
        foreach ($stateDb in Find-CursorWorkspaceStateDatabases -WorkDirectory $WorkDirectory) {
            if (Invoke-CursorStateDatabaseUpdate -StateDbPath $stateDb -Width $Width) {
                $updated = $true
            }
        }
    }

    return $updated
}

function Set-CursorChatPanelWidth {
    param([string]$WorkDirectory)

    Write-Host ''
    Write-Host 'Configuring Cursor chat panel width...'

    if (-not (Update-CursorChatPanelState -WorkDirectory $WorkDirectory -Width $CursorChatPanelWidth)) {
        Write-Host 'Could not update Cursor layout database. Install Python or Git for Windows (sqlite3).' -ForegroundColor Yellow
    }
    else {
        Write-Host "Set Cursor chat panel width to $CursorChatPanelWidth px." -ForegroundColor Green
    }
}

function Schedule-CursorChatPanelWidth {
    param(
        [string]$WorkDirectory,
        [int]$Width = $CursorChatPanelWidth
    )

    Start-Job -ScriptBlock {
        param($Directory, $PanelWidth)

        function Get-PythonLauncherLocal {
            if (Get-Command py -ErrorAction SilentlyContinue) { return @{ Command = 'py'; PrefixArgs = @('-3') } }
            if (Get-Command python -ErrorAction SilentlyContinue) { return @{ Command = 'python'; PrefixArgs = @() } }
            if (Get-Command python3 -ErrorAction SilentlyContinue) { return @{ Command = 'python3'; PrefixArgs = @() } }
            return $null
        }

        foreach ($delay in @(4, 10, 18)) {
            Start-Sleep -Seconds $delay

            $globalDb = Join-Path $env:APPDATA 'Cursor\User\globalStorage\state.vscdb'
            if (Test-Path $globalDb) {
                $env:STATE_DB = $globalDb
                $env:PANEL_WIDTH = [string]$PanelWidth
                $python = Get-PythonLauncherLocal
                if ($python) {
                    $pyFile = [System.IO.Path]::GetTempFileName() + '.py'
                    try {
                        $script = @'
import json, os, sqlite3
db_path = os.environ["STATE_DB"]
width = int(os.environ["PANEL_WIDTH"])
conn = sqlite3.connect(db_path)
cur = conn.cursor()
def upsert(key, value):
    cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (key, value))
upsert("workbench.auxiliaryBar.size", str(width))
cur.execute("SELECT key, value FROM ItemTable WHERE key LIKE 'agentLayout.shared.%'")
for key, value in cur.fetchall():
    try:
        layout = json.loads(value)
    except json.JSONDecodeError:
        continue
    if isinstance(layout, dict):
        layout["auxiliaryBarWidth"] = width
        layout["auxiliaryBarVisible"] = True
        upsert(key, json.dumps(layout, separators=(",", ":")))
conn.commit()
conn.close()
'@
                        [System.IO.File]::WriteAllText($pyFile, $script, [System.Text.UTF8Encoding]::new($false))
                        & $python.Command @($python.PrefixArgs + $pyFile) | Out-Null
                    }
                    finally {
                        Remove-Item Env:STATE_DB, Env:PANEL_WIDTH -ErrorAction SilentlyContinue
                        if (Test-Path $pyFile) { Remove-Item -LiteralPath $pyFile -Force -ErrorAction SilentlyContinue }
                    }
                }
            }

            $storageRoot = Join-Path $env:APPDATA 'Cursor\User\workspaceStorage'
            if ((Test-Path $storageRoot) -and $Directory) {
                foreach ($entry in Get-ChildItem -Path $storageRoot -Directory -ErrorAction SilentlyContinue) {
                    $workspaceJson = Join-Path $entry.FullName 'workspace.json'
                    $stateDb = Join-Path $entry.FullName 'state.vscdb'
                    if (-not (Test-Path $workspaceJson) -or -not (Test-Path $stateDb)) { continue }
                    $text = [System.IO.File]::ReadAllText($workspaceJson)
                    if ($text -notlike "*$Directory*") { continue }

                    $env:STATE_DB = $stateDb
                    $env:PANEL_WIDTH = [string]$PanelWidth
                    $python = Get-PythonLauncherLocal
                    if ($python) {
                        $pyFile = [System.IO.Path]::GetTempFileName() + '.py'
                        try {
                            $script = @'
import json, os, sqlite3
db_path = os.environ["STATE_DB"]
width = int(os.environ["PANEL_WIDTH"])
conn = sqlite3.connect(db_path)
cur = conn.cursor()
def upsert(key, value):
    cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (key, value))
upsert("workbench.auxiliaryBar.size", str(width))
cur.execute("SELECT key, value FROM ItemTable WHERE key LIKE 'agentLayout.shared.%'")
for key, value in cur.fetchall():
    try:
        layout = json.loads(value)
    except json.JSONDecodeError:
        continue
    if isinstance(layout, dict):
        layout["auxiliaryBarWidth"] = width
        layout["auxiliaryBarVisible"] = True
        upsert(key, json.dumps(layout, separators=(",", ":")))
conn.commit()
conn.close()
'@
                            [System.IO.File]::WriteAllText($pyFile, $script, [System.Text.UTF8Encoding]::new($false))
                            & $python.Command @($python.PrefixArgs + $pyFile) | Out-Null
                        }
                        finally {
                            Remove-Item Env:STATE_DB, Env:PANEL_WIDTH -ErrorAction SilentlyContinue
                            if (Test-Path $pyFile) { Remove-Item -LiteralPath $pyFile -Force -ErrorAction SilentlyContinue }
                        }
                    }
                }
            }
        }
    } -ArgumentList $WorkDirectory, $Width | Out-Null
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

    Update-JsonSettingsFile -Path (Join-Path $vscodeDir 'settings.json') -Scope workspace

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
    Write-Host 'Cleaning up Docker containers and networks...'

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host 'Docker is not installed — skipping.' -ForegroundColor Yellow
        return
    }

    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Docker is not running — skipping.' -ForegroundColor Yellow
        return
    }

    $containers = docker ps -aq 2>$null
    if ($containers) {
        docker rm -f $containers
        Write-Host 'Removed Docker containers.' -ForegroundColor Green
    }
    else {
        Write-Host 'No Docker containers.' -ForegroundColor Yellow
    }

    $networks = docker network ls --format '{{.Name}}' 2>$null |
        Where-Object { $_ -notin @('bridge', 'host', 'none') }
    if ($networks) {
        docker network rm $networks 2>$null
        Write-Host 'Removed Docker networks.' -ForegroundColor Green
    }
    else {
        Write-Host 'No custom Docker networks.' -ForegroundColor Yellow
    }
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

    Write-Host ''
    Write-Host "Configuring $TargetIde window settings..."

    Update-JsonSettingsFile -Path $settingsFile -Scope $TargetIde -WindowDimensions 'maximized'

    Write-Host "Set window.newWindowDimensions to maximized in $TargetIde settings." -ForegroundColor Green
    if ($TargetIde -eq 'cursor') {
        Write-Host "Set cursor.chatMaxWidth to $CursorChatPanelWidth in Cursor settings." -ForegroundColor Green
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

function Clear-CursorWorkspaceSession {
    $workDir = Join-Path $env:USERPROFILE 'dev\graftcode_challenge'
    $workspaceFile = Join-Path $workDir 'graftcode.code-workspace'
    $pathVariants = @(
        [System.IO.Path]::GetFullPath($workDir),
        [System.IO.Path]::GetFullPath($workspaceFile)
    )

    Write-Host ''
    Write-Host 'Clearing Cursor workspace session (tabs, editors)...'

    $cleared = $false
    $storageRoot = Join-Path $env:APPDATA 'Cursor\User\workspaceStorage'
    if (Test-Path $storageRoot) {
        foreach ($entry in Get-ChildItem -Path $storageRoot -Directory -ErrorAction SilentlyContinue) {
            $workspaceJson = Join-Path $entry.FullName 'workspace.json'
            if (-not (Test-Path $workspaceJson)) { continue }

            $text = [System.IO.File]::ReadAllText($workspaceJson)
            $shouldRemove = $text -match 'graftcode_challenge'
            if (-not $shouldRemove) {
                foreach ($pathVariant in $pathVariants) {
                    $normalized = $pathVariant.Replace('\', '/')
                    if ($text -like "*$pathVariant*" -or $text -like "*$normalized*") {
                        $shouldRemove = $true
                        break
                    }
                }
            }

            if (-not $shouldRemove) { continue }

            Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Removed Cursor workspace storage: $($entry.Name)" -ForegroundColor Green
            $cleared = $true
        }
    }

    $projectsRoot = Join-Path $env:USERPROFILE '.cursor\projects'
    if (Test-Path $projectsRoot) {
        foreach ($entry in Get-ChildItem -Path $projectsRoot -Directory -ErrorAction SilentlyContinue) {
            if ($entry.Name -notmatch 'graftcode[-_]challenge') { continue }

            Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Removed Cursor project data: $($entry.Name)" -ForegroundColor Green
            $cleared = $true
        }
    }

    if (-not $cleared) {
        Write-Host 'No Cursor session data found for graftcode challenge — skipping.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Cursor session cleared.' -ForegroundColor Green
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
    if ($Ide -eq 'cursor') {
        Schedule-CursorChatPanelWidth -WorkDirectory $WorkDir
    }
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
    Schedule-CursorChatPanelWidth -WorkDirectory $WorkDir
    Schedule-WorkspaceMetadataCleanup -Directory $WorkDir

    Write-Host ''
    Write-Host 'Done! Cursor opened in the distributed system folder.' -ForegroundColor Green
    Write-Host "Folder: $WorkDir" -ForegroundColor Cyan
}

function Initialize-ChallengeEnvironment {
    param(
        [ValidateSet('cursor', 'vscode')]
        [string]$TargetIde = 'cursor'
    )

    Clear-Docker
    Clear-Mcp
    Clear-BrowserCookies
    Clear-CursorWorkspaceSession
    Stop-BuildProcesses
    Reset-WorkspaceDir
    Set-IdeUserSettings -TargetIde $TargetIde
    if ($TargetIde -eq 'cursor') {
        Set-CursorChatPanelWidth -WorkDirectory $WorkDir
    }
}

function Start-DockerComposeUp {
    param([string]$ProjectDirectory)

    if (-not (Test-Path $ProjectDirectory)) {
        Write-Error "Project folder not found: $ProjectDirectory"
    }

    $composeFile = @(
        (Join-Path $ProjectDirectory 'docker-compose.yml'),
        (Join-Path $ProjectDirectory 'docker-compose.yaml')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $composeFile) {
        Write-Host "No docker-compose file in $ProjectDirectory - skipping." -ForegroundColor Yellow
        return
    }

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host "Docker is not installed - skipping compose in $ProjectDirectory." -ForegroundColor Yellow
        return
    }

    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Docker is not running - skipping compose in $ProjectDirectory." -ForegroundColor Yellow
        return
    }

    Write-Host "Starting docker compose in $ProjectDirectory..."
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/k', 'docker compose up' -WorkingDirectory $ProjectDirectory
    Write-Host "Docker compose started in $ProjectDirectory." -ForegroundColor Green
}

function Start-MainStageSession {
    $cursorCmd = Find-IdeCmd -TargetIde 'cursor'
    if (-not $cursorCmd) {
        Write-Error 'Cursor not found. Install Cursor and add it to your PATH.'
    }

    foreach ($projectDir in $MainStageProjects) {
        if (-not (Test-Path $projectDir)) {
            Write-Error "Project folder not found: $projectDir"
        }
    }

    Write-Host ''
    Write-Host 'Launching Main Stage Session...'

    foreach ($projectDir in $MainStageProjects) {
        Write-Host "Opening Cursor in $projectDir"
        Start-Process -FilePath $cursorCmd -ArgumentList @('-n', $projectDir)
        Start-Sleep -Milliseconds 500
    }

    foreach ($projectDir in $MainStageDockerComposeProjects) {
        Start-DockerComposeUp -ProjectDirectory $projectDir
    }

    Start-MaximizeIdeWindow -TargetIde 'cursor'

    Write-Host ''
    Write-Host 'Done! Main Stage Session is ready.' -ForegroundColor Green
    foreach ($projectDir in $MainStageProjects) {
        Write-Host "  $projectDir" -ForegroundColor Cyan
    }
}

function Invoke-Challenge {
    Choose-Ide
    $ideCmd = Find-IdeCmd -TargetIde $Ide
    if (-not $ideCmd) {
        Write-Error "$Ide not found. Install the IDE and add it to your PATH."
    }

    Initialize-ChallengeEnvironment -TargetIde $Ide
    Copy-ChallengeTemplate
    Start-ChallengeIde -IdeCmd $ideCmd
}

function Invoke-Distributed {
    Initialize-ChallengeEnvironment -TargetIde 'cursor'
    Set-DistributedWorkspace
    Start-DistributedIde
}

function Invoke-MainStage {
    Initialize-ChallengeEnvironment -TargetIde 'cursor'
    Start-MainStageSession
}

Show-Banner
Choose-Mode

switch ($Mode) {
    'challenge' { Invoke-Challenge }
    'distributed' { Invoke-Distributed }
    'mainstage' { Invoke-MainStage }
}
