# Launched interactively by devrdp, NOT by the privileged Actions runner.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($identity.Name -notlike '*\devrdp' -or
        $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Open this shortcut from the non-admin devrdp RDP session only.'
    }
    $metadata = Get-Content -LiteralPath 'C:\Dev\installers\antigravity.json' -Raw | ConvertFrom-Json
    $installer = 'C:\Dev\installers\Antigravity-x64.exe'
    if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $metadata.sha256) {
        throw 'Installer SHA256 mismatch. Do not run an unverified installer.'
    }
    $signature = Get-AuthenticodeSignature -FilePath $installer
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Google LLC[, ]') {
        throw 'Installer is not signed by the expected Google LLC publisher.'
    }
    $app = 'C:\Dev\Antigravity\Antigravity.exe'
    if (-not (Test-Path -LiteralPath $app)) {
        Write-Host "Installing Google Antigravity $($metadata.version) for devrdp..."
        # NSIS: /D must be last; destination has no spaces. Do not install as admin.
        $process = Start-Process -FilePath $installer -ArgumentList @('/S', '/D=C:\Dev\Antigravity') -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "Antigravity installer failed: $($process.ExitCode)." }
    }
    if (-not (Test-Path -LiteralPath $app)) {
        throw 'Expected Antigravity.exe was not found. Check installer compatibility; no sandbox bypass is applied.'
    }
    Write-Host 'Opening Antigravity. Sign in yourself and select C:\Dev\source as the project/workspace.'
    Write-Host 'Use a free option only if available to your account; do not enable paid billing or a card trial.'
    Start-Process -FilePath $app -WorkingDirectory 'C:\Dev\source'
} catch {
    Write-Host "Antigravity setup/open failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'RDP remains available. Check START-HERE.txt and the official Antigravity requirements.'
    Read-Host 'Press Enter to close' | Out-Null
    exit 1
}
