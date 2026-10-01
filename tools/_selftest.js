// 跑 gen_levels.py 的自检，并落日志（本机 bash 残缺，统一走 Node）
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const PY = 'C:\\Users\\40577\\.workbuddy\\binaries\\python\\versions\\3.13.12\\python.exe';
const CWD = path.resolve(__dirname, '..');
const script = process.argv[2] || 'selftest';

const args = script === 'gen'
  ? ['tools/gen_levels.py']
  : ['-X', 'utf8', '-c', `
import sys
sys.path.insert(0, 'tools')
import gen_levels as G
ok = G.selftest()
sys.exit(0 if ok else 1)
`];

const child = spawn(PY, args, { cwd: CWD });
let out = '';
child.stdout.on('data', d => { out += d.toString('utf8'); });
child.stderr.on('data', d => { out += d.toString('utf8'); });
child.on('close', code => {
  fs.writeFileSync(path.join(CWD, '_selftest.log'), out, 'utf8');
  console.log(out);
  console.log('--- exit code:', code);
});
