#!/bin/bash
# Isolated pip-drop-editables tests. Never calls a real pip.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${ROOT}/src/pip-drop-editables"
BASH_BIN="/bin/bash"
FAIL=0
PASS=0

say() { printf '%s\n' "$1"; }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL: %s\n        expected: [%s]\n        actual:   [%s]\n' "$desc" "$expected" "$actual"
    fi
}

assert_ok() {
    local desc="$1" status="$2"
    assert_eq "$desc" "0" "$status"
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -F -q -- "$needle"; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL: %s\n        missing: [%s]\n' "$desc" "$needle"
    fi
}

assert_absent() {
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -F -q -- "$needle"; then
        FAIL=$((FAIL + 1))
        printf '  FAIL: %s\n        unexpected: [%s]\n' "$desc" "$needle"
    else
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$desc"
    fi
}

run_tool() {
    RUN_STATUS=0
    RUN_OUT="$("$BASH_BIN" "$SCRIPT" "$@" 2>"${ROOT}/tests/.err")" || RUN_STATUS=$?
    RUN_ERR="$(cat "${ROOT}/tests/.err" 2>/dev/null || true)"
}

test_help_version() {
    say "help and version"
    run_tool --help
    assert_ok "help exit" "$RUN_STATUS"
    assert_eq "help stderr empty" "" "$RUN_ERR"
    assert_contains "help names the command" "pip-drop-editables" "$RUN_OUT"
    assert_contains "help mentions dry-run" "--dry-run" "$RUN_OUT"
    assert_contains "help mentions check" "--check" "$RUN_OUT"
    run_tool --version
    assert_ok "version exit" "$RUN_STATUS"
    assert_eq "version stderr empty" "" "$RUN_ERR"
    printf '%s\n' "$RUN_OUT" | grep -E -q '^pip-drop-editables [0-9]+\.[0-9]+\.[0-9]+$'
    assert_ok "version shape" "$?"
}

test_usage_errors() {
    say "usage errors"
    run_tool --not-a-flag
    assert_eq "unknown flag" "2" "$RUN_STATUS"
    assert_contains "unknown flag message" "Unknown option: --not-a-flag" "$RUN_ERR"
    run_tool --index
    assert_eq "index without check" "2" "$RUN_STATUS"
    assert_contains "index without check message" "--index belongs with --check." "$RUN_ERR"
    run_tool --list --check
    assert_eq "list and check" "2" "$RUN_STATUS"
    assert_contains "list and check message" "--list, --check, and a drop do not combine." "$RUN_ERR"
    run_tool --check --list
    assert_eq "check and list" "2" "$RUN_STATUS"
    assert_contains "check and list message" "--list, --check, and a drop do not combine." "$RUN_ERR"
}

ORIGIN_PATH="$PATH"
WORK=""

new_env() {
    WORK="$(mktemp -d)"
    BIN="${WORK}/bin"
    mkdir -p "$BIN"
    cp "${ROOT}/tests/fixtures/python3" "${BIN}/python3"
    chmod +x "${BIN}/python3"
    # PATH is only this directory so discovery cannot see another interpreter.
    # The fixture, the tool, and the assertions still need the usual utilities.
    for cmd in awk basename cat chmod cp dirname grep ln mkdir mktemp realpath rm sed tr; do
        if src="$(PATH="$ORIGIN_PATH" command -v "$cmd")"; then
            ln -s "$src" "${BIN}/${cmd}"
        fi
    done
    export PATH="${BIN}"
    export PIP_DROP_LOG="${WORK}/log"
    export PIP_DROP_ACTIONS="${WORK}/actions"
    export PIP_DROP_JSON='[]'
    export PIP_DROP_VERSION="3.13.9"
    : >"$PIP_DROP_LOG"
    : >"$PIP_DROP_ACTIONS"
}

