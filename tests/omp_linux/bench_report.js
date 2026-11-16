// Summarises bench.sh output: median per test and mode, speedup, and whether
// the checksums of all runs match. Prints one GitHub annotation per test and
// appends a Markdown table to the step summary. Exits 1 on a failed run or a
// checksum mismatch. Usage: node bench_report.js bench.txt
const fs = require('fs');

const results = {};
const problems = [];
for (const line of fs.readFileSync(process.argv[2], 'utf8').split('\n')) {
  const m = line.match(/^(nojit|jit) \d+ (.+): (\d+) ms \(check (-?\d+)\)/);
  if (!m) {
    if (/FAILED|\[jit\]/.test(line)) problems.push(line);
    continue;
  }
  const [, mode, name, ms, check] = m;
  const r = (results[name] ??= { nojit: [], jit: [], checks: new Set() });
  r[mode].push(Number(ms));
  r.checks.add(check);
}

const median = (a) => [...a].sort((x, y) => x - y)[a.length >> 1];
const table = ['| Test | No JIT (ms) | JIT (ms) | Median | Speedup |', '|---|---|---|---|---|'];
let bad = problems.length > 0;
for (const [name, r] of Object.entries(results)) {
  const a = median(r.nojit);
  const b = median(r.jit);
  const speedup = (a / Math.max(b, 1)).toFixed(1);
  const same = r.checks.size === 1;
  bad ||= !same;
  table.push(`| ${name} | ${r.nojit.join(' / ')} | ${r.jit.join(' / ')} | ${a} → ${b} | ${speedup}× |`);
  console.log(`::notice title=${name}::${a} -> ${b} ms (${speedup}x); no JIT ${r.nojit.join('/')}, JIT ${r.jit.join('/')}; checksum ${same ? 'same' : 'DIFFERENT'}`);
}
for (const p of problems.slice(0, 9)) console.log(`::error title=bench::${p.replace(/::/g, ': :')}`);
if (process.env.GITHUB_STEP_SUMMARY) {
  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, table.join('\n') + '\n');
}
console.log(table.join('\n'));
process.exit(bad || Object.keys(results).length === 0 ? 1 : 0);
