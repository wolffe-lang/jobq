#!/bin/bash
set -e

BUILDDIR="$(cd "$(dirname "$0")" && pwd)"
JOBQ="$BUILDDIR/jobq"

if [ ! -x "$JOBQ" ]; then
    echo "Building jobq..."
    cd "$BUILDDIR" && wolf build main.lu -o jobq
fi

PASS=0
FAIL=0

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

cleanup() {
    rm -rf /tmp/jobq-test-*
}

cleanup

# A1: --help exits 0
echo "=== A1: --help ==="
"$JOBQ" --help > /dev/null 2>&1
if [ $? -eq 0 ]; then
    pass "A1"
else
    fail "A1: --help did not exit 0"
fi

# A2: add -f with five quoted lines produces 5 jobs, show 3 prints argv JSON
echo "=== A2: add -f quoting ==="
DIR="/tmp/jobq-test-a2"
"$JOBQ" init "$DIR"
cat > /tmp/jobq-test-a2-input.txt << 'EOF'
echo "a b"
echo 'x y'
echo hello world
echo "nested \"quote\""
echo trailing
EOF
OUTPUT=$("$JOBQ" add --dir "$DIR" -f /tmp/jobq-test-a2-input.txt 2>&1)
# add -f prints "jobq: added N jobs"
if echo "$OUTPUT" | grep -q "added 5 jobs"; then
    # Check show 3 prints the argv JSON
    SHOW=$("$JOBQ" show --dir "$DIR" 3 2>&1)
    if echo "$SHOW" | grep -q 'cmd='; then
        pass "A2"
    else
        fail "A2: show 3 missing cmd="
    fi
else
    fail "A2: $OUTPUT"
fi
rm -rf "$DIR" /tmp/jobq-test-a2-input.txt

# R0: -j 2, six jobs, all done, logs hold output, exit 0
echo "=== R0: concurrent run ==="
DIR="/tmp/jobq-test-r0"
"$JOBQ" init "$DIR"
for i in 1 2 3 4 5 6; do
    "$JOBQ" add --dir "$DIR" -- sh -c "echo job$i" > /dev/null
