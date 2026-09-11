Continue = 'Stop'
while (True) {
    Write-Host "Starting localtunnel..."
    npx localtunnel --port 9092 --subdomain connectcallapp
    Write-Host "Localtunnel exited, restarting in 2 seconds..."
    Start-Sleep -Seconds 2
}
