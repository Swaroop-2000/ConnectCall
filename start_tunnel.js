const { execSync } = require('child_process');
while (true) {
    console.log('Starting localtunnel...');
    try {
        execSync('npx localtunnel --port 9092 --subdomain connectcallapp9092', { stdio: 'inherit' });
    } catch (e) {
        console.log('Localtunnel exited, restarting in 2 seconds...');
    }
    const end = Date.now() + 2000;
    while (Date.now() < end) {}
}
