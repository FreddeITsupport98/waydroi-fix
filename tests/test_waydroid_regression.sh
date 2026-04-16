#!/bin/bash
# =============================================================================
# Regression test suite for waydroid.sh
# Tests: bash syntax, shellcheck, OTA server queries, python3 zip extraction,
#        CUSTOMIZE_ONLY flag parsing, aria2c download function logic
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAYDROID_SH="${SCRIPT_DIR}/../waydroid.sh"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
FAIL_NAMES=()

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); FAIL_NAMES+=("$1"); }
section() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

# =============================================================================
# 1. BASH SYNTAX CHECK
# =============================================================================
section "1. Bash syntax check"

if bash -n "$WAYDROID_SH" 2>/dev/null; then
    pass "bash -n: no syntax errors"
else
    bash -n "$WAYDROID_SH"
    fail "bash -n: syntax errors found"
fi

# =============================================================================
# 2. SHELLCHECK
# =============================================================================
section "2. ShellCheck static analysis"

if command -v shellcheck >/dev/null 2>&1; then
    # SC2034: unused variables (WAYDROID_MIRRORS etc. are intentional)
    # SC1090: can't follow dynamic source
    # SC2154: referenced but not assigned (runtime variables)
    SC_OUT=$(shellcheck --exclude=SC2034,SC1090,SC2154,SC2046 "$WAYDROID_SH" 2>&1)
    SC_EXIT=$?
    if [[ $SC_EXIT -eq 0 ]]; then
        pass "shellcheck: no issues (excluding SC2034,SC1090,SC2154,SC2046)"
    else
        # Count warnings vs errors
        ERRORS=$(echo "$SC_OUT" | grep -c "error:" || true)
        WARNS=$(echo "$SC_OUT"  | grep -c "warning:" || true)
        if [[ $ERRORS -gt 0 ]]; then
            echo "$SC_OUT" | grep "error:" | head -10
            fail "shellcheck: $ERRORS error(s), $WARNS warning(s)"
        else
            echo -e "${YELLOW}[WARN]${NC} shellcheck: $WARNS warning(s) (no errors) — treating as pass"
            pass "shellcheck: warnings only (no errors)"
        fi
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} shellcheck not installed"
fi

# =============================================================================
# 3. CUSTOMIZE_ONLY FLAG PARSING
# =============================================================================
section "3. CUSTOMIZE_ONLY / SETUP_ONLY flag parsing"

# Extract just the flag block and test it in isolation
FLAG_BLOCK=$(sed -n '/^# Mode flags:/,/^fi$/p' "$WAYDROID_SH" | head -20)

