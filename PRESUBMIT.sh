#! /usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
cd "${SCRIPT_DIR}"

ERREXIT=0
FIX=0
IGNORE_DIRTY=0
JOBS=$(nproc)
VERBOSE=0

function usage() {
    echo "usage: PRESUBMIT.sh [-e] [-f] [-h] [-i] [-j JOBS] [-v [VERBOSE]]"
    echo ""
    echo "Runs various static analysis tools"
    echo ""
    echo "optional arguments:"
    echo "-h, --help         show this help message and exit"
    echo "-e, --errexit      exit immediately on error"
    echo "-i, --ignore-dirty apply fixes even when checkout is dirty"
    echo "-f, --fix          attempt to fix detected errors"
    echo "-j, --jobs N       allow N jobs at once; default nproc jobs"
    echo "-v, --verbose [N]  N=0 (default without arg): only show errors"
    echo "                   N=1 (default): do not suppress info-level messages"
    echo "                   N=2: show verbose output"
}

getopt --test
if [ $? != 4 ]; then
    >&2 echo "Enahnced version of getopt is required"
    exit 1
fi
OPTIONS=efhij:v::
LONGOPTS=errexit,fix,help,ignore-dirty,jobs:,verbose::
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [ $? != 0 ]; then
    exit 1
fi
eval set -- "$PARSED"
while true; do
    case "$1" in
        -e|--errexit)
            ERREXIT=1
            shift
            ;;
        -f|--fix)
            FIX=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -i|--ignore-dirty)
            IGNORE_DIRTY=1
            shift
            ;;
        -j|--jobs)
            JOBS="$2"
            shift 2
            ;;
        -v|--verbose)
            if [ -z "$2" ]; then
                VERBOSE=1
            elif [ "$2" -ne 0 ] && [ "$2" -ne 1 ] && [ "$2" -ne 2 ]; then
                >&2 echo "Valid levels of verbosity are 0, 1, and 2"
                exit 1
            else
                VERBOSE="$2"
            fi
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            >&2 echo "Unhandled argument"
            exit 1
            ;;
    esac
