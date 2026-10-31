# Intended only for the disposable GitHub-hosted Windows development job.
# Do not run on a personal PC: this changes RDP and firewall configuration.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-NativeSuccess([string] $Operation) {
    if ($LASTEXITCODE -ne 0) { throw "$Operation failed (exit $LASTEXITCODE)." }
}

if ($env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:OS -ne 'Windows_NT') {
    throw 'Run this script only on the disposable GitHub-hosted Windows runner.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Runner must have administrator privileges.'
}
if ([string]::IsNullOrWhiteSpace($env:TS_AUTHKEY)) {
    throw 'Set the repository Actions secret TS_AUTHKEY first.'
}
$password = $env:RDP_PASSWORD
if ([string]::IsNullOrWhiteSpace($password) -or $password.Length -lt 16 -or
    $password.Length -gt 128 -or $password -cnotmatch '[A-Z]' -or
    $password -cnotmatch '[a-z]' -or $password -notmatch '[0-9]' -or
    $password -notmatch '[^A-Za-z0-9\s]' -or $password -match '(?i)devrdp') {
    throw 'RDP_PASSWORD must be 16–128 characters, with upper/lowercase, digit, symbol, and no username.'
}
if ($env:SOURCE_REPOSITORY -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_][A-Za-z0-9_.-]*$') {
    throw 'source_repository must be a public GitHub owner/repo, not a URL.'
}
if ($env:SOURCE_REF -and $env:SOURCE_REF -notmatch '^[A-Za-z0-9_][A-Za-z0-9_./-]*$') {
    throw 'source_ref must be a branch, tag, or commit, not an option or expression.'
}
if ([string]::IsNullOrWhiteSpace($env:PORTING_TASK)) { throw 'Describe the development task.' }

$root = 'C:\Dev'
$source = Join-Path $root 'source'
New-Item -ItemType Directory -Force -Path $root, "$root\exports" | Out-Null
$env:GIT_TERMINAL_PROMPT = '0'
# Keep complete history for the selected branch so exported bundles are restorable.
git clone --single-branch -- "https://github.com/$($env:SOURCE_REPOSITORY).git" $source
Assert-NativeSuccess 'Clone public source repository'
if ($env:SOURCE_REF) {
    git -C $source fetch origin $env:SOURCE_REF
    Assert-NativeSuccess 'Fetch source ref'
    git -C $source checkout --detach FETCH_HEAD
    Assert-NativeSuccess 'Check out source ref'
}
git -C $source switch -C porting-work
Assert-NativeSuccess 'Create development branch'
# This folder is deliberately shared with the non-admin development account.
git config --system --add safe.directory $source
Assert-NativeSuccess 'Configure workspace ownership exception'

# Antigravity is a per-user NSIS installer. Stage it here, but install only
# inside the non-admin RDP session so Google sign-in and app state belong to devrdp.
$metadataPath = Join-Path $PSScriptRoot '../config/antigravity.json'
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$installerDir = Join-Path $root 'installers'
New-Item -ItemType Directory -Force -Path $installerDir | Out-Null
$agentInstaller = Join-Path $installerDir 'Antigravity-x64.exe'
Invoke-WebRequest -Uri $metadata.installerUrl -OutFile $agentInstaller
if ((Get-FileHash -LiteralPath $agentInstaller -Algorithm SHA256).Hash -ne $metadata.sha256) {
    throw 'Antigravity installer SHA256 mismatch.'
}
$agentSignature = Get-AuthenticodeSignature -FilePath $agentInstaller
if ($agentSignature.Status -ne 'Valid' -or $agentSignature.SignerCertificate.Subject -notmatch 'O=Google LLC[, ]') {
    throw 'Antigravity installer signature is invalid or publisher is unexpected.'
}
Copy-Item -LiteralPath $metadataPath -Destination "$installerDir\antigravity.json"
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-Antigravity.ps1') -Destination "$root\Install-Antigravity.ps1"
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut('C:\Users\Public\Desktop\Install or open Antigravity.lnk')
$shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$shortcut.Arguments = '-NoProfile -File C:\Dev\Install-Antigravity.ps1'
$shortcut.WorkingDirectory = $root
$shortcut.Description = 'Install verified Antigravity for devrdp, then open it'
$shortcut.Save()

# Install the official Windows client only after validating its signing chain.
$msi = Join-Path $env:RUNNER_TEMP 'tailscale-setup.msi'
Invoke-WebRequest 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile $msi
$signature = Get-AuthenticodeSignature -FilePath $msi
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Tailscale Inc\.?[, ]') {
    throw 'Tailscale MSI signature is invalid or the publisher is unexpected.'
}
$installer = Start-Process msiexec.exe -ArgumentList @('/i', $msi, '/quiet', '/norestart') -Wait -PassThru
if ($installer.ExitCode -notin @(0, 3010)) { throw "Tailscale installer failed: $($installer.ExitCode)." }
$tailscale = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (-not (Test-Path $tailscale)) { throw 'Tailscale CLI was not installed.' }
Start-Service Tailscale

