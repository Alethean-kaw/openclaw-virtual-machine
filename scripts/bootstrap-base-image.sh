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

extract_json_string() {
  local json="$1"
  local key="$2"
  printf '%s\n' "$json" | sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p"
}

extract_preflight_qemu_img_path() {
  local json="$1"
  if [[ "$json" == *'"qemu_img":{"found":true,"path":'* ]]; then
    printf '%s\n' "$json" | sed -n 's/.*"qemu_img":{"found":true,"path":"\([^"]*\)"}.*/\1/p'
  fi
}

FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$script_dir/.." && pwd)"
workspace_root="$(cd "$skill_root/.." && pwd)"
ensure_host_path="$script_dir/ensure-host.sh"

preflight_json="$("$ensure_host_path")" || {
  printf 'Host preflight failed.\n' >&2
  exit 1
}

host_os="$(extract_json_string "$preflight_json" "host_os")"
preflight_status="$(extract_json_string "$preflight_json" "status")"
qemu_img_path="$(extract_preflight_qemu_img_path "$preflight_json")"

cloud_image_path="$workspace_root/ubuntu/ubuntu-24.04-server-cloudimg-amd64.img"
iso_path="$workspace_root/ubuntu/ubuntu-24.04.4-live-server-amd64.iso"
base_image_dir="$skill_root/runtime/cache/base-images"
base_image_path="$base_image_dir/ubuntu-24.04-base.qcow2"
metadata_path="$base_image_dir/ubuntu-24.04-base.json"

cloud_image_found=false
iso_found=false
[[ -f "$cloud_image_path" ]] && cloud_image_found=true
[[ -f "$iso_path" ]] && iso_found=true

source_type=""
source_path=""
if [[ "$cloud_image_found" == "true" ]]; then
  source_type="cloud_image"
  source_path="$cloud_image_path"
elif [[ "$iso_found" == "true" ]]; then
  source_type="iso"
  source_path="$iso_path"
fi

guidance=()
warnings=()
package_manager="$(detect_package_manager 2>/dev/null || true)"
base_image_found=false
created=false
reused_existing=false
status="blocked"

if [[ -f "$base_image_path" && "$FORCE" != "true" ]]; then
  base_image_found=true
  reused_existing=true
  status="exists"
else
  if [[ -z "$qemu_img_path" ]]; then
    guidance+=("qemu-img is required to build the base image.")
    case "$package_manager" in
      apt) guidance+=("Install QEMU with: sudo apt update && sudo apt install -y qemu-system-x86 qemu-utils") ;;
      dnf) guidance+=("Install QEMU with: sudo dnf install -y @virtualization") ;;
      yum) guidance+=("Install QEMU with: sudo yum install -y qemu-kvm") ;;
      pacman) guidance+=("Install QEMU with: sudo pacman -S qemu") ;;
      *) guidance+=("Install QEMU with your Linux package manager, then rerun base image bootstrap.") ;;
    esac
  fi

  if [[ -z "$source_type" ]]; then
    guidance+=("No Ubuntu bootstrap source was found. Add ubuntu/ubuntu-24.04-server-cloudimg-amd64.img or ubuntu/ubuntu-24.04.4-live-server-amd64.iso relative to the repository root.")
  elif [[ "$source_type" == "iso" ]]; then
    guidance+=("ISO bootstrap was detected, but unattended ISO installation is not implemented yet in this phase.")
    guidance+=("Keep the ISO as project material, but use the cloud image to create the first reusable base image.")
  fi

  if [[ -n "$qemu_img_path" && "$source_type" == "cloud_image" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      status="dry_run"
      guidance+=("Dry run complete. The cloud image is available and qemu-img can create the base image when you rerun without --dry-run.")
    else
      mkdir -p "$base_image_dir"
      temp_base_image_path="$base_image_path.tmp.$$"
      rm -f "$temp_base_image_path"
      "$qemu_img_path" convert -p -O qcow2 "$source_path" "$temp_base_image_path" || {
        rm -f "$temp_base_image_path"
        printf 'qemu-img convert failed.\n' >&2
        exit 1
      }
      mv -f "$temp_base_image_path" "$base_image_path"
      base_image_found=true
      created=true
      status="created"
    fi
  fi
fi

if [[ "$preflight_json" == *'"running_inside_vm":true'* ]]; then
  warnings+=("The host is running inside a virtual machine; QEMU may not have hardware acceleration and performance may be reduced.")
fi

if [[ ("$status" == "created" || "$status" == "exists") && "$DRY_RUN" != "true" ]]; then
  mkdir -p "$base_image_dir"
  cat > "$metadata_path" <<EOF
{
  "base_image_path": $(json_string "$base_image_path"),
  "source_type": $(json_nullable_string "$source_type"),
  "source_path": $(json_nullable_string "$source_path"),
  "created_with": $(json_string "$( [[ "$created" == "true" ]] && printf 'bootstrap-base-image.sh' || printf 'existing-base-image' )"),
  "created_at": $(json_string "$(date -Iseconds)"),
  "host_os": $(json_string "$host_os"),
  "preflight_status": $(json_string "$preflight_status"),
  "force": $(json_bool "$FORCE")
}
EOF
fi

printf '{'
printf '"status":'
json_string "$status"
printf ','
printf '"host_os":'
json_string "$host_os"
printf ','
printf '"preflight_status":'
json_string "$preflight_status"
printf ','
printf '"source_type":'
json_nullable_string "$source_type"
printf ','
printf '"source_path":'
json_nullable_string "$source_path"
printf ','
printf '"base_image_path":'
json_string "$base_image_path"
printf ','
printf '"metadata_path":'
json_string "$metadata_path"
printf ','
printf '"base_image_found":'
json_bool "$([[ -f "$base_image_path" ]] && printf true || printf false)"
printf ','
printf '"created":'
json_bool "$created"
printf ','
printf '"reused_existing":'
json_bool "$reused_existing"
printf ','
printf '"force":'
json_bool "$FORCE"
printf ','
printf '"dry_run":'
json_bool "$DRY_RUN"
printf ','
json_array "guidance" "${guidance[@]}"
printf ','
json_array "warnings" "${warnings[@]}"
printf '}\n'

exit 0
