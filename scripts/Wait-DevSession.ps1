$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:SESSION_MINUTES -notin @('30', '60', '120', '180')) {
    throw 'Allowed session lengths: 30, 60, 120, or 180 minutes.'
}
$deadline = [DateTime]::UtcNow.AddMinutes([int]$env:SESSION_MINUTES)
$nextLog = [DateTime]::UtcNow
Write-Host "Development session ends at $($deadline.ToString('u')). No automatic restart."
while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath 'C:\Dev\end-session' -PathType Leaf) {
        Write-Host 'User requested an early finish. Closing RDP and uploading deliberate exports.'
        break
    }
    if ([DateTime]::UtcNow -ge $nextLog) {
        $remaining = [Math]::Ceiling(($deadline - [DateTime]::UtcNow).TotalMinutes)
        Write-Host "Development time remaining: $remaining minutes. Save commits before session end."
        $nextLog = [DateTime]::UtcNow.AddMinutes(5)
    }
    Start-Sleep -Seconds 10
}
Write-Host 'Session finished. Uncommitted work will not be exported.'