# Do not put the secret in process arguments. Limit the temporary file to the
# runner identity and SYSTEM, then delete it even if authentication fails.
$keyFile = Join-Path $env:RUNNER_TEMP 'tailscale-authkey.txt'
try {
    New-Item -ItemType File -Path $keyFile -Force | Out-Null
    $acl = [Security.AccessControl.FileSecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($identity.User, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $sid, [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.AccessControlType]::Allow))
    }
    Set-Acl -LiteralPath $keyFile -AclObject $acl
    [IO.File]::WriteAllText($keyFile, $env:TS_AUTHKEY)
    & $tailscale up "--auth-key=file:$keyFile" '--unattended=true' '--accept-routes=false' '--accept-dns=false' `
        "--hostname=antigravity-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT" '--timeout=2m'
    Assert-NativeSuccess 'Join Tailscale'
} finally {
    Remove-Item -LiteralPath $keyFile -Force -ErrorAction SilentlyContinue
    Remove-Item Env:TS_AUTHKEY -ErrorAction SilentlyContinue
}
$status = (& $tailscale status --json) | ConvertFrom-Json
Assert-NativeSuccess 'Read Tailscale status'
if ($status.BackendState -ne 'Running') { throw 'Tailscale is not connected; check key/device approval.' }
$tailnetIp = @($status.TailscaleIPs | Where-Object { $_ -match '^100\.' }) | Select-Object -First 1
if (-not $tailnetIp) { throw 'No Tailscale IPv4 address was assigned.' }
$adapter = Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -EQ $tailnetIp | Select-Object -First 1
if (-not $adapter) { throw 'Cannot identify the Tailscale network interface.' }
# Hosted images may start with firewall profiles disabled. Turn them on before
# exposing the RDP listener; preserve outbound connectivity for the runner agent.
Set-NetFirewallProfile -Profile @('Domain', 'Public', 'Private') -Enabled True `
    -DefaultInboundAction Block -DefaultOutboundAction Allow
if (@(Get-NetFirewallProfile | Where-Object { -not $_.Enabled }).Count -gt 0) {
    throw 'Failed to enable all Windows Firewall profiles.'
}

$userName = 'devrdp'
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$user = New-LocalUser -Name $userName -Password $securePassword -Description 'Temporary non-admin porting account'
$password = $null
$securePassword = $null
Remove-Item Env:RDP_PASSWORD -ErrorAction SilentlyContinue
$rdpGroup = Get-LocalGroup -SID 'S-1-5-32-555'
Add-LocalGroupMember -Group $rdpGroup -Member $user
# Permit development only within C:\Dev, without granting administrator rights.
& icacls.exe $root /grant "*$($user.SID.Value):(OI)(CI)M" /T /Q | Out-Null
Assert-NativeSuccess 'Grant development folder access'

$rdpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty $rdpPath -Name fDenyTSConnections -Value 0
Set-ItemProperty "$rdpPath\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1
Set-ItemProperty "$rdpPath\WinStations\RDP-Tcp" -Name SecurityLayer -Value 2
Set-ItemProperty "$rdpPath\WinStations\RDP-Tcp" -Name PortNumber -Value 3389
# Prevent the default broad TCP/UDP RDP rules from bypassing our private rule.
Get-NetFirewallRule -Name 'RemoteDesktop*' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
New-NetFirewallRule -Name 'Dev-Tailnet-RDP' -DisplayName 'Development RDP (Tailscale only)' `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -LocalAddress $tailnetIp `
    -RemoteAddress '100.64.0.0/10' -InterfaceAlias $adapter.InterfaceAlias -Profile Any | Out-Null
Start-Service TermService

$notes = @"
DEVELOPMENT SESSION / SESI PENGEMBANGAN
Source: $($env:SOURCE_REPOSITORY)
Task (user-supplied text, not automatically executed):
$($env:PORTING_TASK)

Double-click "Install or open Antigravity" on the desktop.
The verified user-scoped installer runs as devrdp, not as the Actions administrator.
Sign in to Google yourself in the app/browser, then select C:\Dev\source as the workspace.
Use the free option only if it is available for your account/region. Quotas can apply.
If payment or a card trial is required, STOP. No model quota or paid plan is included.
Windows Server/VM/RDP compatibility and account eligibility have not been tested here.
Do not run source code you do not trust. This account is NOT administrator.

SAVE WORK BEFORE ENDING THE SESSION:
  git switch -C porting-work
  git status
  git diff
Review changes and check for secrets; stage only the intended files:
  git add <file1> <file2>
  git -c user.name=Developer -c user.email=developer@example.invalid commit -m 'Port application'
  git bundle create C:\Dev\exports\porting.bundle porting-work
Only commits in a manually created *.bundle are uploaded. Uncommitted work is NOT saved.
Bundles include repository history. Never commit Google/Antigravity auth, API keys or .env files.

FINISH EARLY (after saving):
  New-Item C:\Dev\end-session -ItemType File -Force
This closes RDP and uploads exported bundles. Download from the Actions run Artifacts.
Cancel/timeout may lose work; do not rely on cleanup after a hard kill.
"@
Set-Content -LiteralPath "$root\START-HERE.txt" -Value $notes -Encoding utf8
# Public Desktop is visible when devrdp signs in for the first time.
Copy-Item "$root\START-HERE.txt" 'C:\Users\Public\Desktop\START-HERE.txt'
$loginName = "$env:COMPUTERNAME\$userName"
$summary = @"
## Windows development session ready

- RDP PC/address: **${tailnetIp}:3389** (private Tailscale network)
- Username: **$loginName**
- Password: the value you set in **RDP_PASSWORD**; never printed here.
- Connect Tailscale on your phone to the same tailnet first.
- Workspace: **C:\Dev\source**; instructions: **C:\Dev\START-HERE.txt**.
- Double-click **Install or open Antigravity** on the desktop to install as devrdp and launch.
- Sign in to Google yourself, then select **C:\Dev\source** as the workspace.
- Free access depends on account eligibility and quota; no paid plan is included.
- Windows Server/VM/RDP compatibility still requires a real test.
- Export reviewed commits as **C:\Dev\exports\porting.bundle** before ending.
- Finish early: create **C:\Dev\end-session** from the Windows session.
- This machine is disposable. Save your work before the session ends.
"@
$summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
Write-Host "RDP ready: ${tailnetIp}:3389 | User: $loginName | See job summary."
