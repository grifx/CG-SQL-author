#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

failed() {
	echo '--------------------------------- FAILED'
	make_clean_msg
	exit 1
}

make_clean_msg() {
	echo "To clean artifacts: make clean"
}

colordiff() {
	diff --color "$@"
	return $?
}

# Notes:
#  * we need the line numbers in the main output so that we can use the test
#    tools to see which output came from what input. However this causes silly
#    and voluminous diffs in source control so the reference output has the line
#    numbers stripped.  When comparing against the reference output we replace
#    the line numbers with XXXX.
#
#  * We also remove the generated signed source lines from the output because
#    they may cause the source control system to think the file was
#    auto-generated and therefore not diff it and so forth. Note that the
#    regular expression avoids matching the auto-generated signed source pattern
#    so that this file does not look like it was auto-generated.
normalize_lines() {
	sed -e "s/The statement ending at line .*/The statement ending at line XXXX/" \
		-e "/g.nerated S.gnedSource<<.*>>/d" \
		-e "s/.sql.* error:/.sql:XXXX:1: error:/" <"$1" >"$1.tmp"
	cp "$1.tmp" "$1"
	rm "$1.tmp"
}

__on_diff_exit() {
	normalize_lines "$1"
	normalize_lines "$2"
	if ! colordiff "$1" "$2"; then
		# --non-interactive forces interactive mode off. If the environment is
		# not actually interactive (connected to a terminal for both output and
		# input), interactive mode is also disabled.
		if [ "${NON_INTERACTIVE:-0}" == 1 ] || [ ! -t 0 ] || [ ! -t 1 ]; then
			echo "When running: diff $*"
			echo "The above differences were detected. If these are expected copy the test output to the reference."
			echo "You can also re-run the tests without specifying --non_interactive to affirm the updates."
			echo "Don't just accept the changes to make the error go away; you have to really understand the diff first!"
			echo " "
			failed
		else
			read -rp "When running: diff $*
The above differences were detected. Is this expected?
Don't just accept to make the error go away; you have to really understand the diff first! (y/N) " ANS
			case $ANS in
			[Yy]*) cp "$2" "$1" 2>/dev/null ;;
			*)
				echo " "
				failed
				;;
			esac
		fi
	fi
}

on_diff_exit() {
	__on_diff_exit "${T:-}/$1.ref" "${O:-}/$1"
}
