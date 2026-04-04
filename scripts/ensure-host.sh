#!/usr/bin/env bash

set -uo pipefail

json_escape() {
  local value="${1-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

json_string() {
  printf '"%s"' "$(json_escape "${1-}")"
}

json_bool() {
  if [[ "${1-}" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

json_nullable_string() {
  if [[ -n "${1-}" ]]; then
    json_string "$1"
  else
    printf 'null'
  fi
}

json_array() {
  local name="$1"
  shift
  local items=("$@")
  printf '"%s":[' "$name"
  local first=true
  local item
  for item in "${items[@]}"; do
    [[ -z "$item" ]] && continue
    if [[ "$first" == false ]]; then
      printf ','
    fi
    json_string "$item"
    first=false
  done
  printf ']'
}

find_command_path() {
  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

get_host_os() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || printf 'unknown')"
  case "$uname_s" in
    Linux*) printf 'linux' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows' ;;
    *) printf 'linux' ;;
  esac
}

detect_running_inside_vm() {
  local host_os="$1"
  local content=""

  if [[ "$host_os" == "linux" ]]; then
    if command -v systemd-detect-virt >/dev/null 2>&1; then
      if systemd-detect-virt --quiet >/dev/null 2>&1; then
        printf 'true'
        return 0
      fi
    fi

    if [[ -r /sys/class/dmi/id/product_name ]]; then
      content+=" $(cat /sys/class/dmi/id/product_name 2>/dev/null)"
    fi
    if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
      content+=" $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)"
    fi
    content="$(printf '%s' "$content" | tr '[:upper:]' '[:lower:]')"

    case "$content" in
      *virtualbox*|*vmware*|*kvm*|*qemu*|*xen*|*hyper-v*|*parallels*|*bhyve*)
        printf 'true'
        return 0
        ;;
    esac
  fi

  printf 'false'
}

detect_package_manager() {
  local candidate
  for candidate in apt dnf yum pacman; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$script_dir/.." && pwd)"
workspace_root="$(cd "$skill_root/.." && pwd)"

host_os="$(get_host_os)"
running_inside_vm="$(detect_running_inside_vm "$host_os")"

cloud_image_path="$workspace_root/ubuntu/ubuntu-24.04-server-cloudimg-amd64.img"
iso_path="$workspace_root/ubuntu/ubuntu-24.04.4-live-server-amd64.iso"

if [[ "$host_os" == "windows" ]]; then
  qemu_system_path="$(find_command_path qemu-system-x86_64.exe qemu-system-x86_64 2>/dev/null || true)"
  qemu_img_path="$(find_command_path qemu-img.exe qemu-img 2>/dev/null || true)"
  ssh_path="$(find_command_path ssh.exe ssh 2>/dev/null || true)"
  scp_path="$(find_command_path scp.exe scp 2>/dev/null || true)"
else
  qemu_system_path="$(find_command_path qemu-system-x86_64 2>/dev/null || true)"
  qemu_img_path="$(find_command_path qemu-img 2>/dev/null || true)"
  ssh_path="$(find_command_path ssh 2>/dev/null || true)"
  scp_path="$(find_command_path scp 2>/dev/null || true)"
fi

cloud_image_found=false
iso_found=false
[[ -f "$cloud_image_path" ]] && cloud_image_found=true
[[ -f "$iso_path" ]] && iso_found=true

missing_required=()
guidance=()
warnings=()

[[ -z "$qemu_system_path" ]] && missing_required+=("qemu_system")
[[ -z "$qemu_img_path" ]] && missing_required+=("qemu_img")
[[ -z "$ssh_path" ]] && missing_required+=("ssh")
[[ -z "$scp_path" ]] && missing_required+=("scp")
if [[ "$cloud_image_found" != true && "$iso_found" != true ]]; then
  missing_required+=("ubuntu_base_asset")
fi

if [[ "$running_inside_vm" == "true" ]]; then
  warnings+=("The host is running inside a virtual machine; QEMU may not have hardware acceleration and performance may be reduced.")
fi

package_manager="$(detect_package_manager 2>/dev/null || true)"
qemu_missing=false
ssh_missing=false

if [[ -z "$qemu_system_path" || -z "$qemu_img_path" ]]; then
  qemu_missing=true
  guidance+=("QEMU was not detected. VM mode is unavailable and the skill will fall back to sandbox mode.")

  if [[ "$host_os" == "windows" ]]; then
    guidance+=("Install QEMU from the official download page and choose the Windows 64-bit binaries or installer: https://www.qemu.org/download/")
    guidance+=("After installation, confirm qemu-system-x86_64.exe and qemu-img.exe are available on PATH, then rerun host validation.")
  else
    case "$package_manager" in
      apt) guidance+=("Install QEMU with: sudo apt update && sudo apt install -y qemu-system-x86 qemu-utils") ;;
      dnf) guidance+=("Install QEMU with: sudo dnf install -y @virtualization") ;;
      yum) guidance+=("Install QEMU with: sudo yum install -y qemu-kvm") ;;
      pacman) guidance+=("Install QEMU with: sudo pacman -S qemu") ;;
      *) guidance+=("Install QEMU with your Linux package manager, then rerun host validation.") ;;
    esac
  fi
