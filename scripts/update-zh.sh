#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PO_FILE="${ROOT_DIR}/po/zh-CN.po"
POT_FILE="${ROOT_DIR}/book/xgettext/messages.pot"

run_format=true
show_stats=false
drop_obsolete=true

usage() {
  cat <<'EOF'
Usage: scripts/update-zh.sh [--stats] [--no-format] [--help]

Updates po/zh-CN.po from the latest English sources by running:
1. mdbook build
2. msgmerge --update
3. optionally remove obsolete entries while preserving template order
4. msgfmt --check

Options:
  --stats      Print untranslated and fuzzy entry counts after updating.
  --no-format  Skip the msgcat normalization step.
  --keep-obsolete
               Keep '#~' obsolete entries. Disabled by default.
  --help       Show this help text.
EOF
}

count_msgids() {
  awk '/^msgid /{count++} END{print count+0}'
}

while (($# > 0)); do
  case "$1" in
    --stats)
      show_stats=true
      ;;
    --no-format)
      run_format=false
      ;;
    --keep-obsolete)
      drop_obsolete=false
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

cd "${ROOT_DIR}"

printf '==> Building mdBook and refreshing %s\n' "${POT_FILE}"
mdbook build

printf '==> Merging updates into %s\n' "${PO_FILE}"
msgmerge --update "${PO_FILE}" "${POT_FILE}"

if [[ "${run_format}" == true ]]; then
  printf '==> Normalizing %s while preserving template order\n' "${PO_FILE}"
  tmp_po="$(mktemp --suffix=.po)"
  if [[ "${drop_obsolete}" == true ]]; then
    msgattrib --no-obsolete -o "${tmp_po}" "${PO_FILE}"
  else
    cp "${PO_FILE}" "${tmp_po}"
  fi
  msgmerge "${tmp_po}" "${POT_FILE}" -o "${PO_FILE}" >/dev/null
  rm -f "${tmp_po}"
fi

printf '==> Validating %s with msgfmt\n' "${PO_FILE}"
msgfmt --check -o /tmp/zh-CN.mo "${PO_FILE}"

if [[ "${show_stats}" == true ]]; then
  untranslated_count="$(
    msgattrib --no-obsolete --untranslated "${PO_FILE}" | count_msgids
  )"
  fuzzy_count="$(
    msgattrib --only-fuzzy "${PO_FILE}" | count_msgids
  )"

  printf '==> Stats\n'
  printf 'Untranslated: %s\n' "${untranslated_count}"
  printf 'Fuzzy: %s\n' "${fuzzy_count}"
fi

printf '==> Done\n'
