// 启动 Godot 并把 stdout/stderr 收到文件。
//
// 为什么需要这个包装（2026-09-19 踩坑记录）：
//   在本机上直接跑 Godot 时，stdout 完全拿不到 —— Bash 工具链残缺
//   （dirname 缺失）、PowerShell 的 stdout 也被吞掉（Exit code 0 但无输出），
//   连 Start-Process -RedirectStandardOutput 和 Godot 自带的 --log-file 都不产出文件。
//   当时改用 Node 的 spawn 接管道；本文件保留为可选日志包装。
//   当前跨平台完整检查入口是 python tools/run_checks.py。
//
// 另一个坑：可执行文件必须用 **_console.exe** 版本。
//   非 console 版是 GUI 子系统程序，headless 下 stdout 会被丢弃。
//
// 用法：
//   node tools/run_godot.js --headless --path . -- --smoke
//   node tools/run_godot.js --headless --path . --import
// 日志输出到 _run.log（在项目根目录）。

const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// 使用 PATH 中的 Godot 4.7；Windows 指定 GODOT_BIN 为 4.7.x 的 _console.exe。
// 不再依赖某位开发者 Downloads 下的绝对路径。
const GODOT = process.env.GODOT_BIN || 'godot';
const version = spawnSync(GODOT, ['--version'], { encoding: 'utf8' });
const actual = (version.stdout || '').trim();
if (version.error || version.status !== 0 || !actual.startsWith('4.7.')) {
  console.error('This project requires Godot 4.7 (4.7.x). Set GODOT_BIN to its executable; got ' + JSON.stringify(actual));
  process.exit(1);
}
const CWD = path.resolve(__dirname, '..');
const args = process.argv.slice(2);

// Godot 不接受 "node ... " 之外的额外参数，直接透传
const logPath = path.join(CWD, '_run.log');
const out = fs.createWriteStream(logPath, { flags: 'w' });

const child = spawn(GODOT, args, { cwd: CWD });

child.stdout.on('data', (d) => { out.write(d); });
child.stderr.on('data', (d) => { out.write(d); });
child.on('error', (e) => {
  out.write('SPAWN ERROR: ' + e.message + '\n');
  console.error('SPAWN ERROR: ' + e.message);
});
child.on('close', (code) => {
  out.write('\n=== EXIT CODE: ' + code + ' ===\n');
  out.end();
  console.log('godot exited with code ' + code + '; log -> ' + logPath);
  process.exitCode = code === 0 ? 0 : 1;
});