fi

if [[ -z "$ssh_path" || -z "$scp_path" ]]; then
  ssh_missing=true
  if [[ "$host_os" == "windows" ]]; then
    guidance+=("OpenSSH client support is required for VM mode. Ensure ssh.exe and scp.exe are available, then rerun host validation.")
  else
    case "$package_manager" in
      apt) guidance+=("Install the OpenSSH client with: sudo apt update && sudo apt install -y openssh-client") ;;
      dnf) guidance+=("Install the OpenSSH client with: sudo dnf install -y openssh-clients") ;;
      yum) guidance+=("Install the OpenSSH client with: sudo yum install -y openssh-clients") ;;
      pacman) guidance+=("Install the OpenSSH client with: sudo pacman -S openssh") ;;
      *) guidance+=("Install the OpenSSH client so that ssh and scp are available, then rerun host validation.") ;;
    esac
  fi
fi

if [[ "$cloud_image_found" != true && "$iso_found" != true ]]; then
  guidance+=("Ubuntu base materials were not found. Add ubuntu/ubuntu-24.04-server-cloudimg-amd64.img or ubuntu/ubuntu-24.04.4-live-server-amd64.iso relative to the repository root.")
fi

vm_available=false
status="sandbox_only"
if [[ ${#missing_required[@]} -eq 0 ]]; then
  vm_available=true
  status="vm_ready"
fi

printf '{'
printf '"host_os":'
json_string "$host_os"
printf ','
printf '"running_inside_vm":'
json_bool "$running_inside_vm"
printf ','
printf '"sandbox_available":true,'
printf '"vm_available":'
json_bool "$vm_available"
printf ','
printf '"status":'
json_string "$status"
printf ','
printf '"tools":{'
printf '"qemu_system":{"found":'
json_bool "$([[ -n "$qemu_system_path" ]] && printf true || printf false)"
printf ',"path":'
json_nullable_string "$qemu_system_path"
printf '},'
printf '"qemu_img":{"found":'
json_bool "$([[ -n "$qemu_img_path" ]] && printf true || printf false)"
printf ',"path":'
json_nullable_string "$qemu_img_path"
printf '},'
printf '"ssh":{"found":'
json_bool "$([[ -n "$ssh_path" ]] && printf true || printf false)"
printf ',"path":'
json_nullable_string "$ssh_path"
printf '},'
printf '"scp":{"found":'
json_bool "$([[ -n "$scp_path" ]] && printf true || printf false)"
printf ',"path":'
json_nullable_string "$scp_path"
printf '}'
printf '},'
printf '"assets":{'
printf '"cloud_image_found":'
json_bool "$cloud_image_found"
printf ','
printf '"iso_found":'
json_bool "$iso_found"
printf '},'
json_array "missing_required" "${missing_required[@]}"
printf ','
json_array "guidance" "${guidance[@]}"
printf ','
json_array "warnings" "${warnings[@]}"
printf '}\n'

exit 0
