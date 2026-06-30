const { execSync } = require('child_process');

console.log("Reiniciando o Worker Service para forçar um sync imediato...");
try {
    execSync('Stop-Service "ColiseuSpeed Worker" -Force', { shell: 'powershell.exe' });
    execSync('Start-Service "ColiseuSpeed Worker"', { shell: 'powershell.exe' });
    console.log("Serviço reiniciado. Ele tentará sincronizar em até 1 minuto.");
} catch (e) {
    console.error("Erro ao reiniciar serviço", e.message);
}
