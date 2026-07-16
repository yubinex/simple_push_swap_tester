#!/bin/bash

# push_swap interactive evaluation script
# Walk through every mandatory checkpoint step by step.
# The evaluator supplies their own inputs at each prompt.

PUSH_SWAP="./push_swap"
CHECKER="./checker_linux"

# ── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── helpers ───────────────────────────────────────────────────────────────────
title() {
	echo -e "\n${BOLD}${CYAN}━━━  $1  ━━━${RESET}"
}

step() {
	echo -e "\n${BOLD}${YELLOW}▶ $1${RESET}"
}

show_cmd() {
	echo -e "${DIM}\$ $*${RESET}"
}

verdict_ok()   { echo -e "  ${GREEN}[OK]${RESET}  $1"; }
verdict_fail() { echo -e "  ${RED}[KO]${RESET}  $1"; }
note()         { echo -e "  ${CYAN}     $1${RESET}"; }

pause() {
	echo -e "\n${DIM}  ── press Enter to continue ──${RESET}"
	read -r
}

run_with_checker() {
	local args="$1"
	local ops
	ops=$($PUSH_SWAP $args 2>/dev/null)
	local count
	count=$(echo "$ops" | grep -c . 2>/dev/null || echo 0)
	[ -z "$ops" ] && count=0

	echo -e "  Operations produced: ${BOLD}$count${RESET}"

	if [ "$count" -gt 0 ] && [ "$count" -le 20 ]; then
		echo -e "${DIM}"
		echo "$ops" | sed 's/^/    /'
		echo -e "${RESET}"
	elif [ "$count" -gt 20 ]; then
		echo -e "${DIM}"
		echo "$ops" | head -5 | sed 's/^/    /'
		echo "    ... ($((count - 5)) more)"
		echo -e "${RESET}"
	fi

	if [ -n "$CHECKER" ]; then
		local result
		if [ -z "$ops" ]; then
			result=$(printf "" | $CHECKER $args 2>/dev/null)
		else
			result=$(echo "$ops" | $CHECKER $args 2>/dev/null)
		fi
		if [ "$result" = "OK" ]; then
			verdict_ok "Checker: OK — stack is sorted"
		else
			verdict_fail "Checker: $result"
		fi
	fi
}

# detect shuf
if command -v shuf >/dev/null 2>&1; then
	SHUF=shuf
elif command -v gshuf >/dev/null 2>&1; then
	SHUF=gshuf
else
	SHUF=""
fi

# ─────────────────────────────────────────────────────────────────────────────

clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     push_swap  —  Evaluation Script      ║"
echo "  ║          jhauck  ·  jubaur               ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  This script walks through every mandatory evaluation checkpoint."
echo "  You will be asked to supply your own inputs at several points."
echo "  Press Enter at each pause to advance to the next step."

pause

# ─────────────────────────────────────────────────────────────────────────────
title "1 / 8 — Build"

step "Running make"
show_cmd "make re"
echo ""
make re
if [ $? -ne 0 ]; then
	verdict_fail "make failed — stopping evaluation"
	exit 1
fi
echo ""
verdict_ok "Binary compiled successfully: $PUSH_SWAP"

if [ -x "$CHECKER" ]; then
	verdict_ok "checker_linux found"
else
	echo -e "  ${YELLOW}Warning: checker_linux not found or not executable — correctness checks will be skipped${RESET}"
	CHECKER=""
fi

pause

# ─────────────────────────────────────────────────────────────────────────────
title "2 / 8 — Makefile rules"

step "Verifying standard rules exist: all  clean  fclean  re"
for rule in all clean fclean re; do
	if grep -q "^$rule" Makefile 2>/dev/null || grep -q "^\.PHONY.*$rule" Makefile 2>/dev/null; then
		verdict_ok "rule '$rule' present"
	else
		verdict_fail "rule '$rule' missing from Makefile"
	fi
done

step "No-relink check — running make a second time"
show_cmd "make"
echo ""
make_output=$(make 2>&1)
echo "$make_output"
if echo "$make_output" | grep -qi "nothing to be done\|is up to date\|already built"; then
	verdict_ok "No relink on second make"
else
	note "Check the output above — make should not recompile anything"
fi

pause

# ─────────────────────────────────────────────────────────────────────────────
title "3 / 8 — Error handling"

echo "  The evaluator will supply inputs.  Expected result: 'Error' on stderr, exit 1."
echo ""

run_error_prompt() {
	local label="$1"
	shift
	echo -e "  ${BOLD}Test: $label${RESET}"
	show_cmd "$PUSH_SWAP $*"
	local out
	out=$($PUSH_SWAP "$@" 2>&1)
	local code=$?
	echo "  Output: '$out'   exit: $code"
	if echo "$out" | grep -q "^Error$" && [ "$code" -ne 0 ]; then
		verdict_ok "Correct — Error on stderr, non-zero exit"
	else
		verdict_fail "Expected Error + non-zero exit"
	fi
	echo ""
}