cleanup_env() {
    export PATH="$ORIGIN_PATH"
    unset PIP_DROP_LOG PIP_DROP_ACTIONS PIP_DROP_JSON PIP_DROP_VERSION
    unset PIP_DROP_NO_PIP PIP_DROP_UNINSTALL_STATUS PIP_DROP_INDEX_LINE
    if [ -n "${WORK:-}" ]; then
        rm -rf "$WORK"
    fi
}

run_in_env() {
    RUN_STATUS=0
    RUN_OUT="$("$BASH_BIN" "$SCRIPT" "$@" 2>"${WORK}/err")" || RUN_STATUS=$?
    RUN_ERR="$(cat "${WORK}/err" 2>/dev/null || true)"
    RUN_ACTIONS="$(cat "$PIP_DROP_ACTIONS" 2>/dev/null || true)"
    RUN_LOG="$(cat "$PIP_DROP_LOG" 2>/dev/null || true)"
}

test_no_editables() {
    say "no editables"
    new_env
    run_in_env --python "${WORK}/bin/python3"
    assert_ok "empty exit" "$RUN_STATUS"
    assert_contains "empty message" "No editable installs." "$RUN_OUT"
    assert_eq "no uninstall" "" "$RUN_ACTIONS"
    cleanup_env
}

test_help_version
test_usage_errors
test_no_editables

test_list_editables() {
    say "list editables"
    new_env
    checkout="${WORK}/checkout"
    mkdir -p "$checkout"
    export PIP_DROP_JSON="[{\"name\": \"Lupaxa-SSH-Doctor\", \"version\": \"0.1.0\", \"editable_project_location\": \"${checkout}\"}]"
    run_in_env --list --python "${WORK}/bin/python3"
    assert_ok "list exit" "$RUN_STATUS"
    assert_contains "python header" "Python: ${WORK}/bin/python3 (3.13.9)" "$RUN_OUT"
    assert_contains "count" "Editable installs (1):" "$RUN_OUT"
    assert_contains "name" "Lupaxa-SSH-Doctor" "$RUN_OUT"
    assert_contains "version" "0.1.0" "$RUN_OUT"
    assert_contains "checkout" "$checkout" "$RUN_OUT"
    assert_eq "list does not uninstall" "" "$RUN_ACTIONS"
    assert_contains "list argv" \
        "${BIN}/python3 -m pip list --editable --format=json --disable-pip-version-check" \
        "$RUN_LOG"
    [ -d "$checkout" ]
    assert_ok "checkout remains" "$?"
    cleanup_env
}

extract_version_probe() {
    sed -n "/^version_probe='/,/'\$/p" "$SCRIPT" |
        sed "1s/^version_probe='//; \$s/'\$//"
}

test_real_version_probe() {
    say "real version probe"
    probe="$(extract_version_probe)"
    probe_status=0
    probe_out="$(/usr/bin/python3 -c "$probe" /usr/bin/python3 2>/dev/null)" || probe_status=$?
    assert_ok "probe exit" "$probe_status"
    line1="$(printf '%s\n' "$probe_out" | sed -n '1p')"
    line2="$(printf '%s\n' "$probe_out" | sed -n '2p')"
    line3="$(printf '%s\n' "$probe_out" | sed -n '3p')"
    assert_eq "probe major" "3" "$line1"
    printf '%s\n' "$line2" | grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+$'
    assert_ok "probe version shape" "$?"
    expected_real="$(/usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.executable))')"
    assert_eq "probe realpath" "$expected_real" "$line3"
}

