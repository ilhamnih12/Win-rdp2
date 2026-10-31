# Best effort after success, setup failure, or cancellation. A hard runner kill
# cannot guarantee that this step runs; the hosted VM is disposed by GitHub.
$ErrorActionPreference = 'Continue'
if ($env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:OS -ne 'Windows_NT') {
    throw 'Cleanup is restricted to the disposable GitHub-hosted Windows runner.'
}
$rdpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty $rdpPath -Name fDenyTSConnections -Value 1
Remove-NetFirewallRule -Name 'Dev-Tailnet-RDP' -ErrorAction SilentlyContinue
Disable-LocalUser -Name 'devrdp' -ErrorAction SilentlyContinue
Stop-Service TermService -Force -ErrorAction SilentlyContinue
# Stop this user's remaining programs before artifact upload. Do not kill runner
# processes, which run under a different account.
$login = "$env:COMPUTERNAME\devrdp"
Get-Process -IncludeUserName -ErrorAction SilentlyContinue |
    Where-Object UserName -EQ $login |
    Stop-Process -Force -ErrorAction SilentlyContinue
$tailscale = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $tailscale) {
    & $tailscale logout
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Tailscale logout failed; check the device in your tailnet.' }
}
Remove-Item (Join-Path $env:RUNNER_TEMP 'tailscale-authkey.txt') -Force -ErrorAction SilentlyContinue
Remove-LocalUser -Name 'devrdp' -ErrorAction SilentlyContinue
Write-Host 'Cleanup attempted. Only manually created git bundles are eligible for artifact upload.'