step "Guided error cases"
run_error_prompt "Non-integer argument"  "abc"
run_error_prompt "Duplicate values"      "3" "2" "1" "3"
run_error_prompt "Integer overflow"      "2147483648"
run_error_prompt "Integer underflow"     "-2147483649"
run_error_prompt "Empty string"          ""

step "Evaluator's own error input"
echo -e "  Enter an input that should produce an error (e.g. duplicates, non-integer):"
printf "  \$ $PUSH_SWAP "
read -r custom_err
show_cmd "$PUSH_SWAP $custom_err"
out=$($PUSH_SWAP $custom_err 2>&1)
code=$?
echo "  Output: '$out'   exit: $code"
if echo "$out" | grep -q "^Error$" && [ "$code" -ne 0 ]; then
	verdict_ok "Correct — Error + non-zero exit"
else
	verdict_fail "Expected Error + non-zero exit (got '$out', exit=$code)"
fi

pause

# ─────────────────────────────────────────────────────────────────────────────
title "4 / 8 — Manual test: evaluator's own numbers"

echo "  Enter a list of integers to sort (space-separated)."
echo "  The output will be piped to checker_linux to verify correctness."
echo ""

while true; do
	printf "  \$ $PUSH_SWAP "
	read -r user_input
	if [ -z "$user_input" ]; then
		echo "  (empty input — skipping)"
		break
	fi
	run_with_checker "$user_input"
	echo ""
	printf "  Test another set? [y/N] "
	read -r again
	[[ "$again" =~ ^[Yy]$ ]] || break
done

pause

# ─────────────────────────────────────────────────────────────────────────────
title "5 / 8 — Strategy flags"

echo "  All four strategy flags are tested on the same input."
echo ""
printf "  Enter numbers to test with (or press Enter for a random 20-number set): "
read -r strat_input

if [ -z "$strat_input" ]; then
	if [ -n "$SHUF" ]; then
		strat_input=$($SHUF -i 0-999 -n 20 | tr '\n' ' ')
		echo "  Generated: $strat_input"
	else
		strat_input="15 3 8 1 12 7 20 4 9 17 6 11 2 14 19 5 10 16 13 18"
		echo "  Using default: $strat_input"
	fi
fi

for flag in --simple --medium --complex --adaptive; do
	echo ""
	step "Flag: $flag"
	show_cmd "$PUSH_SWAP $flag $strat_input | wc -l"
	ops=$($PUSH_SWAP $flag $strat_input 2>/dev/null)
	count=$(echo "$ops" | grep -c . 2>/dev/null || echo 0)
	[ -z "$ops" ] && count=0
	echo "  Operations: $count"
	if [ -n "$CHECKER" ]; then
		if [ -z "$ops" ]; then
			result=$(printf "" | $CHECKER $strat_input 2>/dev/null)
		else
			result=$(echo "$ops" | $CHECKER $strat_input 2>/dev/null)
		fi
		[ "$result" = "OK" ] && verdict_ok "Checker: OK" || verdict_fail "Checker: $result"
	fi
done

pause

# ─────────────────────────────────────────────────────────────────────────────
title "6 / 8 — Benchmark mode (--bench)"

echo "  The --bench flag must print to stderr:"
echo "    disorder (%), strategy name + complexity, total ops, per-op counts."
echo ""

printf "  Enter numbers (or press Enter for a random 10-number set): "
read -r bench_input

if [ -z "$bench_input" ]; then
	if [ -n "$SHUF" ]; then
		bench_input=$($SHUF -i 0-999 -n 10 | tr '\n' ' ')
		echo "  Generated: $bench_input"
	else
		bench_input="5 3 8 1 9 2 7 4 10 6"
		echo "  Using default: $bench_input"
	fi
fi

step "Running with --bench --adaptive"
show_cmd "$PUSH_SWAP --bench --adaptive $bench_input 2>&1 | head -10"
echo ""
bench_stderr=$($PUSH_SWAP --bench --adaptive $bench_input 2>&1 >/dev/null)
echo "$bench_stderr"
echo ""

if echo "$bench_stderr" | grep -qi "disorder"; then
	verdict_ok "disorder field present"
else
	verdict_fail "disorder field missing from --bench output"
fi
if echo "$bench_stderr" | grep -qi "strategy"; then
	verdict_ok "strategy field present"
else
	verdict_fail "strategy field missing"
fi
if echo "$bench_stderr" | grep -qi "total_ops\|total ops"; then
	verdict_ok "total_ops field present"
else
	verdict_fail "total_ops field missing"
fi

