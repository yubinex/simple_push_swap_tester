#!/bin/bash

# push_swap evaluation test script
# Tests: error handling, edge cases, correctness, and performance benchmarks

PUSH_SWAP="./push_swap"
CHECKER="./checker_linux"
PASS=0
FAIL=0

# ── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${RESET}  $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[KO]${RESET}  $1"; ((FAIL++)); }
info() { echo -e "  ${CYAN}     $1${RESET}"; }
section() { echo -e "\n${BOLD}${YELLOW}── $1 ──${RESET}"; }

# ── helpers ───────────────────────────────────────────────────────────────────

check_sorted() {
	local args="$1"
	local ops
	ops=$($PUSH_SWAP $args 2>/dev/null)
	local count
	count=$(echo "$ops" | grep -c . 2>/dev/null || echo 0)
	[ -z "$ops" ] && count=0
	local result
	if [ -z "$ops" ]; then
		result=$(printf "" | $CHECKER $args 2>/dev/null)
	else
		result=$(echo "$ops" | $CHECKER $args 2>/dev/null)
	fi
	echo "$count:$result"
}

# Run N random tests of a given size, report avg/min/max ops and any errors
bench() {
	local n=$1
	local runs=$2
	local total=0
	local min=999999
	local max=0
	local errors=0

	for _ in $(seq 1 "$runs"); do
		local args
		args=$(shuf -i 0-999999 -n "$n" | tr '\n' ' ')
		local ops
		ops=$($PUSH_SWAP $args 2>/dev/null)
		local result
		if [ -z "$ops" ]; then
			result=$(printf "" | $CHECKER $args 2>/dev/null)
		else
			result=$(echo "$ops" | $CHECKER $args 2>/dev/null)
		fi
		local count
		count=$(echo "$ops" | grep -c . 2>/dev/null || echo 0)
		[ -z "$ops" ] && count=0

		if [ "$result" != "OK" ]; then
			((errors++))
		fi
		total=$((total + count))
		[ "$count" -lt "$min" ] && min=$count
		[ "$count" -gt "$max" ] && max=$count
	done

	local avg=$((total / runs))
	echo "$avg:$min:$max:$errors"
}

# ── pre-flight ────────────────────────────────────────────────────────────────

section "Setup"

if [ ! -f "$PUSH_SWAP" ]; then
	echo -e "  ${YELLOW}Binary not found, running make...${RESET}"
	make > /dev/null 2>&1
fi

if [ ! -x "$PUSH_SWAP" ]; then
	echo -e "  ${RED}Could not build $PUSH_SWAP — aborting.${RESET}"
	exit 1
fi
echo -e "  ${GREEN}Binary ready: $PUSH_SWAP${RESET}"

if [ ! -x "$CHECKER" ]; then
	echo -e "  ${YELLOW}Warning: $CHECKER not found or not executable — correctness checks will be skipped.${RESET}"
	CHECKER=""
fi

# ── 1. error handling ────────────────────────────────────────────────────────

section "Error handling"

run_error_test() {
	local label="$1"
	shift
	local output
	output=$($PUSH_SWAP "$@" 2>&1)
	local exit_code=$?
	if echo "$output" | grep -q "^Error$" && [ "$exit_code" -ne 0 ]; then
		ok "$label"
	else
		fail "$label  (got: '$(echo "$output" | head -1)', exit=$exit_code)"
	fi
}

run_error_test "Non-integer argument"        "abc"
run_error_test "Mixed valid/invalid"         "1" "2" "abc"
run_error_test "Float"                       "1.5"
run_error_test "Duplicate values"            "1" "2" "3" "2"
run_error_test "INT_MAX + 1 overflow"        "2147483648"
run_error_test "INT_MIN - 1 underflow"       "-2147483649"
run_error_test "20-digit number (long overflow)" "18446744073709551616"
run_error_test "Empty string argument"       ""
run_error_test "Plus-prefixed non-integer"   "+abc"

# ── 2. edge / trivial cases ───────────────────────────────────────────────────

section "Edge cases"

# No arguments — no output, exit 0
output=$($PUSH_SWAP 2>/dev/null)
exit_code=$?
if [ -z "$output" ] && [ "$exit_code" -eq 0 ]; then
	ok "No arguments → no output, exit 0"
else
	fail "No arguments (got: '$output', exit=$exit_code)"
fi

# Single element
output=$($PUSH_SWAP 42 2>/dev/null)
if [ -z "$output" ]; then
	ok "Single element → no operations"
else
	fail "Single element produced output: $output"
fi

# Already sorted — 2 elements
output=$($PUSH_SWAP 1 2 2>/dev/null)
if [ -z "$output" ]; then
	ok "Already sorted (1 2) → no operations"
else
	fail "Already sorted (1 2) produced: $output"
fi

# Already sorted — 5 elements
output=$($PUSH_SWAP 1 2 3 4 5 2>/dev/null)
if [ -z "$output" ]; then
	ok "Already sorted (1 2 3 4 5) → no operations"
else
	fail "Already sorted (1 2 3 4 5) produced: $output"
fi

