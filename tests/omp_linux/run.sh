#!/bin/sh
# Runs smoke.pwn on an open.mp Linux server with jit.so as a legacy plugin.
# Needs 32-bit libc, libstdc++ and libatomic: run.sh <jit.so> <pawnc dir> <server dir> [pawncc flags...]
# Exits non-zero if the JIT reported anything or the script didn't pass.
jit=$(realpath "$1") pawnc=$(realpath "$2") srv=$(realpath "$3")
shift 3
here=$(dirname "$(realpath "$0")")

mkdir -p "$srv/gamemodes" "$srv/plugins"
LD_LIBRARY_PATH="$pawnc/lib" "$pawnc/bin/pawncc" "$here/smoke.pwn" \
  -o"$srv/gamemodes/smoke.amx" "$@" || exit 2
cp "$jit" "$srv/plugins/jit.so"
cat > "$srv/config.json" <<EOF
{
  "announce": false,
  "enable_query": false,
  "artwork": {"enable": false},
  "logging": {"use_prefix": false, "use_timestamp": false},
  "network": {"port": 7797},
  "pawn": {"main_scripts": ["smoke 1"], "side_scripts": [], "legacy_plugins": ["jit"]}
}
EOF
printf 'jit_log 1\n' > "$srv/server.cfg"

cd "$srv" || exit 2
if command -v gdb >/dev/null; then
  # On a crash: backtrace, faulting instruction and registers.
  timeout 60 gdb -q -batch -ex run -ex bt -ex 'x/4i $pc' -ex 'info registers' \
    --args ./omp-server > out.txt 2>&1
else
  timeout 20 ./omp-server > out.txt 2>&1
fi
cat out.txt
if grep -q '\[jit\]' out.txt || ! grep -q 'JIT smoke OK' out.txt; then
  echo "--- jit.log tail"
  tail -5 plugins/jit.log 2>/dev/null
  echo "--- disassembly"
  LD_LIBRARY_PATH="$pawnc/lib" "$pawnc/bin/pawndisasm" gamemodes/smoke.amx
  head -40 gamemodes/smoke.lst 2>/dev/null
  exit 1
fi
