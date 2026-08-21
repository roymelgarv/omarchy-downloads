# shellcheck shell=bash
# Shared shell helpers, sourced (not executed) by the other bin/ scripts.

# Percent-encode a local filesystem path into the path portion of a file://
# URI: unreserved ASCII passes through, everything else — including each byte
# of a multi-byte UTF-8 character — becomes %XX. `LC_ALL=C` makes bash index
# the string byte-by-byte instead of character-by-character; without it this
# would encode one %XX per Unicode code point instead of per UTF-8 byte,
# which is wrong for anything outside Latin-1.
uri_encode_path() {
  local LC_ALL=C
  local s="$1" out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [A-Za-z0-9._~/-]) out+="$c" ;;
      *) out+="$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '%s' "$out"
}

# Absolute path for a file/dir that may not exist yet at the leaf, without
# requiring realpath's target to be readable.
abs_path() {
  printf '%s/%s' "$(cd "$(dirname -- "$1")" && pwd)" "$(basename -- "$1")"
}
