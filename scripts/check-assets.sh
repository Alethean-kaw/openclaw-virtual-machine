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

asset_root_has_materials() {
  local root="$1"
  local name
  for name in \
    ubuntu-24.04-server-cloudimg-amd64.img \
    ubuntu-24.04.4-live-server-amd64.iso \
    SHA256SUMS \
    ubuntu-release-SHA256SUMS
  do
    if [[ -f "$root/$name" ]]; then
      return 0
    fi
  done
  return 1
}

resolve_asset_root() {
  local skill_root="$1"
  local parent_root
  local local_root
  local fallback_root

  parent_root="$(cd "$skill_root/.." && pwd)"
  local_root="$skill_root/ubuntu"
  fallback_root="$parent_root/ubuntu"

  if asset_root_has_materials "$local_root"; then
    printf '%s' "$local_root"
    return 0
  fi

  if asset_root_has_materials "$fallback_root"; then
    printf '%s' "$fallback_root"
    return 0
  fi

  printf '%s' "$local_root"
}

get_expected_sha256() {
  local checksum_path="$1"
  local file_name="$2"

  [[ -f "$checksum_path" ]] || return 0
  grep " $file_name\$" "$checksum_path" | head -n 1 | awk '{print tolower($1)}'
}

audit_file() {
  local file_path="$1"
  local checksum_path="${2-}"
  local present=false
  local checksum_present=false
  local expected=""
  local actual=""
  local verified=false
  local mismatch=false
  local file_name

  file_name="$(basename "$file_path")"
  [[ -f "$file_path" ]] && present=true
  [[ -n "$checksum_path" && -f "$checksum_path" ]] && checksum_present=true

  if [[ "$present" == "true" ]]; then
    actual="$(sha256sum "$file_path" | awk '{print tolower($1)}')"
  fi

  if [[ "$checksum_present" == "true" ]]; then
    expected="$(get_expected_sha256 "$checksum_path" "$file_name")"
  fi

  if [[ "$present" == "true" && -n "$expected" ]]; then
    if [[ "$actual" == "$expected" ]]; then
      verified=true
    else
      mismatch=true
    fi
  fi

  printf '{'
  printf '"present":'
  json_bool "$present"
  printf ','
  printf '"checksum_present":'
  json_bool "$checksum_present"
  printf ','
  printf '"verified":'
  json_bool "$verified"
  printf ','
  printf '"mismatch":'
  json_bool "$mismatch"
  printf ','
  printf '"sha256":'
  json_nullable_string "$actual"
  printf ','
  printf '"expected_sha256":'
  json_nullable_string "$expected"
  printf ','
  printf '"path":'
  json_string "$file_path"
  printf ','
  printf '"checksum_path":'
  json_nullable_string "$checksum_path"
  printf '}'
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$script_dir/.." && pwd)"
asset_root="$(resolve_asset_root "$skill_root")"

cloud_image_path="$asset_root/ubuntu-24.04-server-cloudimg-amd64.img"
cloud_checksums_path="$asset_root/SHA256SUMS"
cloud_checksums_gpg_path="$asset_root/SHA256SUMS.gpg"
iso_path="$asset_root/ubuntu-24.04.4-live-server-amd64.iso"
release_checksums_path="$asset_root/ubuntu-release-SHA256SUMS"
release_checksums_gpg_path="$asset_root/ubuntu-release-SHA256SUMS.gpg"

cloud_image_json="$(audit_file "$cloud_image_path" "$cloud_checksums_path")"
server_iso_json="$(audit_file "$iso_path" "$release_checksums_path")"

missing_required=()
recommended_missing=()
damaged=()
guidance=()
warnings=()

[[ -f "$cloud_image_path" ]] || missing_required+=("cloud_image")
[[ -f "$cloud_checksums_path" ]] || missing_required+=("cloud_checksums")
[[ -f "$iso_path" ]] || recommended_missing+=("server_iso")
[[ -f "$release_checksums_path" ]] || recommended_missing+=("release_checksums")

cloud_expected="$(get_expected_sha256 "$cloud_checksums_path" "$(basename "$cloud_image_path")")"
iso_expected="$(get_expected_sha256 "$release_checksums_path" "$(basename "$iso_path")")"
cloud_actual=""
iso_actual=""
[[ -f "$cloud_image_path" ]] && cloud_actual="$(sha256sum "$cloud_image_path" | awk '{print tolower($1)}')"
[[ -f "$iso_path" ]] && iso_actual="$(sha256sum "$iso_path" | awk '{print tolower($1)}')"

if [[ -f "$cloud_image_path" && -f "$cloud_checksums_path" && -z "$cloud_expected" ]]; then
  damaged+=("cloud_checksums_entry_missing")
fi
if [[ -n "$cloud_expected" && -n "$cloud_actual" && "$cloud_expected" != "$cloud_actual" ]]; then
  damaged+=("cloud_image")
fi
if [[ -f "$iso_path" && -f "$release_checksums_path" && -z "$iso_expected" ]]; then
  damaged+=("release_checksums_entry_missing")
fi
if [[ -n "$iso_expected" && -n "$iso_actual" && "$iso_expected" != "$iso_actual" ]]; then
  damaged+=("server_iso")
fi

[[ -f "$cloud_image_path" ]] || guidance+=("Download ubuntu-24.04-server-cloudimg-amd64.img into ubuntu/ at the repository root.")
[[ -f "$cloud_checksums_path" ]] || guidance+=("Download the cloud-image SHA256SUMS file into ubuntu/SHA256SUMS.")
if [[ -n "$cloud_expected" && -n "$cloud_actual" && "$cloud_expected" != "$cloud_actual" ]]; then
  guidance+=("The cloud image hash does not match SHA256SUMS. Redownload ubuntu-24.04-server-cloudimg-amd64.img.")
fi
[[ -f "$iso_path" ]] || guidance+=("Download ubuntu-24.04.4-live-server-amd64.iso into ubuntu/ if you want the ISO fallback path available locally.")
[[ -f "$release_checksums_path" ]] || guidance+=("Download the Ubuntu release SHA256SUMS file into ubuntu/ubuntu-release-SHA256SUMS.")
if [[ -n "$iso_expected" && -n "$iso_actual" && "$iso_expected" != "$iso_actual" ]]; then
  guidance+=("The server ISO hash does not match ubuntu-release-SHA256SUMS. Redownload ubuntu-24.04.4-live-server-amd64.iso.")
fi

[[ -f "$cloud_checksums_gpg_path" ]] || warnings+=("The cloud-image SHA256SUMS.gpg file is missing. Integrity can still be checked locally, but detached signature verification is unavailable.")
[[ -f "$release_checksums_gpg_path" ]] || warnings+=("The Ubuntu release SHA256SUMS.gpg file is missing. Integrity can still be checked locally, but detached signature verification is unavailable.")

status="needs_attention"
if [[ ! " ${missing_required[*]} " =~ "cloud_image" && ! " ${missing_required[*]} " =~ "cloud_checksums" && ${#damaged[@]} -eq 0 ]]; then
  if [[ -f "$iso_path" && -f "$release_checksums_path" && -n "$iso_expected" && "$iso_expected" == "$iso_actual" ]]; then
    status="complete"
  else
    status="usable"
  fi
fi

printf '{'
printf '"status":'
json_string "$status"
printf ','
printf '"asset_root":'
json_string "$asset_root"
printf ','
printf '"files":{'
printf '"cloud_image":%s,' "$cloud_image_json"
printf '"cloud_checksums":{"present":%s,"path":%s},' "$(json_bool "$([[ -f "$cloud_checksums_path" ]] && printf true || printf false)")" "$(json_string "$cloud_checksums_path")"
printf '"cloud_checksums_gpg":{"present":%s,"path":%s},' "$(json_bool "$([[ -f "$cloud_checksums_gpg_path" ]] && printf true || printf false)")" "$(json_string "$cloud_checksums_gpg_path")"
printf '"server_iso":%s,' "$server_iso_json"
printf '"release_checksums":{"present":%s,"path":%s},' "$(json_bool "$([[ -f "$release_checksums_path" ]] && printf true || printf false)")" "$(json_string "$release_checksums_path")"
printf '"release_checksums_gpg":{"present":%s,"path":%s}' "$(json_bool "$([[ -f "$release_checksums_gpg_path" ]] && printf true || printf false)")" "$(json_string "$release_checksums_gpg_path")"
printf '},'
json_array "missing_required" "${missing_required[@]}"
printf ','
json_array "recommended_missing" "${recommended_missing[@]}"
printf ','
json_array "damaged" "${damaged[@]}"
printf ','
json_array "guidance" "${guidance[@]}"
printf ','
json_array "warnings" "${warnings[@]}"
printf '}\n'

exit 0
