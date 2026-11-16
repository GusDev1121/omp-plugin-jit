#!/bin/sh
# Runs benchmarks/omp_cpu.pwn on an open.mp Linux server, alternating without
# and with jit.so (legacy plugin), the same way docs/benchmark-openmp.md did.
# Usage: bench.sh <jit.so> <pawnc dir> <server dir> [runs]
# Prints "<nojit|jit> <run> <test>: <ms> ms (check <n>)" lines.
jit=$(realpath "$1") pawnc=$(realpath "$2") srv=$(realpath "$3") runs=${4:-3}
root=$(dirname "$(realpath "$0")")/../..

mkdir -p "$srv/gamemodes" "$srv/plugins"
LD_LIBRARY_PATH="$pawnc/lib" "$pawnc/bin/pawncc" "$root/benchmarks/omp_cpu.pwn" \
  -i"$srv/qawno/include" -d0 -O1 -o"$srv/gamemodes/bench.amx" >&2 || exit 2
cp "$jit" "$srv/plugins/jit.so"
rm -f "$srv/server.cfg"

cd "$srv" || exit 2
for run in $(seq "$runs"); do
  for mode in nojit jit; do
    plugins=''
    [ $mode = jit ] && plugins='"jit"'
    cat > config.json <<EOF
{
  "announce": false,
  "enable_query": false,
  "artwork": {"enable": false},
  "logging": {"use_prefix": false, "use_timestamp": false},
  "network": {"port": 7797},
  "pawn": {"main_scripts": ["bench 1"], "side_scripts": [], "legacy_plugins": [$plugins]}
}
EOF
    timeout 300 ./omp-server > bench.out 2>&1
    grep -a '\[BENCH\]' bench.out | grep -v 'done' | sed "s/^.*\[BENCH\] /$mode $run /"
    grep -aq '\[BENCH\] done' bench.out || echo "$mode $run FAILED: $(tail -3 bench.out | tr '\n' ' ')"
    grep -a '\[jit\]' bench.out
  done
done
