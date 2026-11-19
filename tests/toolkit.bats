#!/usr/bin/env bats
# Run with: bats tests/

setup() {
  BIN="$BATS_TEST_DIRNAME/../bin"
  FIX="$BATS_TEST_DIRNAME/fixtures"
  export NO_COLOR=1
  TMP="$(mktemp -d)"
}
teardown() { rm -rf "$TMP"; }

# ---------- sysreport ----------
@test "sysreport: text report has all sections" {
  run "$BIN/sysreport.sh" --disk-warn 100 --mem-warn 100
  [[ "$output" == *"Load"* && "$output" == *"Memory"* && "$output" == *"Disks"* ]]
}
@test "sysreport: --json is valid JSON with expected keys" {
  run bash -c "'$BIN/sysreport.sh' --json --disk-warn 100 --mem-warn 100 | python3 -c 'import json,sys; d=json.load(sys.stdin); assert {\"load\",\"memory_used_pct\",\"disks\",\"status\"} <= d.keys()'"
  [ "$status" -eq 0 ]
}
@test "sysreport: low threshold triggers warning exit code" {
  run "$BIN/sysreport.sh" --mem-warn 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARNINGS"* ]]
}
@test "sysreport: rejects unknown option" {
  run "$BIN/sysreport.sh" --bogus
  [ "$status" -eq 2 ]
}

# ---------- netcheck ----------
@test "netcheck: localhost DNS resolves" {
  run "$BIN/netcheck.sh" dns:localhost
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"localhost"* ]]
}
@test "netcheck: open and closed TCP ports detected" {
  python3 -m http.server 18080 --bind 127.0.0.1 >/dev/null 2>&1 & pid=$!
  sleep 1
  run "$BIN/netcheck.sh" tcp:127.0.0.1:18080 tcp:127.0.0.1:1 http:http://127.0.0.1:18080/
  kill $pid
  [ "$status" -eq 1 ]            # exactly one failure (port 1)
  [[ "$output" == *"3 checks, 1 failed"* ]]
}
@test "netcheck: reads targets from file and ignores comments" {
  printf '# comment\n\ndns:localhost\n' > "$TMP/t.txt"
  run "$BIN/netcheck.sh" -f "$TMP/t.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 checks, 0 failed"* ]]
}

# ---------- backup ----------
@test "backup: creates verified archive with checksum" {
  mkdir -p "$TMP/data"; echo hello > "$TMP/data/a.txt"
  run "$BIN/backup.sh" -s "$TMP/data" -d "$TMP/bk"
  [ "$status" -eq 0 ]
  ls "$TMP"/bk/data_*.tar.gz
  ls "$TMP"/bk/data_*.tar.gz.sha256
}
@test "backup: retention keeps only N archives" {
  mkdir -p "$TMP/data"; echo x > "$TMP/data/f"
  for i in 1 2 3 4; do "$BIN/backup.sh" -s "$TMP/data" -d "$TMP/bk" -k 2 2>/dev/null; sleep 1.1; done
  [ "$(find "$TMP/bk" -name '*.tar.gz' | wc -l)" -eq 2 ]
}
@test "backup: exclude pattern is honoured" {
  mkdir -p "$TMP/data"; echo keep > "$TMP/data/keep.txt"; echo skip > "$TMP/data/skip.log"
  "$BIN/backup.sh" -s "$TMP/data" -d "$TMP/bk" -e '*.log' 2>/dev/null
  run tar -tzf "$(ls "$TMP"/bk/*.tar.gz)"
  [[ "$output" == *"keep.txt"* && "$output" != *"skip.log"* ]]
}
@test "backup: --verify detects tampering" {
  mkdir -p "$TMP/data"; echo x > "$TMP/data/f"
  "$BIN/backup.sh" -s "$TMP/data" -d "$TMP/bk" 2>/dev/null
  a=$(ls "$TMP"/bk/*.tar.gz); echo junk >> "$a"
  run "$BIN/backup.sh" --verify "$a"
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
}
@test "backup: fails cleanly on missing source" {
  run "$BIN/backup.sh" -s /nope -d "$TMP/bk"
  [ "$status" -eq 1 ]
}

# ---------- logwatch ----------
@test "logwatch nginx: counts and flags high 5xx ratio" {
  run "$BIN/logwatch.sh" nginx "$FIX/access.log"
  [ "$status" -eq 1 ]                       # 2/8 = 25% 5xx
  [[ "$output" == *"8 requests"* && "$output" == *"25.00%"* ]]
}
@test "logwatch auth: finds brute-force source" {
  run "$BIN/logwatch.sh" auth "$FIX/auth.log"
  [ "$status" -eq 0 ]                       # 4 fails < threshold 20
  [[ "$output" == *"failed SSH password attempts : 4"* ]]
  [[ "$output" == *"3 203.0.113.9"* ]]
}
@test "logwatch auth: threshold triggers non-zero exit" {
  SSH_FAIL_THRESHOLD=2 run "$BIN/logwatch.sh" auth "$FIX/auth.log"
  [ "$status" -eq 1 ]
}

# ---------- user_audit ----------
@test "user_audit: flags extra UID 0 account" {
  run "$BIN/user_audit.sh" --passwd "$FIX/passwd" --group "$FIX/group" --shadow /nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"backdoor"* && "$output" == *"sudo: deploy"* ]]
}

# ---------- service_watchdog ----------
@test "watchdog: restarts a dead process and rate-limits" {
  export STATE_DIR="$TMP/wd" WATCHDOG_SETTLE=1
  run "$BIN/service_watchdog.sh" -n fake-svc-xyz -r "true" -m 1
  [ "$status" -eq 1 ]                        # restart cmd 'true' doesn't bring it up
  run "$BIN/service_watchdog.sh" -n fake-svc-xyz -r "true" -m 1
  [ "$status" -eq 2 ]                        # limit reached
  [[ "$output" == *"giving up"* ]]
}
@test "watchdog: healthy process passes" {
  sleep 30 & pid=$!
  run "$BIN/service_watchdog.sh" -n sleep
  kill $pid
  [ "$status" -eq 0 ]
}
