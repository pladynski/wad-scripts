#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHALLENGE_TEMPLATE="${SCRIPT_DIR}/templates/graftcode-challenge"

GRAFTCODE_URL="https://wad.graftcode.com"
WAD_KNOWLEDGE_REPO="https://github.com/pladynski/wad-knowledge"
WORKSPACE_METADATA_CLEANUP_DELAY=10
CURSOR_CHAT_PANEL_WIDTH=400

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) MAIN_STAGE_ROOT="/c/dev" ;;
  *) MAIN_STAGE_ROOT="${HOME}/dev" ;;
esac

MAIN_STAGE_PROJECTS=(
  "${MAIN_STAGE_ROOT}/wad-knowledge"
  "${MAIN_STAGE_ROOT}/wad-speckit"
  "${MAIN_STAGE_ROOT}/wad-graft-demo"
  "${MAIN_STAGE_ROOT}/wad-rest-demo"
)

MAIN_STAGE_DOCKER_COMPOSE_PROJECTS=(
  "${MAIN_STAGE_ROOT}/wad-graft-demo"
  "${MAIN_STAGE_ROOT}/wad-rest-demo"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

MODE=""
IDE=""
WORK_DIR=""

show_banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  cat <<'EOF'
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
EOF
  echo -e "${NC}"
  echo -e "${YELLOW}Welcome to the world of Graftcode!${NC}"
  echo
}

choose_mode() {
  echo -e "${BOLD}What would you like to do?${NC}"
  echo "  1) Graftcode Challenge"
  echo "  2) Build a distributed system using Graftcode"
  echo "  3) Main Stage Session"
  echo
  while true; do
    read -r -p "Your choice [1/2/3]: " choice
    case "$choice" in
      1) MODE="challenge"; return ;;
      2) MODE="distributed"; return ;;
      3) MODE="mainstage"; return ;;
      *) echo -e "${RED}Invalid choice. Enter 1, 2, or 3.${NC}" ;;
    esac
  done
}

choose_ide() {
  echo -e "${BOLD}Choose your IDE:${NC}"
  echo "  1) Cursor"
  echo "  2) Visual Studio Code"
  echo
  while true; do
    read -r -p "Your choice [1/2]: " choice
    case "$choice" in
      1) IDE="cursor"; return ;;
      2) IDE="vscode"; return ;;
      *) echo -e "${RED}Invalid choice. Enter 1 or 2.${NC}" ;;
    esac
  done
}

find_ide_cmd() {
  case "$IDE" in
    cursor)
      if command -v cursor >/dev/null 2>&1; then
        echo "cursor"
        return 0
      fi
      ;;
    vscode)
      if command -v code >/dev/null 2>&1; then
        echo "code"
        return 0
      fi
      local vscode_bin="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
      if [[ -x "$vscode_bin" ]]; then
        echo "$vscode_bin"
        return 0
      fi
      ;;
  esac
  return 1
}

find_cursor_cmd() {
  if command -v cursor >/dev/null 2>&1; then
    echo "cursor"
    return 0
  fi
  return 1
}

