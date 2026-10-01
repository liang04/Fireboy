// 启动 Godot 并把 stdout/stderr 收到文件。
//
// 为什么需要这个包装（2026-09-19 踩坑记录）：
//   在本机上直接跑 Godot 时，stdout 完全拿不到 —— Bash 工具链残缺
//   （dirname 缺失）、PowerShell 的 stdout 也被吞掉（Exit code 0 但无输出），
//   连 Start-Process -RedirectStandardOutput 和 Godot 自带的 --log-file 都不产出文件。
//   用 Node 的 spawn 接管道则一切正常。所以 headless 测试统一走这里。
//
// 另一个坑：可执行文件必须用 **_console.exe** 版本。
//   非 console 版是 GUI 子系统程序，headless 下 stdout 会被丢弃。
//
// 用法：
//   node tools/run_godot.js --headless --path . -- --smoke
//   node tools/run_godot.js --headless --path . --import
// 日志输出到 _run.log（在项目根目录）。

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// 注意：Downloads 下的 "Godot_v4.7.2-stable_win64.exe" 是一个【目录】，
// 真正的可执行文件在它【里面】。别把这两层拼错。
const GODOT = 'C:\\Users\\40577\\Downloads\\Godot_v4.7.2-stable_win64.exe'
            + '\\Godot_v4.7.2-stable_win64_console.exe';
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
});

