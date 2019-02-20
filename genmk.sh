#!/bin/bash

HAVE_TPUT="$(command -v tput || true)"

abend()
{
    MESSAGE="$*"
    exec 1>&2
    [ "$HAVE_TPUT" ] && tput setaf 1 && tput bold
    echo "$0: ${MESSAGE:-'unkown error'}"
    [ "$HAVE_TPUT" ] && tput sgr0

    [ "$OUTPUT" != '-stdout' ] && rm "$OUTPUT"
	
    exit 1
}

parse_build()
{
    TYPE="$1"
    shift

    case "${TYPE^^}" in

	BINARY)
	    TARGET="$1"
	    LINKFLAG=-x
	    ;;

	MODULE)
	    TARGET="$1.so"
	    LINKFLAG=-b
	    ;;

	*)
	    abend "unknown build target type: $TYPE"
	;;
    esac
    shift
    TYPE=${TYPE^^}

    [ "${1^^}" = USING ] || abend "expected USING, but got: $1"
    shift

    echo -n "\$(TARGETDIR)/$TARGET:"
    FIRSTOBJECT=""
    for SOURCE in "$@"; do
	OBJECT="\$(BUILDDIR)/${SOURCE%.*}.o"
	OBJECTS[$OBJECT]="$SOURCE"
	echo -n " $OBJECT"

	if [ -z "$FIRSTOBJECT" ]; then
	    FIRSTOBJECT="$OBJECT"
	fi
    done
    echo
    echo "	\$(COBC) $LINKFLAG \$(COBFLAGS) -o \$@ \$^"
    echo
    TARGETS[$TARGET]="$*"

    if [ "$TYPE" = BINARY ]; then
	# main program needs both -c and -x, otherwise <undefined reference to `main'>
	OBJECTFLAGS[$FIRSTOBJECT]="-x"
    fi
}

write_test()
{
    TEST="$1"
    shift

    echo "\$(TESTRUNDIR)/$TEST:"
    echo "	cp \$(SOURCEDIR)/$TEST \$(TESTRUNDIR)/SRCPRG"
    for SOURCE in "$@"; do
	echo "	cp \$(TESTDIR)/$SOURCE \$(TESTRUNDIR)/UTESTS"
	echo "	cd \$(TESTRUNDIR) && \$(ZUTZCPC)"
	echo "	\$(COBC) -x \$(COBFLAGS) -I \$(CUTCOPY) -o \$(TESTRUNDIR)/unittest \$(TESTRUNDIR)/TESTPRG"
	[ "$HAVE_TPUT" ] && echo '	@tput bold;tput setaf 3'
	echo "	cd \$(TESTRUNDIR) && ./unittest"
	[ "$HAVE_TPUT" ] && echo '	@tput sgr0'
    done
    echo

    TESTS[$TEST]="$*"
}

write_test_with_driver()
{
    TEST="$1"
    DRIVER="$2"
    shift 2

    echo "\$(TESTRUNDIR)/$TEST:"
    echo "	\$(COBC) -x \$(COBFLAGS) -o \$(TESTRUNDIR)/driver \$(TESTDIR)/$DRIVER"
    echo "	cp \$(SOURCEDIR)/$TEST \$(TESTRUNDIR)/SRCPRG"
    for SOURCE in "$@"; do
	MODULE="${TEST%.*}.so"
	echo "	cp \$(TESTDIR)/$SOURCE \$(TESTRUNDIR)/UTESTS"
	echo "	cd \$(TESTRUNDIR) && \$(ZUTZCPC)"
	echo "	\$(COBC) -b \$(COBFLAGS) -I \$(CUTCOPY) -o \$(TESTRUNDIR)/$MODULE \$(TESTRUNDIR)/TESTPRG"
	[ "$HAVE_TPUT" ] && echo '	@tput bold;tput setaf 3'
	echo "	cd \$(TESTRUNDIR) && ./driver"
	[ "$HAVE_TPUT" ] && echo '	@tput sgr0'
    done
    echo

    TESTS[$TEST]="$*"
}

parse_test()
{
    [ "${1^^}" = SOURCE ] || abend "unknown test target type: $1"
    shift

    SOURCE="$1"
    shift

    if [ "${1^^}" = WITH ] && [ "${2^^}" = DRIVER ]; then
	DRIVER="$3"
	shift 3
    else
	DRIVER=
    fi

    [ "$1" = USING ] || abend "expected USING, but got: $2"
    shift

    if [ $DRIVER ]; then
	write_test_with_driver "$SOURCE" "$DRIVER" "$@"
    else
	write_test "$SOURCE" "$@"
    fi
}

###########

trap abend ERR
set -e

if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    abend 'need at least bash v4 for associative arrays'
fi

OUTPUT="$1"
if [ "$OUTPUT" ]; then
    exec > "$OUTPUT"
else
    OUTPUT="-stdout"
fi

echo ".PHONY: build test prepare-test"
echo

declare -A TARGETS OBJECTS OBJECTFLAGS TESTS

while IFS= read -r LINE; do

    # remove comments
    LINE="${LINE%%#*}"

    # skip empty lines
    [[ $LINE =~ ^[[:space:]]*$ ]] && continue

    set -- $LINE

    VERB="$1"
    shift
    
    case "${VERB^^}" in

	BUILD|build)
	    parse_build "$@"
	    ;;

	TEST|test)
	    parse_test "$@"
	    ;;
	
	*)
	    abend "unknown verb: $VERB"
	;;
    esac
    
done

for OBJECT in ${!OBJECTS[*]}; do
    SOURCE="${OBJECTS[$OBJECT]}"
    EXTRAFLAGS="${OBJECTFLAGS[$OBJECT]}"
    echo "$OBJECT: \$(SOURCEDIR)/$SOURCE"
    echo "	\$(COBC) -c $EXTRAFLAGS \$(COBFLAGS) -o \$@ \$<"
    echo
done

echo -n "build:"
for TARGET in ${!TARGETS[*]}; do
    echo -n " \$(TARGETDIR)/$TARGET"
done
echo
echo

echo -n "test: prepare-test"
for TEST in ${!TESTS[*]}; do
    echo -n " \$(TESTRUNDIR)/$TEST"
done
echo
echo

echo 'prepare-test:'
echo '	echo ZUTZCWS > $(TESTRUNDIR)/UTSTCFG'