import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const apiDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const isWin = process.platform === 'win32';
const venvPython = isWin
  ? path.join(apiDir, '.venv', 'Scripts', 'python.exe')
  : path.join(apiDir, '.venv', 'bin', 'python');
const python = existsSync(venvPython) ? venvPython : 'python';

const child = spawn(
  python,
  ['-m', 'uvicorn', 'main:app', '--reload', '--host', '0.0.0.0', '--port', '8001'],
  { cwd: apiDir, stdio: 'inherit', shell: false },
);

child.on('exit', (code) => process.exit(code ?? 1));