test_pyenv_versions() {
    say "pyenv versions"
    new_env
    rm -f "${BIN}/python3"
    root="${WORK}/pyenv"
    mkdir -p "${root}/shims" "${root}/versions/3.12.12/bin" "${root}/versions/3.13.9/bin" "${root}/versions/my-venv/bin" "${root}/versions/3.11.14/bin"
    cp "${ROOT}/tests/fixtures/python3" "${root}/shims/python3"
    chmod +x "${root}/shims/python3"
    printf '%s\n' '#!/bin/bash' 'echo "pyenv: python3.12: command not found" >&2' 'exit 1' >"${root}/shims/python3.12"
    chmod +x "${root}/shims/python3.12"
    ln -s "${root}/shims/python3" "${root}/versions/3.13.9/bin/python3"
    cp "${ROOT}/tests/fixtures/python3" "${root}/versions/3.12.12/bin/python3.12"
    chmod +x "${root}/versions/3.12.12/bin/python3.12"
    cp "${ROOT}/tests/fixtures/python3" "${root}/versions/my-venv/bin/python3"
    chmod +x "${root}/versions/my-venv/bin/python3"
    printf 'home = x\n' >"${root}/versions/3.11.14/pyvenv.cfg"
    cp "${ROOT}/tests/fixtures/python3" "${root}/versions/3.11.14/bin/python3.11"
    chmod +x "${root}/versions/3.11.14/bin/python3.11"
    export PATH="${root}/shims:${BIN}"
    unset PIP_DROP_VERSION
    run_in_env --all --list
    assert_ok "pyenv exit" "$RUN_STATUS"
    assert_contains "current shim" "Python: ${root}/shims/python3 (3.13.9)" "$RUN_OUT"
    assert_contains "installed 3.12" "Python: ${root}/versions/3.12.12/bin/python3.12 (3.12.0)" "$RUN_OUT"
    assert_absent "selected install is not a second row" "Python: ${root}/versions/3.13.9/bin/python3" "$RUN_OUT"
    assert_absent "unselected shim" "Python: ${root}/shims/python3.12" "$RUN_OUT"
    assert_absent "named env" "my-venv" "$RUN_OUT"
    assert_absent "pyvenv" "python3.11" "$RUN_OUT"
    cleanup_env
}

test_empty_version_field() {
    say "empty version field"
    new_env
    checkout="${WORK}/checkout"
    mkdir -p "$checkout"
    export PIP_DROP_JSON="[{\"name\":\"demo\",\"version\":\"\",\"editable_project_location\":\"${checkout}\"}]"
    run_in_env --list --python "${BIN}/python3"
    assert_ok "empty version exit" "$RUN_STATUS"
    name_line="$(printf '%s\n' "$RUN_OUT" | grep -F 'demo' || true)"
    assert_contains "empty version name" "demo" "$name_line"
    assert_absent "checkout is not the version" "$checkout" "$name_line"
    assert_contains "empty version checkout" "    ${checkout}" "$RUN_OUT"
    cleanup_env
}

test_list_editables
test_real_version_probe
test_pyenv_versions
test_empty_version_field

PTY_PY="/usr/bin/python3"

run_pty() {
    feed="$1"
    shift
    RUN_STATUS=0
    RUN_OUT="$("$PTY_PY" "${ROOT}/tests/pty-run.py" --feed "$feed" -- "$BASH_BIN" "$SCRIPT" "$@" 2>"${WORK}/err")" || RUN_STATUS=$?
    RUN_ERR="$(cat "${WORK}/err" 2>/dev/null || true)"
    RUN_ACTIONS="$(cat "$PIP_DROP_ACTIONS" 2>/dev/null || true)"
}

run_notty() {
    RUN_STATUS=0
    RUN_OUT="$("$PTY_PY" "${ROOT}/tests/pty-run.py" --notty -- "$BASH_BIN" "$SCRIPT" "$@" 2>"${WORK}/pty.err")" || RUN_STATUS=$?
    RUN_ERR="$(cat "${WORK}/pty.err" 2>/dev/null || true)"
}

test_two_pythons_no_tty() {
    say "two pythons no tty"
    new_env
    unset PIP_DROP_VERSION
    cp "${ROOT}/tests/fixtures/python3" "${BIN}/python3.12"
    chmod +x "${BIN}/python3.12"
    run_notty --list
    assert_eq "no tty exit" "2" "$RUN_STATUS"
    assert_contains "lists pythons" "Pythons on PATH:" "$RUN_ERR"
    cleanup_env
}

