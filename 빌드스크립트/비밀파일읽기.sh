#!/bin/sh
# 빌드할 때 맥의 비밀 파일을 읽어 앱 안의 스위프트 파일을 만듭니다.
# 키 값은 화면이나 로그에 찍지 않습니다.

set -eu

SECRETS="/Users/anyplan/.appstoreconnect/private_keys/비밀암호.txt"
OUT="${SRCROOT}/빌드생성/BakedSecrets.swift"

mkdir -p "${SRCROOT}/빌드생성"

value_for() {
  key="$1"
  if [ ! -f "${SECRETS}" ]; then
    return 0
  fi
  awk -v key="${key}" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      line = $0
      eq = index(line, "=")
      if (eq == 0) next
      name = substr(line, 1, eq - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (name == key) {
        val = substr(line, eq + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        found = val
      }
    }
    END {
      if (found != "") printf "%s", found
    }
  ' "${SECRETS}"
}

swift_escape() {
  awk 'BEGIN { ORS = "" }
  {
    gsub(/\\/, "\\\\")
    gsub(/"/, "\\\"")
    gsub(/\r/, "\\r")
    if (NR > 1) printf "\\n"
    printf "%s", $0
  }'
}

write_let() {
  prop="$1"
  key="$2"
  raw="$(value_for "${key}")"
  esc="$(printf '%s' "${raw}" | swift_escape)"
  printf '    static let %s = "%s"\n' "${prop}" "${esc}"
}

{
  printf '%s\n' "// 빌드 중에 비밀 파일에서 채운 파일입니다. 키 값은 저장소에 올리지 않습니다."
  printf '%s\n' "enum BakedSecrets {"
  write_let mapbox MAPBOX_ACCESS_TOKEN
  write_let gemini GEMINI_API_KEY
  write_let dataGoKr DATA_GO_KR_SERVICE_KEY
  write_let khoaHaereum KHOA_HAEREUM_KEY
  write_let youtube YOUTUBE_API_KEY
  printf '%s\n' "}"
} > "${OUT}"

if git -C "${SRCROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "${SRCROOT}" update-index --skip-worktree -- "빌드생성/BakedSecrets.swift" >/dev/null 2>&1 || true
fi
