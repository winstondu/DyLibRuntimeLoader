#!/usr/bin/env bash
# End-to-end adversarial harness for the lazy-load logger.
# Must run from a checkout whose directory is named Dynasty (SwiftPM
# derives the root package identity from it).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
EX="$ROOT/Examples"
DIST="$HERE/.dist"
fail=0
pass() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; }

build() { swift build --package-path "$1" -c debug >/dev/null 2>"$DIST.err" || { cat "$DIST.err"; echo "build failed: $1"; exit 2; }; }
bin() { swift build --package-path "$1" -c debug --show-bin-path; }

for p in "$EX/AnimalInterface" "$EX/TrickInterface" "$EX/CatPlugin" "$EX/BackflipPlugin" "$HERE/LoggedDogPlugin" "$HERE/LoggerHost"; do
    build "$p"
done

rm -rf "$DIST"; mkdir -p "$DIST/Frameworks"
cp "$(bin "$HERE/LoggerHost")/LoggerHost" "$DIST/"
cp "$(bin "$HERE/LoggerHost")/libDynasty.dylib" "$DIST/"
cp "$(bin "$EX/AnimalInterface")/libAnimalInterface.dylib" "$DIST/"
cp "$(bin "$EX/TrickInterface")/libTrickInterface.dylib" "$DIST/"
cp "$(bin "$EX/CatPlugin")/libCatPlugin.dylib" "$DIST/"
cp "$(bin "$EX/BackflipPlugin")/libBackflipPlugin.dylib" "$DIST/"
cp "$(bin "$HERE/LoggedDogPlugin")/libLoggedDogPlugin.dylib" "$DIST/"

fw() { mkdir -p "$DIST/Frameworks/$1.framework"; ln -s "../../$2" "$DIST/Frameworks/$1.framework/$1"; }
fw CatPlugin libCatPlugin.dylib
fw ConcPlugin libCatPlugin.dylib
fw ReentPlugin libCatPlugin.dylib
fw SilentPlugin libCatPlugin.dylib
fw BackflipPlugin libBackflipPlugin.dylib
fw LoggedDogPlugin libLoggedDogPlugin.dylib

echo "== in-process checks"
"$DIST/LoggerHost" checks 2>"$DIST/checks.err"; rc=$?
[ $rc -eq 0 ] && pass "in-process checks (exit 0)" || bad "in-process checks exit=$rc"
grep -c HOSTLOG "$DIST/checks.err" | sed 's/^/  HOSTLOG lines: /'

echo "== trap subprocess"
"$DIST/LoggerHost" trap >"$DIST/trap.out" 2>"$DIST/trap.err"; rc=$?
cat "$DIST/trap.err" | sed 's/^/  | /'
[ $rc -ne 0 ] && pass "trap: process died (exit=$rc)" || bad "trap: process exited 0"
grep -q "TRAP unreachable" "$DIST/trap.err" && bad "trap: proxy did not trap"
logline=$(grep -n "HOSTLOG didLoad .*MissingPlugin.*error=failedToOpen" "$DIST/trap.err" | head -1 | cut -d: -f1)
fatal=$(grep -n "failed to load" "$DIST/trap.err" | head -1 | cut -d: -f1)
if [ -n "$logline" ] && [ -n "$fatal" ] && [ "$logline" -lt "$fatal" ]; then
    pass "trap: failure event (line $logline) emitted before fatalError (line $fatal)"
else
    bad "trap: failure event not logged before trap (log=$logline fatal=$fatal)"
fi

echo "== plugin-to-plugin"
"$DIST/LoggerHost" dog >"$DIST/dog.out" 2>"$DIST/dog.err"; rc=$?
cat "$DIST/dog.out" "$DIST/dog.err" | sed 's/^/  | /'
[ $rc -eq 0 ] && pass "dog host checks" || bad "dog host checks exit=$rc"
n=$(grep -c "DOGLOG didLoad interface=Trick path=.*/BackflipPlugin.framework/BackflipPlugin duration=.* error=nil" "$DIST/dog.err")
[ "$n" = 1 ] && pass "plugin-to-plugin: Dog's own logger saw exactly one Trick load" || bad "plugin-to-plugin: DOGLOG Trick success lines=$n"
n=$(grep -c "DOGLOG willLoad interface=Trick" "$DIST/dog.err")
[ "$n" = 1 ] && pass "plugin-to-plugin: one Trick willLoad" || bad "plugin-to-plugin: Trick willLoad lines=$n"
grep -q "HOSTLOG.*BackflipPlugin" "$DIST/dog.err" && bad "plugin-to-plugin: host logger saw the plugin's connection"

echo "== compile-fail: non-conforming logger type"
if swift build --package-path "$HERE/CompileFail" >"$DIST/cf.out" 2>&1; then
    bad "compile-fail: logger: NotALogger.self compiled"
else
    grep -E "error:" "$DIST/cf.out" | grep -v "^error: fatalError" | head -3 | sed 's/^/  | /'
    if grep -qE "cannot convert value of type 'NotALogger.Type'" "$DIST/cf.out"; then
        pass "compile-fail: rejected with a type error"
    elif grep -q "Assertion failed" "$DIST/cf.out"; then
        # Swift 6.4 beta asserts in SILGen on any type error inside a @DyLibConnect
        # member expansion (dependencies: has the same crash at ad55dba).
        echo "WARN compile-fail: rejected, but by a compiler crash, not a diagnostic"
    else
        bad "compile-fail: failed for an unrelated reason"
    fi
fi

[ $fail -eq 0 ] && echo "HARNESS: ALL PASSED" || echo "HARNESS: FAILURES"
exit $fail