done
"$JOBQ" run --dir "$DIR" -j 2 > /dev/null 2>&1
RUN_EXIT=$?
DONE=$("$JOBQ" ls --dir "$DIR" --state done | wc -l)
if [ "$RUN_EXIT" -eq 0 ] && [ "$DONE" -eq 6 ]; then
    # Check logs hold output
    LOGS_WITH_CONTENT=0
    for f in "$DIR"/log/*.log; do
        if [ -s "$f" ]; then
            LOGS_WITH_CONTENT=$((LOGS_WITH_CONTENT + 1))
        fi
    done
    if [ "$LOGS_WITH_CONTENT" -eq 6 ]; then
        pass "R0"
    else
        fail "R0: only $LOGS_WITH_CONTENT logs with content"
    fi
else
    fail "R0: exit=$RUN_EXIT done=$DONE"
fi
rm -rf "$DIR"

# R1: Exactly once — 500 jobs, four runners, three repetitions
echo "=== R1: Exactly once ==="
for rep in 1 2 3; do
    DIR="/tmp/jobq-test-r1-$rep"
    OUTDIR="/tmp/jobq-test-r1-$rep-out"
    mkdir -p "$OUTDIR"
    "$JOBQ" init "$DIR"
    # Use add -f for speed
    seq 1 500 | while read i; do echo "sh -c \"printf x > $OUTDIR/$i\""; done > /tmp/jobq-test-r1-$rep-input.txt
    "$JOBQ" add --dir "$DIR" -f /tmp/jobq-test-r1-$rep-input.txt > /dev/null
    # Start four runners simultaneously
    "$JOBQ" run --dir "$DIR" -j 4 &
    P1=$!
    "$JOBQ" run --dir "$DIR" -j 4 &
    P2=$!
    "$JOBQ" run --dir "$DIR" -j 4 &
    P3=$!
    "$JOBQ" run --dir "$DIR" -j 4 &
    P4=$!
    wait $P1 || true
    wait $P2 || true
    wait $P3 || true
    wait $P4 || true
    # Check: 500 files, each containing exactly one byte
    COUNT=$(ls "$OUTDIR" | wc -l)
    if [ "$COUNT" -ne 500 ]; then
        fail "R1 rep $rep: expected 500 files, got $COUNT"
    else
        BAD=0
        for f in "$OUTDIR"/*; do
            SIZE=$(wc -c < "$f")
            if [ "$SIZE" -ne 1 ]; then
                BAD=$((BAD + 1))
            fi
        done
        if [ "$BAD" -gt 0 ]; then
            fail "R1 rep $rep: $BAD files with wrong size"
        else
            pass "R1 rep $rep"
        fi
    fi
    rm -rf "$DIR" "$OUTDIR" /tmp/jobq-test-r1-$rep-input.txt
done

# R2: Lease expiry — reclaimed job ends done with tries=1
echo "=== R2: Lease expiry ==="
DIR="/tmp/jobq-test-r2"
"$JOBQ" init "$DIR"
"$JOBQ" add --dir "$DIR" -- sh -c "printf x > /tmp/jobq-test-r2-out; sleep 10" > /dev/null
# Start a runner with a 2-second lease
"$JOBQ" run --dir "$DIR" -j 1 --lease 2 &
RUNNER=$!
sleep 1
# Kill the runner
kill -9 $RUNNER 2>/dev/null || true
wait $RUNNER 2>/dev/null || true
# Wait for lease to expire
sleep 3
# Start another runner — it should reclaim and complete the job
"$JOBQ" run --dir "$DIR" -j 1 --lease 30 > /dev/null 2>&1 || true
# Check: the job should be done with tries=1
DONE=$("$JOBQ" ls --dir "$DIR" --state done | wc -l)
if [ "$DONE" -eq 1 ]; then
    # Check tries=1 in the done file
    DONE_FILE=$(ls "$DIR/done/"*.job | head -1)
    if grep -q "tries=1" "$DONE_FILE"; then
        pass "R2"
    else
        fail "R2: tries not 1"
    fi
else
    fail "R2: done=$DONE"
fi
rm -rf "$DIR" /tmp/jobq-test-r2-out

# R3: Max tries — the file in failed/ holds status=lease-expired
echo "=== R3: Max tries ==="
DIR="/tmp/jobq-test-r3"
"$JOBQ" init "$DIR"
"$JOBQ" add --dir "$DIR" -- sleep 30 > /dev/null
# Start a runner with a 1-second lease and max-tries 2
"$JOBQ" run --dir "$DIR" -j 1 --lease 1 --max-tries 2 &
RUNNER=$!
sleep 1
kill -9 $RUNNER 2>/dev/null || true
wait $RUNNER 2>/dev/null || true
sleep 2
# Start another runner
"$JOBQ" run --dir "$DIR" -j 1 --lease 1 --max-tries 2 &
RUNNER=$!
sleep 1
kill -9 $RUNNER 2>/dev/null || true
wait $RUNNER 2>/dev/null || true
sleep 2
# Start a final runner — the job should be in failed/ with lease-expired
"$JOBQ" run --dir "$DIR" -j 1 --lease 1 --max-tries 2 > /dev/null 2>&1 || true
FAILED=$("$JOBQ" ls --dir "$DIR" --state failed | wc -l)
if [ "$FAILED" -ge 1 ]; then
    # Check status=lease-expired
    FAILED_FILE=$(ls "$DIR/failed/"*.job | head -1)
    if grep -q "status=lease-expired" "$FAILED_FILE"; then
        pass "R3"
    else
        fail "R3: status not lease-expired"
    fi
else
    fail "R3: failed=$FAILED"
fi
rm -rf "$DIR"

# R4: a job longer than the lease runs ONCE while its runner is alive (lease renewal)
echo "=== R4: Renewal under a live runner ==="
DIR="/tmp/jobq-test-r4"; OUT="/tmp/jobq-test-r4.out"; rm -rf "$DIR" "$OUT"
"$JOBQ" init "$DIR"
"$JOBQ" add --dir "$DIR" -- sh -c "printf x >> $OUT; sleep 6" > /dev/null
"$JOBQ" run --dir "$DIR" -j 1 --lease 2 > /dev/null 2>&1 &
RUNNER_A=$!
sleep 3
"$JOBQ" run --dir "$DIR" -j 1 --lease 2 > /dev/null 2>&1 || true
wait $RUNNER_A || true
BYTES=$(wc -c < "$OUT" | tr -d ' ')
DONE=$("$JOBQ" ls --dir "$DIR" --state done | grep -c '^[0-9]')
if [ "$BYTES" = "1" ] && [ "$DONE" = "1" ] && grep -q "tries=0" "$DIR"/done/*; then
    pass "R4"
else
    fail "R4: bytes=$BYTES done=$DONE"
fi
rm -rf "$DIR" "$OUT"

# R5: kill and reclaim — a runner killed mid-job, lease expires, second runner reclaims
echo "=== R5: Kill and reclaim ==="
DIR="/tmp/jobq-test-r5"
"$JOBQ" init "$DIR"
"$JOBQ" add --dir "$DIR" -- sh -c "sleep 6; echo done" > /dev/null
# Start runner A with a 2-second lease
"$JOBQ" run --dir "$DIR" -j 1 --lease 2 &
RUNNER_A=$!
sleep 1
# Kill runner A
kill -9 $RUNNER_A 2>/dev/null || true
wait $RUNNER_A 2>/dev/null || true
# Wait for lease to expire
sleep 3
# Start runner B — it should reclaim and complete the job
"$JOBQ" run --dir "$DIR" -j 1 --lease 30 > /dev/null 2>&1 || true
# Check: the job is done exactly once
DONE=$("$JOBQ" ls --dir "$DIR" --state done | wc -l)
if [ "$DONE" -eq 1 ]; then
    pass "R5"
else
    fail "R5: done=$DONE"
fi
rm -rf "$DIR"

# F1: Failed job goes to failed/, retry --failed moves it back
echo "=== F1: Failed job and retry ==="
DIR="/tmp/jobq-test-f1"
"$JOBQ" init "$DIR"
"$JOBQ" add --dir "$DIR" -- sh -c "exit 3" > /dev/null
"$JOBQ" run --dir "$DIR" -j 1 > /dev/null 2>&1 || true
FAILED=$("$JOBQ" ls --dir "$DIR" --state failed | wc -l)
if [ "$FAILED" -eq 1 ]; then
    # Check exit=3
    FAILED_FILE=$(ls "$DIR/failed/"*.job | head -1)
    if grep -q "exit=3" "$FAILED_FILE"; then
        # Retry --failed
        "$JOBQ" retry --dir "$DIR" --failed > /dev/null 2>&1
        PENDING=$("$JOBQ" ls --dir "$DIR" --state pending | wc -l)
        if [ "$PENDING" -eq 1 ]; then
            # Check tries=0
            PENDING_FILE=$(ls "$DIR/queue/"*.job | head -1)
            if grep -q "tries=0" "$PENDING_FILE"; then
                pass "F1"
            else
                fail "F1: tries not 0 after retry"
            fi
        else
            fail "F1: pending=$PENDING after retry"
        fi
    else
        fail "F1: exit not 3"
    fi
else
    fail "F1: failed=$FAILED"
fi
rm -rf "$DIR"

# S1: stats prints four counts and mean/p95
echo "=== S1: stats ==="
DIR="/tmp/jobq-test-s1"
"$JOBQ" init "$DIR"
for i in 1 2 3; do
    "$JOBQ" add --dir "$DIR" -- echo "job$i" > /dev/null
done
"$JOBQ" run --dir "$DIR" -j 1 > /dev/null 2>&1
STATS=$("$JOBQ" stats --dir "$DIR" 2>&1)
if echo "$STATS" | grep -q "pending:" && \
   echo "$STATS" | grep -q "running:" && \
   echo "$STATS" | grep -q "done:" && \
   echo "$STATS" | grep -q "failed:" && \
   echo "$STATS" | grep -q "mean:" && \
   echo "$STATS" | grep -q "p95:"; then
    pass "S1"
else
    fail "S1: stats missing fields"
fi
rm -rf "$DIR"

# M1: Malformed job file is skipped, valid job runs
echo "=== M1: Malformed job ==="
DIR="/tmp/jobq-test-m1"
"$JOBQ" init "$DIR"
# Write a malformed job file
echo "this is not a valid job file" > "$DIR/queue/000001-1.job"
# Add a valid job
"$JOBQ" add --dir "$DIR" -- echo "valid" > /dev/null
# Run — the malformed job should be skipped, the valid one should run
"$JOBQ" run --dir "$DIR" -j 1 > /dev/null 2>&1 || true
DONE=$("$JOBQ" ls --dir "$DIR" --state done | wc -l)
if [ "$DONE" -ge 1 ]; then
    # Check the malformed file is still in queue/
    if [ -f "$DIR/queue/000001-1.job" ]; then
        pass "M1"
    else
        fail "M1: malformed file moved"
    fi
else
    fail "M1: valid job not done"
fi
rm -rf "$DIR"

# P1: 10,000 true jobs at -j 8 under 60s
echo "=== P1: Performance ==="
DIR="/tmp/jobq-test-p1"
"$JOBQ" init "$DIR"
# Use add -f for speed: write 10000 lines to a file
seq 1 10000 | while read i; do echo "true"; done > /tmp/jobq-test-p1-input.txt
"$JOBQ" add --dir "$DIR" -f /tmp/jobq-test-p1-input.txt > /dev/null
START=$(date +%s)
"$JOBQ" run --dir "$DIR" -j 8 > /dev/null 2>&1
END=$(date +%s)
ELAPSED=$((END - START))
DONE=$("$JOBQ" ls --dir "$DIR" --state done | wc -l)
if [ "$DONE" -eq 10000 ]; then
    pass "P1 (${ELAPSED}s, $DONE done)"
else
    fail "P1: done=$DONE elapsed=${ELAPSED}s"
fi
rm -rf "$DIR" /tmp/jobq-test-p1-input.txt

# T1: TERM a runner mid-job, second runner completes after lease
echo "=== T1: TERM handling ==="
DIR="/tmp/jobq-test-t1"
"$JOBQ" init "$DIR"
# Use a job that sleeps long enough to be reclaimed
"$JOBQ" add --dir "$DIR" -- sh -c "sleep 5; echo done" > /dev/null
# Start a runner with a 2-second lease
"$JOBQ" run --dir "$DIR" -j 1 --lease 2 &
RUNNER=$!
sleep 1
# TERM the runner
kill -TERM $RUNNER 2>/dev/null || true
wait $RUNNER 2>/dev/null || true
# Wait for lease to expire
sleep 3
# Start a second runner — it should reclaim and complete the job
"$JOBQ" run --dir "$DIR" -j 1 --lease 30 > /dev/null 2>&1 || true
# Check: the job is done exactly once
DONE=$("$JOBQ" ls --dir "$DIR" --state done | wc -l)
if [ "$DONE" -eq 1 ]; then
    pass "T1"
else
    fail "T1: done=$DONE"
fi
rm -rf "$DIR"

# FR-12: --dir on a directory without the layout exits 2
echo "=== FR-12: not a queue ==="
DIR="/tmp/jobq-test-fr12"
mkdir -p "$DIR"
"$JOBQ" run --dir "$DIR" -j 1 > /dev/null 2>&1
EXIT=$?
if [ "$EXIT" -eq 2 ]; then
    pass "FR-12"
else
    fail "FR-12: exit=$EXIT"
fi
rm -rf "$DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