test_python_menu_columns() {
    say "python menu columns"
    new_env
    unset PIP_DROP_VERSION
    cp "${ROOT}/tests/fixtures/python3" "${BIN}/python3.9"
    chmod +x "${BIN}/python3.9"
    run_notty --list
    assert_eq "menu exit" "2" "$RUN_STATUS"
    printf '%s\n' "$RUN_ERR" >"${WORK}/menu"
    rows=0
    seen_ver=""
    seen_path=""
    while IFS= read -r line; do
        case "$line" in
            "  "*) ;;
            *) continue ;;
        esac
        ver_at="$(printf '%s\n' "$line" | awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print RSTART; exit }')"
        path_at="$(printf '%s\n' "$line" | awk 'match($0, / \//) { print RSTART + 1; exit }')"
        [ -n "$ver_at" ] && [ -n "$path_at" ] || continue
        rows=$((rows + 1))
        if [ -z "$seen_ver" ]; then
            seen_ver="$ver_at"
            seen_path="$path_at"
        else
            assert_eq "version column" "$seen_ver" "$ver_at"
            assert_eq "path column" "$seen_path" "$path_at"
        fi
    done <"${WORK}/menu"
    assert_eq "menu rows" "2" "$rows"
    cleanup_env
}

test_same_binary_one_row() {
    say "same binary one row"
    new_env
    ln -s python3 "${BIN}/python3.13"
    run_in_env --list
    assert_ok "one python no prompt" "$RUN_STATUS"
    cleanup_env
}

test_python_flag_off_path() {
    say "python off path"
    new_env
    off="${WORK}/venv/bin"
    mkdir -p "$off"
    cp "${ROOT}/tests/fixtures/python3" "${off}/python"
    chmod +x "${off}/python"
    export PIP_DROP_VERSION="3.11.9"
    run_in_env --list --python "${off}/python"
    assert_ok "off path exit" "$RUN_STATUS"
    assert_contains "off path header" "Python: ${off}/python (3.11.9)" "$RUN_OUT"
    cleanup_env
}

test_version_flag() {
    say "python version flag"
    new_env
    unset PIP_DROP_VERSION
    cp "${ROOT}/tests/fixtures/python3" "${BIN}/python3.12"
    chmod +x "${BIN}/python3.12"
    run_in_env --list --python-version 3.12
    assert_ok "3.12 exit" "$RUN_STATUS"
    assert_contains "3.12 selected" "3.12.0" "$RUN_OUT"
    assert_contains "3.12 python header" "Python: ${BIN}/python3.12 (3.12.0)" "$RUN_OUT"
    assert_absent "not default python header" "Python: ${BIN}/python3 (3.13.9)" "$RUN_OUT"
    cleanup_env
}

test_missing_version() {
    say "missing version"
    new_env
    run_in_env --list --python-version 3.10
    assert_eq "missing version" "2" "$RUN_STATUS"
    cleanup_env
}

with_two_pythons() {
    new_env
    unset PIP_DROP_VERSION
    cp "${ROOT}/tests/fixtures/python3" "${BIN}/python3.12"
    chmod +x "${BIN}/python3.12"
}

test_prompt_current() {
    say "prompt current"
    with_two_pythons
    run_pty $'\n' --list
    assert_ok "empty answer" "$RUN_STATUS"
    assert_contains "current version" "3.13.9" "$RUN_OUT"
    assert_contains "current python header" "Python: ${BIN}/python3 (3.13.9)" "$RUN_OUT"
    assert_absent "not 3.12 header" "Python: ${BIN}/python3.12 (3.12.0)" "$RUN_OUT"
    cleanup_env
}

test_prompt_version() {
    say "prompt version"
    with_two_pythons
    run_pty $'3.12\n' --list
    assert_ok "answer 3.12" "$RUN_STATUS"
    assert_contains "answered 3.12" "3.12.0" "$RUN_OUT"
    assert_contains "3.12 python header" "Python: ${BIN}/python3.12 (3.12.0)" "$RUN_OUT"
    assert_absent "not default header" "Python: ${BIN}/python3 (3.13.9)" "$RUN_OUT"
    cleanup_env
}