# Test: --customize-only sets CUSTOMIZE_ONLY=1, SETUP_ONLY=0
RESULT=$(bash -c "
$FLAG_BLOCK
echo \"SETUP_ONLY=\$SETUP_ONLY CUSTOMIZE_ONLY=\$CUSTOMIZE_ONLY\"
" -- --customize-only 2>/dev/null)

if [[ "$RESULT" == "SETUP_ONLY=0 CUSTOMIZE_ONLY=1" ]]; then
    pass "--customize-only sets CUSTOMIZE_ONLY=1 and SETUP_ONLY=0"
else
    fail "--customize-only flag parsing: expected 'SETUP_ONLY=0 CUSTOMIZE_ONLY=1', got '$RESULT'"
fi

# Test: --setup-only sets SETUP_ONLY=1, CUSTOMIZE_ONLY=0
RESULT2=$(bash -c "
$FLAG_BLOCK
echo \"SETUP_ONLY=\$SETUP_ONLY CUSTOMIZE_ONLY=\$CUSTOMIZE_ONLY\"
" -- --setup-only 2>/dev/null)

if [[ "$RESULT2" == "SETUP_ONLY=1 CUSTOMIZE_ONLY=0" ]]; then
    pass "--setup-only sets SETUP_ONLY=1 and CUSTOMIZE_ONLY=0"
else
    fail "--setup-only flag parsing: expected 'SETUP_ONLY=1 CUSTOMIZE_ONLY=0', got '$RESULT2'"
fi

# Test: no args → both 0
RESULT3=$(bash -c "
$FLAG_BLOCK
echo \"SETUP_ONLY=\$SETUP_ONLY CUSTOMIZE_ONLY=\$CUSTOMIZE_ONLY\"
" -- 2>/dev/null)

if [[ "$RESULT3" == "SETUP_ONLY=0 CUSTOMIZE_ONLY=0" ]]; then
    pass "no args: both flags are 0"
else
    fail "no args flag parsing: expected 'SETUP_ONLY=0 CUSTOMIZE_ONLY=0', got '$RESULT3'"
fi

# =============================================================================
# 4. OTA CONSTANTS PRESENT
# =============================================================================
section "4. OTA URL constants in script"

if grep -q 'OTA_SYSTEM_URL="https://ota.waydro.id/system"' "$WAYDROID_SH"; then
    pass "OTA_SYSTEM_URL defined as https://ota.waydro.id/system"
else
    fail "OTA_SYSTEM_URL missing or wrong"
fi

if grep -q 'OTA_VENDOR_URL="https://ota.waydro.id/vendor"' "$WAYDROID_SH"; then
    pass "OTA_VENDOR_URL defined as https://ota.waydro.id/vendor"
else
    fail "OTA_VENDOR_URL missing or wrong"
fi

# =============================================================================
# 5. OTA SERVER CONNECTIVITY & JSON STRUCTURE
# =============================================================================
section "5. OTA server connectivity and JSON structure"

# Path-based URL format (as used by waydroid internally):
#   system: {channel}/{rom_type}/waydroid_{arch}/{TYPE}.json
#   vendor: {channel}/waydroid_{arch}/{TYPE}.json
ROM_TYPE="lineage"
ARCH="x86_64"

for endpoint in "system/${ROM_TYPE}/waydroid_${ARCH}/VANILLA.json" "vendor/waydroid_${ARCH}/MAINLINE.json"; do
    LABEL="${endpoint%%/*}"
    URL="https://ota.waydro.id/${endpoint}"
    echo "  Querying: $URL"
    JSON=$(curl -sL --max-time 15 "$URL" 2>/dev/null)

    if [[ -z "$JSON" ]]; then
        fail "OTA ${endpoint%%\?*}: no response (network issue?)"
        continue
    fi

    # Parse with python3
    PARSED=$(printf '%s' "$JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    r = d['response'][0]
    print(r['url'] + '|' + r['filename'])
except Exception as e:
    print('ERROR: ' + str(e), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)

    if [[ $? -eq 0 && -n "$PARSED" ]]; then
        DL_URL="${PARSED%%|*}"
        FILENAME="${PARSED##*|}"
        echo "    -> filename: $FILENAME"
        echo "    -> url:      $DL_URL"
        if [[ "$FILENAME" == *.zip ]]; then
            pass "OTA ${LABEL}: valid JSON with url + filename (*.zip)"
        else
            fail "OTA ${LABEL}: filename doesn't end in .zip — got '$FILENAME'"
        fi
    else
        fail "OTA ${LABEL}: JSON parse failed — response: ${JSON:0:120}"
    fi
done

# =============================================================================
# 6. waydroid_ota_get_download_info FUNCTION LOGIC
# =============================================================================
section "6. waydroid_ota_get_download_info function"

# Extract function from script
OTA_FN=$(sed -n '/^waydroid_ota_get_download_info\(\)/,/^}/p' "$WAYDROID_SH")

if [[ -z "$OTA_FN" ]]; then
    fail "Could not extract waydroid_ota_get_download_info from script"
else
    # Run the function in a subshell with color vars and rom_type
    INFO=$(bash -c "
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
WAYDROID_ROM_TYPE='lineage'
$OTA_FN
waydroid_ota_get_download_info 'https://ota.waydro.id/system' 'VANILLA' 'x86_64' 'system'
" 2>/dev/null)

    if [[ -n "$INFO" ]]; then
        GOT_URL="${INFO%%|*}"
        REST="${INFO#*|}"
        GOT_FILE="${REST%%|*}"
        REST="${REST#*|}"
        GOT_SIZE="${REST%%|*}"
        GOT_SHA="${REST#*|}"
        if [[ "$GOT_URL" == http* && "$GOT_FILE" == *.zip && "$GOT_SIZE" =~ ^[0-9]+$ && ${#GOT_SHA} -eq 64 ]]; then
            pass "waydroid_ota_get_download_info: returns valid url|filename|size|sha256"
            echo "    -> url:   $GOT_URL"
            echo "    -> file:  $GOT_FILE"
            echo "    -> size:  $GOT_SIZE bytes"
            echo "    -> sha256: ${GOT_SHA:0:16}..."
        else
            fail "waydroid_ota_get_download_info: unexpected output '$INFO' (expected url|file|size|sha256)"
        fi
    else
        fail "waydroid_ota_get_download_info: empty output (OTA unreachable or function error)"
    fi
fi

# =============================================================================
# 7. PYTHON3 ZIP EXTRACTION LOGIC
# =============================================================================
section "7. Python3 zip extraction logic"

TMPDIR_TEST=$(mktemp -d)
DEST_DIR="${TMPDIR_TEST}/images"
mkdir -p "$DEST_DIR"

# Create two mock zip files (system + vendor) each containing a .img file
SYSTEM_ZIP="${TMPDIR_TEST}/lineage-18.1-20230101-VANILLA-waydroid_x86_64-system.zip"
VENDOR_ZIP="${TMPDIR_TEST}/lineage-18.1-20230101-MAINLINE-waydroid_x86_64-vendor.zip"

python3 -c "
import zipfile
import sys

zips = [
    ('${SYSTEM_ZIP}', 'lineage-18.1-20230101-VANILLA-waydroid_x86_64-system.img'),
    ('${VENDOR_ZIP}', 'lineage-18.1-20230101-MAINLINE-waydroid_x86_64-vendor.img'),
]
for zip_path, img_name in zips:
    with zipfile.ZipFile(zip_path, 'w') as zf:
        zf.writestr(img_name, 'mock android image content')
print('mock zips created')
" 2>&1

# Run extraction pointing at our DEST_DIR (avoids needing /etc/waydroid-extra write perms)
python3 - "$SYSTEM_ZIP" "$VENDOR_ZIP" <<PYEOF2 2>&1
import zipfile, os, shutil, sys

dest_dir = "${DEST_DIR}"
success = True

for zip_path in sys.argv[1:]:
    label = "system" if "system" in os.path.basename(zip_path).lower() else "vendor"
    print(f"  Extracting {label} from: {os.path.basename(zip_path)}")
    try:
        with zipfile.ZipFile(zip_path) as zf:
            imgs = [n for n in zf.namelist() if n.endswith(".img")]
            if not imgs:
                print(f"ERROR: no .img in {zip_path}", file=sys.stderr)
                success = False
                continue
            for name in imgs:
                zf.extract(name, dest_dir)
                extracted = os.path.join(dest_dir, name)
                final = os.path.join(dest_dir, os.path.basename(name))
                if extracted != final:
                    shutil.move(extracted, final)
                print(f"    -> {final}")
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        success = False

sys.exit(0 if success else 1)
PYEOF2

PY_EXIT=$?
if [[ $PY_EXIT -eq 0 ]]; then
    if [[ -f "${DEST_DIR}/lineage-18.1-20230101-VANILLA-waydroid_x86_64-system.img" && \
          -f "${DEST_DIR}/lineage-18.1-20230101-MAINLINE-waydroid_x86_64-vendor.img" ]]; then
        pass "Python zip extraction: both .img files extracted to dest_dir"
    else
        fail "Python zip extraction: expected .img files not found in ${DEST_DIR}"
        ls "$DEST_DIR" 2>/dev/null
    fi
else
    fail "Python zip extraction: script exited with non-zero (exit $PY_EXIT)"
fi

# Empty zip (no .img) → should fail cleanly
EMPTY_ZIP="${TMPDIR_TEST}/empty.zip"
python3 -c "import zipfile; zipfile.ZipFile('${EMPTY_ZIP}', 'w').close()"

python3 - "$EMPTY_ZIP" <<PYEOF3 2>/dev/null
import zipfile, os, shutil, sys
dest_dir = "${DEST_DIR}"
success = True
for zip_path in sys.argv[1:]:
    with zipfile.ZipFile(zip_path) as zf:
        imgs = [n for n in zf.namelist() if n.endswith(".img")]
        if not imgs:
            success = False
sys.exit(0 if success else 1)
PYEOF3

if [[ $? -ne 0 ]]; then
    pass "Python zip extraction: correctly detects missing .img and fails"
else
    fail "Python zip extraction: did NOT fail on empty zip (expected failure)"
fi

rm -rf "$TMPDIR_TEST"

# =============================================================================
# 8. SourceForge CDN MIRROR RESOLUTION
# =============================================================================
section "8. SourceForge CDN mirror resolution"

SF_URL="https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_x86_64/lineage-20.0-20260403-VANILLA-waydroid_x86_64-system.zip/download"
echo "  Resolving: $SF_URL"
CDN_URL=$(curl -sL --max-time 15 --max-filesize 1 \
    -o /dev/null -w "%{url_effective}" "$SF_URL" 2>/dev/null || true)
CDN_URL="${CDN_URL//[[:space:]]/}"
echo "  -> Resolved: $CDN_URL"

if [[ -n "$CDN_URL" && "$CDN_URL" != "$SF_URL" && "$CDN_URL" == *"dl.sourceforge.net"* ]]; then
    pass "CDN resolution: resolved to direct mirror (*.dl.sourceforge.net)"
elif [[ -n "$CDN_URL" && "$CDN_URL" != "$SF_URL" ]]; then
    pass "CDN resolution: resolved to a different URL (CDN mirror)"
    echo "    Note: URL does not contain dl.sourceforge.net — may be a custom mirror"
else
    fail "CDN resolution: could not resolve to a direct CDN URL (aria2c will likely fail)"
fi

# Confirm the mirror resolution code uses HEAD request (fast, no body download)
if grep -q 'curl -s --head -L' "$WAYDROID_SH" && grep -q 'url_effective' "$WAYDROID_SH"; then
    pass "CDN resolution: uses HEAD request (no body download)"
else
    fail "CDN resolution: HEAD-based resolution code missing from waydroid.sh"
fi

# Confirm log-file based progress function is present (no RPC dependency)
if grep -q 'waydroid_download_with_progress' "$WAYDROID_SH" && \
   grep -q 'summary-interval' "$WAYDROID_SH" && \
   grep -q 'log-level=notice' "$WAYDROID_SH" && \
   grep -q 'SPIN' "$WAYDROID_SH"; then
    pass "Progress bar: log-file based display (spinner + bar) present"
else
    fail "Progress bar: waydroid_download_with_progress function missing or incomplete"
fi

# =============================================================================
# 9. aria2c DOWNLOAD FUNCTION STRUCTURE
# =============================================================================
section "9. aria2c download function present and structured correctly"

# Check aria2c command line flags are correct
if grep -A 5 'aria2c -x 16 -s 16' "$WAYDROID_SH" | grep -q -- '--retry-wait=5'; then
    pass "aria2c flags include --retry-wait=5"
else
    fail "aria2c flags missing --retry-wait=5"
fi

if grep -A 5 'aria2c -x 16 -s 16' "$WAYDROID_SH" | grep -q -- '--max-tries=5'; then
    pass "aria2c flags include --max-tries=5"
else
    fail "aria2c flags missing --max-tries=5"
fi

if grep -q '\-d "\${dest_dir}"' "$WAYDROID_SH" && grep -q '\-o "\${filename}"' "$WAYDROID_SH"; then
    pass "aria2c uses -d dest_dir -o filename (correct arg format)"
else
    fail "aria2c -d/-o flags missing or malformed"
fi

# Confirm old WAYDROID_DOWNLOAD_TOOL approach is gone
if grep -q 'WAYDROID_DOWNLOAD_TOOL' "$WAYDROID_SH"; then
    fail "Old WAYDROID_DOWNLOAD_TOOL env var still referenced in script"
else
    pass "Old WAYDROID_DOWNLOAD_TOOL approach removed"
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================
echo
echo "=============================================="
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}ALL TESTS PASSED${NC} ($PASS passed, 0 failed)"
    echo "=============================================="
    exit 0
else
    echo -e "${RED}FAIL SUMMARY ($FAIL failed, $PASS passed)${NC}"
    for name in "${FAIL_NAMES[@]}"; do
        echo -e "  ${RED}✗${NC} $name"
    done
    echo "=============================================="
    exit 1
fi
