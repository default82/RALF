Write-Host "BOOTSTRAP SMOKE: repo is checked out and scripts can run."
Write-Host "Timestamp: $(Get-Date -Format o)"
Write-Host "User: $env:USERNAME"
Write-Host "PWD: $(Get-Location)"

# Optional: verify tools presence (later we add tofu/ansible)
$tools = @("git")
foreach ($t in $tools) {
  $cmd = Get-Command $t -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Missing tool: $t" }
  Write-Host "OK: $t -> $($cmd.Source)"
}

Write-Host "SMOKE OK"
exit 0