test_prompt_all() {
    say "prompt all"
    with_two_pythons
    run_pty $'all\n' --list
    assert_ok "answer all" "$RUN_STATUS"
    assert_contains "all current" "3.13.9" "$RUN_OUT"
    assert_contains "all 3.12" "3.12.0" "$RUN_OUT"
    assert_contains "all default header" "Python: ${BIN}/python3 (3.13.9)" "$RUN_OUT"
    assert_contains "all 3.12 header" "Python: ${BIN}/python3.12 (3.12.0)" "$RUN_OUT"
    cleanup_env
}

test_prompt_junk() {
    say "prompt junk"
    with_two_pythons
    run_pty $'nope\n' --yes --list
    assert_ok "junk exit" "$RUN_STATUS"
    assert_contains "junk leaves" "Left in place." "$RUN_OUT"
    cleanup_env
}

test_dry_run() {
    say "dry run"
    new_env
    checkout="${WORK}/checkout"
    mkdir -p "$checkout"
    export PIP_DROP_JSON="[{\"name\":\"Lupaxa-SSH-Doctor\",\"version\":\"0.1.0\",\"editable_project_location\":\"${checkout}\"}]"
    run_in_env -n --python "${BIN}/python3"
    assert_ok "dry exit" "$RUN_STATUS"
    assert_contains "dry message" "Dry run. Nothing uninstalled." "$RUN_OUT"
    assert_eq "dry records nothing" "" "$RUN_ACTIONS"
    [ -d "$checkout" ]
    assert_ok "dry checkout remains" "$?"
    cleanup_env
}

test_decline() {
    say "decline uninstall"
    new_env
    export PIP_DROP_JSON='[{"name":"demo","version":"1","editable_project_location":"/tmp/demo"}]'
    run_pty $'n\n' --python "${BIN}/python3"
    assert_ok "decline exit" "$RUN_STATUS"
    assert_contains "uninstall prompt" "Uninstall these 1 editable installs? [y/N]: " "$RUN_OUT"
    assert_contains "left in place" "Left in place." "$RUN_OUT"
    assert_eq "decline records nothing" "" "$RUN_ACTIONS"
    cleanup_env
}

test_check_blocks() {
    say "check blocks"
    new_env
    export PIP_DROP_JSON='[{"name":"demo","version":"1.0.0","editable_project_location":"/tmp/demo"}]'
    run_in_env --check --python "${BIN}/python3"
    assert_eq "check exit" "1" "$RUN_STATUS"
    assert_contains "interpreter" "Python: ${BIN}/python3 (3.13.9)" "$RUN_OUT"
    assert_contains "package name" "demo" "$RUN_OUT"
    assert_contains "installed version" "1.0.0" "$RUN_OUT"
    assert_contains "checkout path" "/tmp/demo" "$RUN_OUT"
    assert_contains "blocks" "blocks pip install -U" "$RUN_OUT"
    assert_eq "check does not uninstall" "" "$RUN_ACTIONS"
    cleanup_env
}

test_check_clean() {
    say "check clean"
    new_env
    run_in_env --check --python "${BIN}/python3"
    assert_ok "clean check" "$RUN_STATUS"
    assert_contains "clean message" "No editable installs." "$RUN_OUT"
    cleanup_env
}

test_check_index() {
    say "check index"
    new_env
    export PIP_DROP_JSON='[{"name":"Demo_Package","version":"1.0","editable_project_location":"/tmp/demo"}]'
    export PIP_DROP_INDEX_LINE="published 1.2.0"
    run_in_env --check --index --python "${BIN}/python3"
    assert_eq "index exit" "1" "$RUN_STATUS"
    assert_contains "published" "1.2.0" "$RUN_OUT"
    assert_contains "still blocks" "blocks pip install -U" "$RUN_OUT"
    cleanup_env
}

