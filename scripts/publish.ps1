param(
    [string]$Repository = 'a526437928/J2MEStudio',
    [string]$Branch = 'codex/phase2-library'
)
$ErrorActionPreference = 'Stop'
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid GitHub repository name' }
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    # Authentication is handled by Git Credential Manager in the user's browser.
    # This script never reads, accepts or stores passwords, PATs or Apple secrets.
    # Only trust this explicitly selected local checkout for this invocation.
    & git -c "safe.directory=$projectRoot" -c http.sslBackend=openssl -c http.version=HTTP/1.1 push "https://github.com/$Repository.git" "HEAD:refs/heads/$Branch"
    if ($LASTEXITCODE -ne 0) { throw 'Git push failed. Complete Git Credential Manager login and retry; verify repository/workflow write permission.' }
    Write-Host "Pushed. Open https://github.com/$Repository/actions to follow the real build."
} finally {
    Pop-Location
}
