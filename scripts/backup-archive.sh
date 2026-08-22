#!/usr/bin/env bash

# This file is sourced by verify-backup.sh and restore-backup.sh.
# Backups contain credentials, so extract only the three regular files that
# Inst DM itself creates. Never unpack an arbitrary archive path tree.

extract_instdm_backup() {
  local archive_path="$1"
  local destination="$2"
  local member line
  local -a members
  local -a required=(database.dump production.env manifest.txt)
  local seen_database=0
  local seen_environment=0
  local seen_manifest=0

  mkdir -p "$destination"
  chmod 700 "$destination"

  while IFS= read -r member; do
    members+=("$member")
  done < <(tar -tzf "$archive_path")
  if (( ${#members[@]} == 0 )); then
    echo "Backup archive could not be read." >&2
    return 1
  fi
  if (( ${#members[@]} != ${#required[@]} )); then
    echo "Backup archive must contain exactly database.dump, production.env and manifest.txt." >&2
    return 1
  fi

  for member in "${members[@]}"; do
    case "$member" in
      database.dump) (( seen_database += 1 )) ;;
      production.env) (( seen_environment += 1 )) ;;
      manifest.txt) (( seen_manifest += 1 )) ;;
      *)
        echo "Backup archive contains an unexpected member: $member" >&2
        return 1
        ;;
    esac
    if (( seen_database > 1 || seen_environment > 1 || seen_manifest > 1 )); then
      echo "Backup archive contains a duplicate member: $member" >&2
      return 1
    fi
  done

  (( seen_database == 1 )) || { echo "Backup archive is missing database.dump." >&2; return 1; }
  (( seen_environment == 1 )) || { echo "Backup archive is missing production.env." >&2; return 1; }
  (( seen_manifest == 1 )) || { echo "Backup archive is missing manifest.txt." >&2; return 1; }

  # GNU tar starts each verbose record with the entry type. Backups created by
  # this project contain regular files only; reject links and device entries.
  while IFS= read -r line; do
    if [[ "${line:0:1}" != "-" ]]; then
      echo "Backup archive contains a non-regular member." >&2
      return 1
    fi
  done < <(tar -tvzf "$archive_path")

  for member in "${required[@]}"; do
    tar -xOzf "$archive_path" -- "$member" > "$destination/$member"
    chmod 600 "$destination/$member"
  done
}