test_check_index_down() {
    say "check index down"
    new_env
    export PIP_DROP_JSON='[{"name":"demo","version":"1.0.0","editable_project_location":"/tmp/demo"}]'
    export PIP_DROP_INDEX_LINE="unavailable timeout"
    run_in_env --check --index --python "${BIN}/python3"
    assert_contains "unavailable" "index: unavailable" "$RUN_OUT"
    assert_contains "local block remains" "blocks pip install -U" "$RUN_OUT"
    cleanup_env
}

test_check_index_unparsed() {
    say "check index unparsed"
    new_env
    export PIP_DROP_JSON='[{"name":"demo","version":"1.0.0","editable_project_location":"/tmp/demo"}]'
    export PIP_DROP_INDEX_LINE="unparsed"
    run_in_env --check --index --python "${BIN}/python3"
    assert_contains "unparsed" "unparsed" "$RUN_OUT"
    assert_contains "unparsed still blocks" "blocks pip install -U" "$RUN_OUT"
    cleanup_env
}

test_check_index_failure_continues() {
    say "index failure continues"
    new_env
    hidden="${WORK}/hidden"
    mkdir -p "$hidden"
    cp "${BIN}/python3" "${hidden}/python3"
    chmod +x "${hidden}/python3"
    cat >"${BIN}/python3" <<EOF
#!/bin/bash
if [ "\${1:-}" = "-" ]; then
    count_file="${WORK}/index-calls"
    n=0
    if [ -f "\$count_file" ]; then
        n="\$(cat "\$count_file")"
    fi
    n=\$((n + 1))
    printf '%s\n' "\$n" >"\$count_file"
    if [ "\$n" -eq 1 ]; then
        cat >/dev/null
        exit 1
    fi
fi
exec $(printf '%q' "${hidden}/python3") "\$@"
EOF
    chmod +x "${BIN}/python3"
    export PIP_DROP_JSON='[{"name":"demo","version":"1.0.0","editable_project_location":"/tmp/demo"},{"name":"other","version":"2.0.0","editable_project_location":"/tmp/other"}]'
    export PIP_DROP_INDEX_LINE="published 9.9.9"
    run_in_env --check --index --python "${BIN}/python3"
    assert_eq "index failure exit" "1" "$RUN_STATUS"
    assert_contains "first package" "demo" "$RUN_OUT"
    assert_contains "failed index unavailable" "index: unavailable" "$RUN_OUT"
    assert_contains "second package" "other" "$RUN_OUT"
    assert_contains "second published" "9.9.9" "$RUN_OUT"
    count="$(printf '%s\n' "$RUN_OUT" | grep -c 'blocks pip install -U' || true)"
    assert_eq "both packages block" "2" "$count"
    assert_eq "index failure records nothing" "" "$RUN_ACTIONS"
    cleanup_env
}

test_yes_uninstalls() {
    say "yes uninstalls"
    new_env
    checkout="${WORK}/checkout"
    mkdir -p "$checkout"
    export PIP_DROP_JSON="[{\"name\":\"Lupaxa-SSH-Doctor\",\"version\":\"0.1.0\",\"editable_project_location\":\"${checkout}\"}]"
    run_in_env -y --python "${BIN}/python3" lupaxa-ssh-doctor
    assert_ok "yes exit" "$RUN_STATUS"
    assert_contains "uninstall recorded" "uninstall Lupaxa-SSH-Doctor" "$RUN_ACTIONS"
    assert_contains "removed" "Removed editable installs." "$RUN_OUT"
    assert_contains "checkouts stay" "Checkouts on disk were not deleted. Dependencies were left installed." "$RUN_OUT"
    assert_contains "upgrade hint" "python -m pip install -U <name>" "$RUN_OUT"
    assert_contains "cache hint" "--no-cache-dir" "$RUN_OUT"
    assert_contains "purge hint" "pip-drop-editables --purge-cache" "$RUN_OUT"
    assert_contains "uninstall argv" \
        "${BIN}/python3 -m pip uninstall -y --disable-pip-version-check Lupaxa-SSH-Doctor" \
        "$RUN_LOG"
    [ -d "$checkout" ]
    assert_ok "yes checkout remains" "$?"
    cleanup_env
}

