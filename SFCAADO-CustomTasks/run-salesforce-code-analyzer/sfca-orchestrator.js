const { exec } = require('child_process');
const path = require('path');

const scriptPath = path.join(__dirname, 'sfca-orchestrator.ps1');
const command = `pwsh -File "${scriptPath}"`;

console.log(`Running: ${command}`);

const child = exec(command, { env: process.env });

child.stdout.on('data', (data) => process.stdout.write(data));
child.stderr.on('data', (data) => process.stderr.write(data));

child.on('exit', (code) => process.exit(code));