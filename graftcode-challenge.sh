#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHALLENGE_TEMPLATE="${SCRIPT_DIR}/templates/graftcode-challenge"

GRAFTCODE_URL="https://wad.graftcode.com"
WAD_KNOWLEDGE_REPO="https://github.com/pladynski/wad-knowledge"
WORKSPACE_METADATA_CLEANUP_DELAY=10
CURSOR_CHAT_MAX_WIDTH=400

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
  / ___|  _ \    / \  |_   _| ____/ ___|  _ \|  _ \| ____|
 | |  _| |_) |  / _ \   | | |  _|| |   | | | | | | |  _|
 | |_| |  _ <  / ___ \  | | | |__| |___| |_| | |_| | |___
  \____|_| \_\/_/   \_\ |_| |_____\____|____/|____/|_____|

   ____ _   _    _    _       _     _____ _   _ _____ ____  _____
  / ___| | | |  / \  | |     | |   | ____| \ | |_   _|  _ \| ____|
 | |   | |_| | / _ \ | |     | |   |  _| |  \| | | | | |_) |  _|
 | |___|  _  |/ ___ \| |___  | |___| |___| |\  | | | |  _ <| |___
  \____|_| |_/_/   \_\_____| |_____|_____|_| \_| |_| |_| \_\_____|
EOF
  echo -e "${NC}"
  echo -e "${YELLOW}Welcome to the world of Graftcode!${NC}"
  echo
}

choose_mode() {
  echo -e "${BOLD}What would you like to do?${NC}"
  echo "  1) Graftcode Challenge"
  echo "  2) Build a distributed system using Graftcode"
  echo
  while true; do
    read -r -p "Your choice [1/2]: " choice
    case "$choice" in
      1) MODE="challenge"; return ;;
      2) MODE="distributed"; return ;;
      *) echo -e "${RED}Invalid choice. Enter 1 or 2.${NC}" ;;
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

create_workspace_dir() {
  local folder_name
  folder_name="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  WORK_DIR="${HOME}/dev/${folder_name}"
  mkdir -p "$WORK_DIR"
  echo -e "${GREEN}Created folder:${NC} ${WORK_DIR}"
}

copy_challenge_template() {
  if [[ ! -d "$CHALLENGE_TEMPLATE" ]]; then
    echo -e "${RED}Challenge template not found: ${CHALLENGE_TEMPLATE}${NC}" >&2
    exit 1
  fi

  cp -R "${CHALLENGE_TEMPLATE}/." "$WORK_DIR/"
  write_cursor_workspace_settings "$WORK_DIR"
  echo -e "${GREEN}Workspace template ready.${NC}"
}

write_cursor_workspace_settings() {
  local work_dir="$1"

  mkdir -p "${work_dir}/.vscode"

  WORK_DIR="$work_dir" CHAT_MAX_WIDTH="$CURSOR_CHAT_MAX_WIDTH" python3 <<'PY'
import json
import os
import re

path = os.path.join(os.environ["WORK_DIR"], ".vscode", "settings.json")


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

data["cursor.chatMaxWidth"] = int(os.environ["CHAT_MAX_WIDTH"])

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
PY
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

  cat > "${WORK_DIR}/.vscode/settings.json" <<JSON
{
  "task.allowAutomaticTasks": "on",
  "cursor.chatMaxWidth": ${CURSOR_CHAT_MAX_WIDTH}
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
  echo -e "${BOLD}Cleaning up running Docker containers...${NC}"

  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}Docker is not installed — skipping.${NC}"
    return 0
  fi

  if ! docker info >/dev/null 2>&1; then
    echo -e "${YELLOW}Docker is not running — skipping.${NC}"
    return 0
  fi

  local running
  running="$(docker ps -q 2>/dev/null || true)"

  if [[ -z "$running" ]]; then
    echo -e "${YELLOW}No running containers.${NC}"
    return 0
  fi

  docker rm -f $running
  echo -e "${GREEN}Removed running Docker containers.${NC}"
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

  SETTINGS_FILE="$settings_file" CHAT_MAX_WIDTH="$CURSOR_CHAT_MAX_WIDTH" IDE="$ide" python3 <<'PY'
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
    data["cursor.chatMaxWidth"] = int(os.environ["CHAT_MAX_WIDTH"])

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
PY

  echo -e "${GREEN}Set window.newWindowDimensions to fullscreen in ${ide} settings.${NC}"
  if [[ "$ide" == "cursor" ]]; then
    echo -e "${GREEN}Set cursor.chatMaxWidth to ${CURSOR_CHAT_MAX_WIDTH} in Cursor settings.${NC}"
  fi
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

run_challenge() {
  local ide_cmd

  choose_ide
  ide_cmd="$(find_ide_cmd)" || {
    echo -e "${RED}${IDE} not found. Install the IDE and add it to your PATH.${NC}" >&2
    exit 1
  }
  create_workspace_dir
  cleanup_docker
  cleanup_mcp
  cleanup_browser_cookies
  configure_ide_settings "$IDE"
  copy_challenge_template
  launch_challenge "$ide_cmd"
}

run_distributed() {
  create_workspace_dir
  cleanup_docker
  cleanup_mcp
  cleanup_browser_cookies
  configure_ide_settings "cursor"
  setup_distributed_workspace
  launch_distributed
}

main() {
  show_banner
  choose_mode

  case "$MODE" in
    challenge) run_challenge ;;
    distributed) run_distributed ;;
  esac
}

main "$@"