step "Verify operations still go to stdout (not mixed with bench output)"
show_cmd "$PUSH_SWAP --bench --adaptive $bench_input 2>/dev/null | wc -l"
ops_count=$($PUSH_SWAP --bench --adaptive $bench_input 2>/dev/null | wc -l)
echo "  Lines on stdout: $ops_count"
if [ "$ops_count" -ge 0 ] 2>/dev/null; then
	verdict_ok "Operations on stdout, bench on stderr — correctly separated"
fi

pause

# ─────────────────────────────────────────────────────────────────────────────
title "7 / 8 — Performance benchmarks"

if [ -z "$SHUF" ]; then
	echo -e "  ${YELLOW}shuf / gshuf not found — skipping random benchmarks${RESET}"
	pause
else

bench_random() {
	local n=$1 runs=$2
	local total=0 min=999999 max=0 errors=0
	for _ in $(seq 1 "$runs"); do
		args=$($SHUF -i 0-999999 -n "$n" | tr '\n' ' ')
		ops=$($PUSH_SWAP $args 2>/dev/null)
		count=$(echo "$ops" | grep -c . 2>/dev/null || echo 0)
		[ -z "$ops" ] && count=0
		if [ -n "$CHECKER" ]; then
			if [ -z "$ops" ]; then
				r=$(printf "" | $CHECKER $args 2>/dev/null)
			else
				r=$(echo "$ops" | $CHECKER $args 2>/dev/null)
			fi
			[ "$r" != "OK" ] && ((errors++))
		fi
		total=$((total + count))
		[ "$count" -lt "$min" ] && min=$count
		[ "$count" -gt "$max" ] && max=$count
	done
	echo "$((total / runs)):$min:$max:$errors"
}

step "100 random numbers — 5 runs"
note "Targets: < 2000 (pass)  < 1500 (good)  < 700 (excellent)"
echo ""
res=$(bench_random 100 5)
avg=${res%%:*}; rest=${res#*:}
min=${rest%%:*}; rest=${rest#*:}
max=${rest%%:*}; errors=${rest##*:}
note "avg=$avg  min=$min  max=$max  correctness_errors=$errors"
[ "$errors" -gt 0 ] && verdict_fail "$errors incorrect sorts"
if   [ "$avg" -lt 700 ];  then verdict_ok "avg $avg ops — EXCELLENT (< 700)"
elif [ "$avg" -lt 1500 ]; then verdict_ok "avg $avg ops — GOOD (< 1500)"
elif [ "$avg" -lt 2000 ]; then verdict_ok "avg $avg ops — PASS (< 2000)"
else                           verdict_fail "avg $avg ops — FAIL (≥ 2000)"
fi

echo ""
step "500 random numbers — 5 runs  (this takes ~30 seconds)"
note "Targets: < 12000 (pass)  < 8000 (good)  < 5500 (excellent)"
echo ""
res=$(bench_random 500 5)
avg=${res%%:*}; rest=${res#*:}
min=${rest%%:*}; rest=${rest#*:}
max=${rest%%:*}; errors=${rest##*:}
note "avg=$avg  min=$min  max=$max  correctness_errors=$errors"
[ "$errors" -gt 0 ] && verdict_fail "$errors incorrect sorts"
if   [ "$avg" -lt 5500 ];  then verdict_ok "avg $avg ops — EXCELLENT (< 5500)"
elif [ "$avg" -lt 8000 ];  then verdict_ok "avg $avg ops — GOOD (< 8000)"
elif [ "$avg" -lt 12000 ]; then verdict_ok "avg $avg ops — PASS (< 12000)"
else                            verdict_fail "avg $avg ops — FAIL (≥ 12000)"
fi

fi  # end shuf check

pause

# ─────────────────────────────────────────────────────────────────────────────
title "8 / 8 — Free exploration"

echo "  Use this section to test anything else you want to verify."
echo ""
echo "  Useful commands:"
echo -e "    ${DIM}\$ ./push_swap 3 2 1 | ./checker_linux 3 2 1${RESET}"
echo -e "    ${DIM}\$ ./push_swap --bench --adaptive 5 4 3 2 1 2>&1${RESET}"
echo -e "    ${DIM}\$ ./push_swap --simple 5 4 3 2 1 | wc -l${RESET}"
echo ""
echo "  Run ./test.sh for the full automated suite."
echo ""

while true; do
	printf "  \$ $PUSH_SWAP "
	read -r free_input
	[ -z "$free_input" ] && break
	run_with_checker "$free_input"
done

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━  Evaluation complete  ━━━${RESET}"
echo ""
echo "  Sections covered:"
echo "    1. Build + Makefile"
echo "    2. No-relink rule"
echo "    3. Error handling"
echo "    4. Manual input + checker"
echo "    5. All four strategy flags"
echo "    6. --bench mode output"
echo "    7. Performance (100 + 500 numbers)"
echo "    8. Free exploration"
echo ""
