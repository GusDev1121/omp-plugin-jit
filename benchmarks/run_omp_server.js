// Run omp-server.exe once, timestamp every output line (ms since spawn),
// stop it a grace period after a marker line appears (optionally sampling
// process CPU over CPU_WINDOW_MS first), and print the lines matching a
// filter as JSON. Windows only (CPU sampling uses PowerShell).
// Usage: [CPU_WINDOW_MS=60000] node run_omp_server.js <serverDir> <stopMarkerRegex> <graceMs> <timeoutMs> <keepRegex>
const { spawn } = require('child_process');
const path = require('path');
const [dir, stopRe, graceMs, timeoutMs, keepRe] = process.argv.slice(2);
const stop = new RegExp(stopRe), keep = new RegExp(keepRe);
const t0 = process.hrtime.bigint();
const ms = () => Number(process.hrtime.bigint() - t0) / 1e6;
const child = spawn(path.join(dir, 'omp-server.exe'), [], { cwd: dir });
const lines = [];
let buf = '', stopping = false;
// Console "exit" via piped stdin is ignored by open.mp, so after the grace
// period we sample process CPU time over CPU_WINDOW_MS, then kill.
const CPU_WINDOW_MS = Number(process.env.CPU_WINDOW_MS || 0);
const cpuMs = () => Number(require('child_process').execSync(
  `powershell -NoProfile -Command "(Get-Process -Id ${child.pid}).TotalProcessorTime.TotalMilliseconds"`).toString().trim().replace(',', '.'));
let cpu = null;
const sendExit = () => {
  if (!CPU_WINDOW_MS) { child.kill(); return; }
  const c0 = cpuMs(), w0 = ms();
  setTimeout(() => {
    const c1 = cpuMs(), w1 = ms();
    cpu = { windowMs: Math.round(w1 - w0), cpuMs: Math.round(c1 - c0), cpuPctOfOneCore: +((c1 - c0) / (w1 - w0) * 100).toFixed(2) };
    child.kill();
  }, CPU_WINDOW_MS);
};
function onData(d) {
  buf += d.toString('latin1');
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).replace(/\r$/, '');
    buf = buf.slice(i + 1);
    const t = ms();
    if (keep.test(line)) lines.push({ t: Math.round(t), line: line.replace(/^\[[^\]]*\] \[Info\] /, '') });
    if (!stopping && stop.test(line)) { stopping = true; setTimeout(sendExit, Number(graceMs)); }
  }
}
child.stdout.on('data', onData);
child.stderr.on('data', onData);
const killer = setTimeout(() => { lines.push({ t: Math.round(ms()), line: 'TIMEOUT - killed' }); child.kill(); }, Number(timeoutMs));
child.on('exit', (code) => {
  clearTimeout(killer);
  console.log(JSON.stringify({ exitCode: code, totalMs: Math.round(ms()), cpu, lines }, null, 1));
});