done
if [[ $# -ne 0 ]]; then
    >&2 echo Unexpected arguments: $@
    exit 1
fi

if [ ${IGNORE_DIRTY} = 0 ] && [ ${FIX} = 1 ] && \
       ! git diff-index --quiet HEAD -- ; then
    >&2 echo "Commit changes before running automatic fixes."
    >&2 echo "Rerun with -i/--ignore-dirty to skip this check."
    exit 1
fi

function join_by {
    local IFS="$1"
    shift
    echo "$*"
}

function hide_output() {
    if [[ $VERBOSE -ge 1 ]]; then
        "$@"
    else
        "$@" > /dev/null
    fi
    return $?
}

function filter_impl() {
    FD=$1
    shift
    if [[ $VERBOSE -ge 1 ]]; then
	shift
        "$@"
        return $?
    else
        REGEX="$1"
        shift
        if [[ ${FD} -eq 1 ]]; then
            "$@" | grep -ve "${REGEX}"
        elif [[ ${FD} -eq 2 ]]; then
            "$@" 2>&1 | grep -ve "${REGEX}"
        else
            >&2 echo "Bad FD"
            exit 1
        fi
        return ${PIPESTATUS[0]}
    fi
}

function filter() {
    filter_impl 1 "$@"
}

function filter2() {
    filter_impl 2 "$@"
}

EXITCODE=0
function set_exit() {
    "$@"
    local PROC_EXITCODE=$?
    if [[ ${PROC_EXITCODE} -ne 0 ]]; then
        if [[ ${ERREXIT} -eq 1 ]] || [[ ${VERBOSE} -gt 0 ]]; then
            >&2 echo "Command failed: $@"
        fi
        if [[ ${ERREXIT} -eq 1 ]]; then
            >&2 echo "exiting with ${PROC_EXITCODE}"
            exit ${PROC_EXITCODE}
        fi
        if [[ ${EXITCODE} -eq 0 ]]; then
            EXITCODE=${PROC_EXITCODE}
        fi
    fi
}

function exit_on_failure() {
    "$@"
    local PROC_EXITCODE=$?
    if [[ ${PROC_EXITCODE} -ne 0 ]]; then
        >&2 echo "Command failed: $@"
        exit ${PROC_EXITCODE}
    fi
}

# Run tools that shuffle code around the most before other tools so that line
# number context will be meaningful.
if [ ${FIX} = 1 ]; then
    set_exit \
        filter2 "SKIP .*; detected existing license" \
        copyright-header \
        --license LGPL3 \
        --copyright-software dbus-trace \
        --copyright-software-description \
        "Display communication between DBus clients and the DBus daemon" \
        --copyright-holder "Thomas Anderson <tomKPZ@gmail.com>" \
        --copyright-year 2019 \
        -w 80 \
        -o . \
        -a src

    if [[ $VERBOSE -gt 1 ]]; then
        CLANG_FORMAT_VERBOSE=--verbose
    else
        CLANG_FORMAT_VERBOSE=
    fi
    set_exit \
        parallel \
        -j ${JOBS} \
        clang-format \
        ${CLANG_FORMAT_VERBOSE} \
        -i \
        ::: src/*

    set_exit \
        cmake-format \
        -i \
        CMakeLists.txt
else
    function check_formatted() {
        clang-format \
            -output-replacements-xml \
            "$1" \
            | grep -c "<replacement " > /dev/null
        RETCODE=${PIPESTATUS[1]}
        if [[ ${RETCODE} -eq 0 ]]; then
            >&2 echo "$1 is not properly formatted"
            return 1
        else
            return 0
        fi
    }
    export -f check_formatted
    set_exit \
        parallel \
        -j ${JOBS} \
        check_formatted \
        ::: src/*
fi

if [[ $VERBOSE -gt 1 ]]; then
    CMAKE_VERBOSE=--log-level=VERBOSE
else
    CMAKE_VERBOSE=
fi
rm -f CMakeCache.txt
exit_on_failure \
    hide_output \
    cmake \
    ${CMAKE_VERBOSE} \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=On \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    .

if [[ $VERBOSE -gt 1 ]]; then
    MAKE_VERBOSE="VERBOSE=1"
else
    MAKE_VERBOSE=
fi
exit_on_failure \
    hide_output \
    make \
    ${MAKE_VERBOSE} \
    -j ${JOBS}

IWYU_TOOL_ARGS=(
    "-j ${JOBS}"
    "-p ."
    "--"
    "-Xiwyu --mapping_file=iwyu.imp"
)
if [[ $VERBOSE -gt 1 ]]; then
    IWYU_VERBOSE=-v
else
    IWYU_VERBOSE=
fi
if [ ${FIX} = 1 ]; then
    function fix_includes() {
        iwyu-tool \
            ${IWYU_TOOL_ARGS[@]} \
            ${IWYU_VERBOSE} \
            -Xiwyu --verbose=1 \
            | iwyu-fix-includes
        return ${PIPESTATUS[1]}
    }
    filter "iwyu reports no contentful changes" \
           filter "IWYU edited 0 files on your behalf." \
           filter "^$" \
           fix_includes
else
    set_exit \
        filter "has correct #includes/fwd-decls" \
        filter "^$" \
        iwyu-tool \
        ${IWYU_TOOL_ARGS[@]} \
        ${IWYU_VERBOSE}
fi

if [ ${FIX} = 1 ]; then
    CLANG_TIDY_FIX=-fix
else
    CLANG_TIDY_FIX=
fi
if [[ ${VERBOSE} -ge 1 ]]; then
    CLANG_TIDY_VERBOSE=
else
    CLANG_TIDY_VERBOSE=-quiet
fi
set_exit \
    filter "clang-apply-replacements version" \
    filter "^clang-tidy.*-p=" \
    filter "Applying fixes ..." \
    filter2 "warnings generated." \
    /usr/share/clang/run-clang-tidy.py \
    ${CLANG_TIDY_FIX} \
    ${CLANG_TIDY_VERBOSE} \
    -j ${JOBS} \
    src

CPPCHECK_FILTER=(
    # TODO(tomKPZ): Enable this.
    "--suppress=unusedFunction"

    # TODO(tomKPZ): Enable this?
    "--suppress=missingIncludeSystem"
)
if [[ $VERBOSE -gt 1 ]]; then
    CPPCHECK_VERBOSE=-v
else
    CPPCHECK_VERBOSE=
fi
# Don't use -j ${JOBS} because that would disable unusedFunction checking.
set_exit \
    hide_output \
    cppcheck \
    ${CPPCHECK_VERBOSE} \
    --inconclusive \
    --enable=all \
    ${CPPCHECK_FILTER[@]} \
    --force \
    src

CPPLINT_FILTER=(
    # This project uses "#pragma once".
    "-build/include"
    "-build/header_guard"

    # We don't implement DCHECK_GT(), etc.
    "-readability/check"

    # We want to use <thread>, <mutex>, etc.
    "-build/c++11"

    # False positive.  And we use clang-format anyway.
    "-whitespace/parens"
)
if [[ $VERBOSE -gt 1 ]]; then
    CPPLINT_VERBOSE=$VERBOSE
else
    CPPLINT_VERBOSE=--quiet
fi
set_exit \
    parallel \
    -j ${JOBS} \
    cpplint \
    --filter="$(join_by , ${CPPLINT_FILTER[@]})" \
    ${CPPLINT_VERBOSE} \
    ::: src/*

if [[ $EXITCODE -ne 0 ]]; then
    >&2 echo "Checks failed."
    if [[ $FIX -eq 0 ]]; then
        >&2 echo "Rerun with -f/--fix to attempt automatic fixes."
    fi
    if [[ $VERBOSE -eq 0 ]]; then
        >&2 echo "Rerun with -v/--verbose or -v2/--verbose=2 for verbose output"
    fi
fi
exit $EXITCODE
