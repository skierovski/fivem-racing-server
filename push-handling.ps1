param(
    [Parameter(Mandatory=$true)]
    [string]$CarName
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoHandling = "c:\Some Project\fivem-racing-server\resources\handling"
$tiers = @("bronze", "silver", "gold", "platinum", "diamond", "blacklist", "custom")
$found = $false

foreach ($tier in $tiers) {
    $srcFile = Join-Path $scriptDir "$tier\$CarName.meta"
    if (Test-Path $srcFile) {
        $destFolder = Join-Path $repoHandling $tier
        if (-not (Test-Path $destFolder)) { New-Item -ItemType Directory -Path $destFolder -Force | Out-Null }
        Copy-Item $srcFile (Join-Path $destFolder "$CarName.meta") -Force
        Write-Host "Copied: $tier/$CarName.meta" -ForegroundColor Cyan
        $found = $true
        break
    }
}

if (-not $found) {
    Write-Host "File '$CarName.meta' not found in any tier folder." -ForegroundColor Red
    exit 1
}

Set-Location "c:\Some Project\fivem-racing-server"
git add resources/handling/

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
git commit -m "Handling: $CarName ($timestamp)"

Write-Host "Pushing to dev..." -ForegroundColor Cyan
git push origin dev

if ($LASTEXITCODE -eq 0) {
    Write-Host "Done! $CarName handling pushed to dev." -ForegroundColor Green
} else {
    Write-Host "Push failed!" -ForegroundColor Red
}