reset_workspace_dir() {
  WORK_DIR="${HOME}/dev/graftcode_challenge"
  if [[ -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
    echo -e "${YELLOW}Cleaned existing folder:${NC} ${WORK_DIR}"
  fi
  mkdir -p "$WORK_DIR"
  echo -e "${GREEN}Created folder:${NC} ${WORK_DIR}"
}

stop_build_processes() {
  local name
  local stopped=false

  echo
  echo -e "${BOLD}Stopping esbuild and node processes...${NC}"

  for name in esbuild node; do
    if ! pgrep -x "$name" >/dev/null 2>&1; then
      continue
    fi

    echo -e "${YELLOW}Stopping ${name} processes...${NC}"
    pkill -9 "$name" 2>/dev/null || true
    stopped=true
  done

  if [[ "$stopped" == true ]]; then
    sleep 1
    echo -e "${GREEN}Stopped esbuild and node processes.${NC}"
  else
    echo -e "${YELLOW}No esbuild or node processes running — skipping.${NC}"
  fi
}

copy_challenge_template() {
  if [[ ! -d "$CHALLENGE_TEMPLATE" ]]; then
    echo -e "${RED}Challenge template not found: ${CHALLENGE_TEMPLATE}${NC}" >&2
    exit 1
  fi

  cp -R "${CHALLENGE_TEMPLATE}/." "$WORK_DIR/"
  echo -e "${GREEN}Workspace template ready.${NC}"
}

setup_distributed_workspace() {
  if ! command -v git >/dev/null 2>&1; then
    echo -e "${RED}Git is not installed.${NC}" >&2
    exit 1
  fi

  echo
  echo -e "${BOLD}Cloning wad-knowledge repository...${NC}"
  (
    cd "$WORK_DIR"
    git clone "$WAD_KNOWLEDGE_REPO" .
    rm -f README.md
    rm -rf .git
  )

  mkdir -p "${WORK_DIR}/.vscode"

  cat > "${WORK_DIR}/.vscode/settings.json" <<'JSON'
{
  "task.allowAutomaticTasks": "on",
  "workbench.editor.restoreViewState": false,
  "files.hotExit": "off"
}
JSON

  cat > "${WORK_DIR}/.vscode/tasks.json" <<'JSON'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Install Graft",
      "type": "shell",
      "command": "curl -fsSL https://grft.dev/get | sh",
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
JSON

  echo -e "${GREEN}Distributed system workspace is ready.${NC}"
}

cleanup_docker() {
  echo
  echo -e "${BOLD}Cleaning up Docker containers and networks...${NC}"

  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}Docker is not installed — skipping.${NC}"
    return 0
  fi

  if ! docker info >/dev/null 2>&1; then
    echo -e "${YELLOW}Docker is not running — skipping.${NC}"
    return 0
  fi

  local containers
  containers="$(docker ps -aq 2>/dev/null || true)"

  if [[ -n "$containers" ]]; then
    # shellcheck disable=SC2086
    docker rm -f $containers
    echo -e "${GREEN}Removed Docker containers.${NC}"
  else
    echo -e "${YELLOW}No Docker containers.${NC}"
  fi

  local networks
  networks="$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -v -E '^(bridge|host|none)$' || true)"

  if [[ -n "$networks" ]]; then
    # shellcheck disable=SC2086
    docker network rm $networks 2>/dev/null || true
    echo -e "${GREEN}Removed Docker networks.${NC}"
  else
    echo -e "${YELLOW}No custom Docker networks.${NC}"
  fi
}

reset_mcp_file() {
  local path="$1"
  local content="$2"

  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  echo -e "${GREEN}Cleared:${NC} ${path}"
}

cleanup_mcp() {
  echo
  echo -e "${BOLD}Cleaning up MCP configuration...${NC}"

  local cursor_mcp="${HOME}/.cursor/mcp.json"
  local cursor_user_mcp="${HOME}/Library/Application Support/Cursor/User/mcp.json"
  local vscode_user_mcp="${HOME}/Library/Application Support/Code/User/mcp.json"

  reset_mcp_file "$cursor_mcp" '{
  "mcpServers": {}
}'
  reset_mcp_file "$cursor_user_mcp" '{
  "mcpServers": {}
}'
  reset_mcp_file "$vscode_user_mcp" '{
  "servers": {},
  "inputs": []
}'

  echo -e "${GREEN}MCP configuration cleared in Cursor and Visual Studio Code.${NC}"
}

configure_ide_settings() {
  local ide="$1"
  local settings_file

  case "$ide" in
    cursor)
      settings_file="${HOME}/Library/Application Support/Cursor/User/settings.json"
      ;;
    vscode)
      settings_file="${HOME}/Library/Application Support/Code/User/settings.json"
      ;;
    *)
      return 0
      ;;
  esac

  echo
  echo -e "${BOLD}Configuring ${ide} window settings...${NC}"

  mkdir -p "$(dirname "$settings_file")"

  SETTINGS_FILE="$settings_file" IDE="$ide" python3 <<'PY'
import json
import os
import re

path = os.environ["SETTINGS_FILE"]
ide = os.environ["IDE"]


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

data["window.newWindowDimensions"] = "fullscreen"
if ide == "cursor":
    data.pop("cursor.chatMaxWidth", None)

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
PY

  echo -e "${GREEN}Set window.newWindowDimensions to fullscreen in ${ide} settings.${NC}"
}

configure_cursor_chat_panel_width() {
  local state_db="${HOME}/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

  if [[ ! -f "$state_db" ]]; then
    echo -e "${YELLOW}Cursor state database not found — skipping chat panel width.${NC}"
    return 0
  fi

  echo
  echo -e "${BOLD}Configuring Cursor chat panel width...${NC}"

  STATE_DB="$state_db" PANEL_WIDTH="$CURSOR_CHAT_PANEL_WIDTH" python3 <<'PY'
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
PY

  echo -e "${GREEN}Set Cursor chat panel width to ${CURSOR_CHAT_PANEL_WIDTH}px.${NC}"
}