# Negative numbers
if [ -n "$CHECKER" ]; then
	args="-1 -5 0 -3 2"
	res=$(check_sorted "$args")
	count=${res%%:*}; verdict=${res##*:}
	if [ "$verdict" = "OK" ]; then
		ok "Negative numbers sorted correctly ($count ops)"
	else
		fail "Negative numbers: checker said $verdict"
	fi
fi

# ── 3. tiny inputs (≤ 5 elements) ────────────────────────────────────────────

section "Tiny inputs (≤ 5 elements)"

tiny_test() {
	local label="$1"
	local max_ops="$2"
	shift 2
	local args="$*"

	if [ -n "$CHECKER" ]; then
		local res
		res=$(check_sorted "$args")
		local count=${res%%:*}
		local verdict=${res##*:}
		if [ "$verdict" != "OK" ]; then
			fail "$label: checker said $verdict"
			return
		fi
		if [ "$count" -le "$max_ops" ]; then
			ok "$label: correct, $count ops (≤ $max_ops)"
		else
			fail "$label: correct but $count ops > $max_ops limit"
		fi
	else
		local ops
		ops=$($PUSH_SWAP $args 2>/dev/null)
		local count
		count=$(echo "$ops" | grep -c . 2>/dev/null || echo 0)
		[ -z "$ops" ] && count=0
		if [ "$count" -le "$max_ops" ]; then
			ok "$label: $count ops (≤ $max_ops) — no checker to verify correctness"
		else
			fail "$label: $count ops > $max_ops limit"
		fi
	fi
}

tiny_test "2 elements reversed"    1  2 1
tiny_test "3 elements (1)"         2  2 1 3
tiny_test "3 elements (2)"         3  3 2 1
tiny_test "4 elements (1)"         6  4 3 2 1
tiny_test "4 elements (2)"         6  2 4 1 3
tiny_test "4 elements (3)"         6  3 4 1 2
tiny_test "5 elements (1)"        12  5 4 3 2 1
tiny_test "5 elements (2)"        12  3 5 1 4 2
tiny_test "5 elements (3)"        12  4 2 5 1 3

# ── 4. correctness — random medium/large inputs ───────────────────────────────

section "Correctness — random inputs"

if [ -z "$CHECKER" ]; then
	echo -e "  ${YELLOW}Skipped (checker_linux not available)${RESET}"
else
	correctness_test() {
		local n=$1
		local runs=$2
		local label="$3"
		local errors=0
		for _ in $(seq 1 "$runs"); do
			local args
			args=$(shuf -i 0-99999 -n "$n" | tr '\n' ' ')
			local ops
			ops=$($PUSH_SWAP $args 2>/dev/null)
			local result
			result=$(echo "$ops" | $CHECKER $args 2>/dev/null)
			[ "$result" != "OK" ] && ((errors++))
		done
		if [ "$errors" -eq 0 ]; then
			ok "$label: all $runs runs correct"
		else
			fail "$label: $errors/$runs runs produced wrong result"
		fi
	}

	correctness_test 10  20 "10 numbers  (20 runs)"
	correctness_test 50  10 "50 numbers  (10 runs)"
	correctness_test 100  5 "100 numbers (5 runs)"
	correctness_test 500  3 "500 numbers (3 runs)"
fi

# ── 5. bench mode output ──────────────────────────────────────────────────────

section "Bench mode (--bench)"

bench_output=$($PUSH_SWAP --bench --adaptive 5 4 3 2 1 2>&1 >/dev/null)

for field in disorder strategy total_ops sa sb ss pa pb ra rb rr rra rrb rrr; do
	if echo "$bench_output" | grep -qi "$field"; then
		ok "--bench output contains '$field'"
	else
		fail "--bench output missing '$field'"
	fi
done

# ── 6. performance benchmarks ─────────────────────────────────────────────────

section "Performance benchmarks — 100 numbers (5 runs)"

if [ -z "$CHECKER" ]; then
	echo -e "  ${YELLOW}Skipped (checker_linux not available)${RESET}"
else
	res=$(bench 100 5)
	avg=${res%%:*}; rest=${res#*:}
	min=${rest%%:*}; rest=${rest#*:}
	max=${rest%%:*}; errors=${rest##*:}

	info "avg=$avg  min=$min  max=$max  errors=$errors"

	[ "$errors" -gt 0 ] && fail "Correctness errors detected in benchmark"

	if   [ "$avg" -lt 700 ];  then ok "Average $avg ops < 700  (excellent)"
	elif [ "$avg" -lt 1500 ]; then ok "Average $avg ops < 1500 (good)"
	elif [ "$avg" -lt 2000 ]; then ok "Average $avg ops < 2000 (pass)"
	else                           fail "Average $avg ops ≥ 2000 (below passing threshold)"
	fi
fi

section "Performance benchmarks — 500 numbers (5 runs)"

if [ -z "$CHECKER" ]; then
	echo -e "  ${YELLOW}Skipped (checker_linux not available)${RESET}"
else
	res=$(bench 500 5)
	avg=${res%%:*}; rest=${res#*:}
	min=${rest%%:*}; rest=${rest#*:}
	max=${rest%%:*}; errors=${rest##*:}

	info "avg=$avg  min=$min  max=$max  errors=$errors"

	[ "$errors" -gt 0 ] && fail "Correctness errors detected in benchmark"

	if   [ "$avg" -lt 5500 ];  then ok "Average $avg ops < 5500  (excellent)"
	elif [ "$avg" -lt 8000 ];  then ok "Average $avg ops < 8000  (good)"
	elif [ "$avg" -lt 12000 ]; then ok "Average $avg ops < 12000 (pass)"
	else                            fail "Average $avg ops ≥ 12000 (below passing threshold)"
	fi
fi

# ── 6. summary ────────────────────────────────────────────────────────────────

section "Summary"
total=$((PASS + FAIL))
echo -e "  ${BOLD}Passed: ${GREEN}$PASS${RESET}${BOLD} / $total${RESET}"
if [ "$FAIL" -gt 0 ]; then
	echo -e "  ${BOLD}Failed: ${RED}$FAIL${RESET}${BOLD} / $total${RESET}"
	exit 1
fi
exit 0
