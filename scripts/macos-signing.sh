#!/bin/bash
# Resolve only a valid Developer ID Application identity from the local Keychain.
# A name or SHA-1 identity hash is accepted; development and ad-hoc identities are not.
ddl_developer_id_hash() {
  if [ -z "${1:-}" ] || [ "$1" = "-" ]; then
    echo "A Developer ID Application certificate is required. Set DDL_SIGNING_IDENTITY to its name or identity hash." >&2
    return 1
  fi
  local task_identity_hash
  task_identity_hash="$(security find-identity -v -p codesigning | awk -v requested="$1" '
    /"Developer ID Application: / {
      hash = $2
      name = $0
      sub(/^[^"]*"/, "", name)
      sub(/".*$/, "", name)
      if (requested == hash || requested == name) print hash
    }')"
  if [ -z "$task_identity_hash" ]; then
    echo "No matching valid Developer ID Application certificate and private key were found in Keychain." >&2
    echo "Create/install the certificate using your paid Apple Developer Program account first." >&2
    return 1
  fi
  printf '%s\n' "$task_identity_hash"
}