test_not_editable_name() {
    say "not editable name"
    new_env
    export PIP_DROP_JSON='[{"name":"demo","version":"1","editable_project_location":"/tmp/demo"}]'
    run_in_env -y --python "${BIN}/python3" requests
    assert_eq "missing name" "2" "$RUN_STATUS"
    assert_contains "not editable" "not an editable install" "$RUN_ERR"
    assert_eq "missing records nothing" "" "$RUN_ACTIONS"
    cleanup_env
}

test_same_binary_uninstalls_once() {
    say "same binary once"
    new_env
    ln -s python3 "${BIN}/python3.13"
    export PIP_DROP_JSON='[{"name":"demo","version":"1","editable_project_location":"/tmp/demo"}]'
    run_in_env --all -y
    assert_ok "once exit" "$RUN_STATUS"
    count="$(printf '%s\n' "$RUN_ACTIONS" | grep -c 'uninstall demo' || true)"
    assert_eq "one uninstall" "1" "$count"
    cleanup_env
}

test_purge_after_uninstall() {
    say "purge after uninstall"
    new_env
    export PIP_DROP_JSON='[{"name":"demo","version":"1","editable_project_location":"/tmp/demo"}]'
    run_in_env -y --purge-cache --python "${BIN}/python3"
    assert_eq "uninstall exit" "0" "$RUN_STATUS"
    assert_contains "purged" "purge" "$RUN_ACTIONS"
    assert_contains "purge argv" \
        "${BIN}/python3 -m pip cache purge --disable-pip-version-check" \
        "$RUN_LOG"
    assert_absent "purged success skips cache hint" "--no-cache-dir" "$RUN_OUT"
    cleanup_env
}

test_no_purge_on_dry_run() {
    say "no purge on dry run"
    new_env
    export PIP_DROP_JSON='[{"name":"demo","version":"1","editable_project_location":"/tmp/demo"}]'
    run_in_env -n --purge-cache --python "${BIN}/python3"
    assert_ok "dry purge exit" "$RUN_STATUS"
    assert_eq "no purge action" "" "$RUN_ACTIONS"
    cleanup_env
}

test_no_purge_on_list() {
    say "no purge on list"
    new_env
    export PIP_DROP_JSON='[{"name":"demo","version":"1","editable_project_location":"/tmp/demo"}]'
    run_in_env --list --purge-cache --python "${BIN}/python3"
    assert_ok "list purge exit" "$RUN_STATUS"
    assert_eq "list purge action" "" "$RUN_ACTIONS"
    cleanup_env
}

test_no_purge_on_empty_list() {
    say "no purge on empty list"
    new_env
    run_in_env --list --purge-cache --python "${BIN}/python3"
    assert_ok "empty list purge exit" "$RUN_STATUS"
    assert_contains "empty list message" "No editable installs." "$RUN_OUT"
    assert_eq "empty list purge action" "" "$RUN_ACTIONS"
    cleanup_env
}

test_no_purge_on_check() {
    say "no purge on check"
    new_env
    export PIP_DROP_JSON='[{"name":"demo","version":"1","editable_project_location":"/tmp/demo"}]'
    run_in_env --check --purge-cache --python "${BIN}/python3"
    assert_eq "check purge exit" "1" "$RUN_STATUS"
    assert_contains "check still blocks" "blocks pip install -U" "$RUN_OUT"
    assert_absent "check does not purge" "purge" "$RUN_ACTIONS"
    assert_absent "check does not uninstall" "uninstall" "$RUN_ACTIONS"
    assert_eq "check records nothing" "" "$RUN_ACTIONS"
    cleanup_env
}