fullscreen_ide_window() {
  local ide="$1"
  local app_name process_name

  case "$ide" in
    cursor)
      app_name="Cursor"
      process_name="Cursor"
      ;;
    vscode)
      app_name="Visual Studio Code"
      process_name="Code"
      ;;
    *)
      return 0
      ;;
  esac

  (
    sleep 2
    osascript - "$app_name" "$process_name" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set processName to item 2 of argv

  tell application appName to activate

  set ready to false
  repeat with i from 1 to 60
    tell application "System Events"
      if exists process processName then
        repeat with w in windows of process processName
          set {_, wH} to size of w
          if wH > 200 then
            set ready to true
            exit repeat
          end if
        end repeat
      end if
    end tell
    if ready then exit repeat
    delay 0.25
  end repeat

  tell application "Finder"
    set {x1, y1, x2, y2} to bounds of window of desktop
  end tell
  set screenH to y2 - y1

  tell application "System Events"
    tell process processName
      if (count of windows) is 0 then return
      set frontmost to true

      set mainWindow to missing value
      set maxArea to 0
      repeat with w in windows
        set {wW, wH} to size of w
        set area to wW * wH
        if area > maxArea then
          set maxArea to area
          set mainWindow to w
        end if
      end repeat

      if mainWindow is missing value then return

      set {_, windowH} to size of mainWindow
      if windowH < screenH - 80 then
        set value of attribute "AXMain" of mainWindow to true
        delay 0.2
        keystroke "f" using {control down, command down}
      end if
    end tell
  end tell
end run
APPLESCRIPT
  ) &
}

quit_ide_if_running() {
  local app_name="$1"

  if ! pgrep -if "${app_name}\\.app" >/dev/null 2>&1; then
    return 0
  fi

  echo -e "${YELLOW}Closing ${app_name} to clear browser session...${NC}"
  osascript -e "tell application \"${app_name}\" to quit" 2>/dev/null || true

  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -if "${app_name}\\.app" >/dev/null 2>&1 || return 0
    sleep 1
  done

  killall "$app_name" 2>/dev/null || true
  sleep 1
}