test_no_purge_on_empty_check() {
    say "no purge on empty check"
    new_env
    run_in_env --check --purge-cache --python "${BIN}/python3"
    assert_ok "empty check purge exit" "$RUN_STATUS"
    assert_contains "empty check message" "No editable installs." "$RUN_OUT"
    assert_eq "empty check purge action" "" "$RUN_ACTIONS"
    cleanup_env
}

test_purge_when_empty() {
    say "purge when empty"
    new_env
    run_in_env --purge-cache --python "${BIN}/python3"
    assert_ok "empty purge exit" "$RUN_STATUS"
    assert_contains "empty purge message" "No editable installs." "$RUN_OUT"
    assert_contains "empty purged" "purge" "$RUN_ACTIONS"
    cleanup_env
}

test_purge_each_interpreter() {
    say "purge each interpreter"
    new_env
    unset PIP_DROP_VERSION
    cp "${ROOT}/tests/fixtures/python3" "${BIN}/python3.12"
    chmod +x "${BIN}/python3.12"
    run_in_env --all --purge-cache
    assert_ok "each purge exit" "$RUN_STATUS"
    count="$(printf '%s\n' "$RUN_ACTIONS" | grep -c '^purge$' || true)"
    assert_eq "purge once per interpreter" "2" "$count"
    cleanup_env
}

test_uninstall_failure_continues() {
    say "uninstall failure continues"
    new_env
    export PIP_DROP_JSON='[{"name":"demo","version":"1","editable_project_location":"/tmp/demo"},{"name":"other","version":"2","editable_project_location":"/tmp/other"}]'
    export PIP_DROP_UNINSTALL_STATUS=1
    run_in_env -y --purge-cache --python "${BIN}/python3"
    assert_eq "partial exit" "1" "$RUN_STATUS"
    assert_contains "first uninstall" "uninstall demo" "$RUN_ACTIONS"
    assert_contains "second uninstall" "uninstall other" "$RUN_ACTIONS"
    assert_contains "purge after failure" "purge" "$RUN_ACTIONS"
    cleanup_env
}

test_no_pip_one_interpreter() {
    say "no pip on one interpreter"
    new_env
    hidden="${WORK}/hidden"
    mkdir -p "$hidden"
    cp "${BIN}/python3" "${hidden}/python3"
    cp "${BIN}/python3" "${BIN}/python3.12"
    chmod +x "${hidden}/python3" "${BIN}/python3.12"
    cat >"${BIN}/python3" <<EOF
#!/bin/bash
export PIP_DROP_NO_PIP=1
exec $(printf '%q' "${hidden}/python3") "\$@"
EOF
    chmod +x "${BIN}/python3"
    export PIP_DROP_JSON='[{"name":"demo","version":"1","editable_project_location":"/tmp/demo"}]'
    run_in_env --all -y
    assert_eq "no pip exit" "1" "$RUN_STATUS"
    fail_lines="$(printf '%s\n' "$RUN_ERR" | grep -F 'pip list failed for' || true)"
    assert_eq "no pip full line" "pip list failed for ${BIN}/python3" "$fail_lines"
    assert_absent "healthy path absent from failures" "${BIN}/python3.12" "$fail_lines"
    assert_contains "healthy uninstall" "uninstall demo" "$RUN_ACTIONS"
    cleanup_env
}

test_two_pythons_no_tty
test_python_menu_columns
test_same_binary_one_row
test_python_flag_off_path
test_version_flag
test_missing_version
test_prompt_current
test_prompt_version
test_prompt_all
test_prompt_junk
test_dry_run
test_decline
test_check_blocks
test_check_clean
test_check_index
test_check_index_down
test_check_index_unparsed
test_check_index_failure_continues
test_yes_uninstalls
test_not_editable_name
test_same_binary_uninstalls_once
test_purge_after_uninstall
test_no_purge_on_dry_run
test_no_purge_on_list
test_no_purge_on_empty_list
test_no_purge_on_check
test_no_purge_on_empty_check
test_purge_when_empty
test_purge_each_interpreter
test_uninstall_failure_continues
test_no_pip_one_interpreter

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