cleanup_cursor_workspace_session() {
  local work_dir="${HOME}/dev/graftcode_challenge"
  local workspace_file="${work_dir}/graftcode.code-workspace"
  local storage_root="${HOME}/Library/Application Support/Cursor/User/workspaceStorage"
  local projects_root="${HOME}/.cursor/projects"
  local cleared=false

  echo
  echo -e "${BOLD}Clearing Cursor workspace session (tabs, editors)...${NC}"

  if [[ -d "$storage_root" ]]; then
    local entry workspace_json text
    for entry in "$storage_root"/*; do
      [[ -d "$entry" ]] || continue
      workspace_json="${entry}/workspace.json"
      [[ -f "$workspace_json" ]] || continue

      text="$(cat "$workspace_json")"
      if [[ "$text" != *"graftcode_challenge"* && "$text" != *"$work_dir"* && "$text" != *"$workspace_file"* ]]; then
        continue
      fi

      rm -rf "$entry"
      cleared=true
      echo -e "${GREEN}Removed Cursor workspace storage:${NC} $(basename "$entry")"
    done
  fi

  if [[ -d "$projects_root" ]]; then
    local project_dir
    for project_dir in "$projects_root"/*; do
      [[ -d "$project_dir" ]] || continue
      [[ "$(basename "$project_dir")" == *graftcode-challenge* || "$(basename "$project_dir")" == *graftcode_challenge* ]] || continue

      rm -rf "$project_dir"
      cleared=true
      echo -e "${GREEN}Removed Cursor project data:${NC} $(basename "$project_dir")"
    done
  fi

  if [[ "$cleared" == false ]]; then
    echo -e "${YELLOW}No Cursor session data found for graftcode challenge — skipping.${NC}"
  else
    echo -e "${GREEN}Cursor session cleared.${NC}"
  fi
}

cleanup_browser_cookies() {
  echo
  echo -e "${BOLD}Cleaning up IDE browser cookies...${NC}"

  quit_ide_if_running "Cursor"
  quit_ide_if_running "Visual Studio Code"

  local cleared=false
  local base partition

  for base in \
    "${HOME}/Library/Application Support/Cursor/Partitions" \
    "${HOME}/Library/Application Support/Code/Partitions"; do
    [[ -d "$base" ]] || continue

    for partition in "$base"/*; do
      [[ -d "$partition" ]] || continue
      rm -rf "$partition"
      cleared=true
      echo -e "${GREEN}Removed browser partition:${NC} ${partition}"
    done
  done

  if [[ "$cleared" == false ]]; then
    echo -e "${YELLOW}No IDE browser data found — skipping.${NC}"
  else
    echo -e "${GREEN}IDE browser cookies cleared.${NC}"
  fi
}

schedule_workspace_metadata_cleanup() {
  local work_dir="$1"

  (
    sleep "$WORKSPACE_METADATA_CLEANUP_DELAY"
    rm -rf "${work_dir}/.vscode"
  ) &
}

launch_challenge() {
  local ide_cmd="$1"
  local workspace_file="${WORK_DIR}/graftcode.code-workspace"

  echo
  echo -e "${BOLD}Launching ${IDE}...${NC}"

  "$ide_cmd" -n "$workspace_file" &
  fullscreen_ide_window "$IDE"
  schedule_workspace_metadata_cleanup "$WORK_DIR"

  echo
  echo -e "${GREEN}Done!${NC} ${IDE} is opening ${GRAFTCODE_URL} in the internal browser."
  echo -e "Workspace: ${CYAN}${workspace_file}${NC}"
}

launch_distributed() {
  local cursor_cmd
  cursor_cmd="$(find_cursor_cmd)" || {
    echo -e "${RED}Cursor not found. Install Cursor and add it to your PATH.${NC}" >&2
    exit 1
  }

  echo
  echo -e "${BOLD}Launching Cursor...${NC}"

  "$cursor_cmd" -n "$WORK_DIR" &
  fullscreen_ide_window "cursor"
  schedule_workspace_metadata_cleanup "$WORK_DIR"

  echo
  echo -e "${GREEN}Done!${NC} Cursor opened in the distributed system folder."
  echo -e "Folder: ${CYAN}${WORK_DIR}${NC}"
}

prepare_challenge_environment() {
  local ide="${1:-cursor}"

  cleanup_docker
  cleanup_mcp
  cleanup_browser_cookies
  cleanup_cursor_workspace_session
  stop_build_processes
  reset_workspace_dir
  configure_ide_settings "$ide"
  if [[ "$ide" == "cursor" ]]; then
    configure_cursor_chat_panel_width
  fi
}

start_docker_compose_up() {
  local project_dir="$1"

  if [[ ! -d "$project_dir" ]]; then
    echo -e "${RED}Project folder not found: ${project_dir}${NC}" >&2
    exit 1
  fi

  if [[ ! -f "${project_dir}/docker-compose.yml" && ! -f "${project_dir}/docker-compose.yaml" ]]; then
    echo -e "${YELLOW}No docker-compose file in ${project_dir} — skipping.${NC}"
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}Docker is not installed — skipping compose in ${project_dir}.${NC}"
    return 0
  fi

  if ! docker info >/dev/null 2>&1; then
    echo -e "${YELLOW}Docker is not running — skipping compose in ${project_dir}.${NC}"
    return 0
  fi

  echo -e "${BOLD}Starting docker compose in ${project_dir}...${NC}"
  (
    cd "$project_dir"
    docker compose up
  ) &
  echo -e "${GREEN}Docker compose started in ${project_dir}.${NC}"
}

launch_main_stage() {
  local cursor_cmd project_dir

  cursor_cmd="$(find_cursor_cmd)" || {
    echo -e "${RED}Cursor not found. Install Cursor and add it to your PATH.${NC}" >&2
    exit 1
  }

  for project_dir in "${MAIN_STAGE_PROJECTS[@]}"; do
    if [[ ! -d "$project_dir" ]]; then
      echo -e "${RED}Project folder not found: ${project_dir}${NC}" >&2
      exit 1
    fi
  done

  echo
  echo -e "${BOLD}Launching Main Stage Session...${NC}"

  for project_dir in "${MAIN_STAGE_PROJECTS[@]}"; do
    echo -e "${BOLD}Opening Cursor in ${project_dir}${NC}"
    "$cursor_cmd" -n "$project_dir" &
    sleep 0.5
  done

  for project_dir in "${MAIN_STAGE_DOCKER_COMPOSE_PROJECTS[@]}"; do
    start_docker_compose_up "$project_dir"
  done

  fullscreen_ide_window "cursor"

  echo
  echo -e "${GREEN}Done! Main Stage Session is ready.${NC}"
  for project_dir in "${MAIN_STAGE_PROJECTS[@]}"; do
    echo -e "  ${CYAN}${project_dir}${NC}"
  done
}

run_challenge() {
  local ide_cmd

  choose_ide
  ide_cmd="$(find_ide_cmd)" || {
    echo -e "${RED}${IDE} not found. Install the IDE and add it to your PATH.${NC}" >&2
    exit 1
  }
  prepare_challenge_environment "$IDE"
  copy_challenge_template
  launch_challenge "$ide_cmd"
}

run_distributed() {
  prepare_challenge_environment "cursor"
  setup_distributed_workspace
  launch_distributed
}

run_main_stage() {
  prepare_challenge_environment "cursor"
  launch_main_stage
}

main() {
  show_banner
  choose_mode

  case "$MODE" in
    challenge) run_challenge ;;
    distributed) run_distributed ;;
    mainstage) run_main_stage ;;
  esac
}

main "$@"
