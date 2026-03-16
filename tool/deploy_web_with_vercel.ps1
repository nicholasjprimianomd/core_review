$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $projectRoot 'build\web_vercel'

if (-not (Test-Path $outputDir)) {
  throw "Web output not found at $outputDir. Run tool\\build_web_for_vercel.py first."
}

if ($env:VERCEL_ORG_ID -and $env:VERCEL_PROJECT_ID) {
  $vercelDir = Join-Path $outputDir '.vercel'
  New-Item -ItemType Directory -Force -Path $vercelDir | Out-Null

  $projectJson = @{
    orgId = $env:VERCEL_ORG_ID
    projectId = $env:VERCEL_PROJECT_ID
  } | ConvertTo-Json -Compress

  Set-Content -Path (Join-Path $vercelDir 'project.json') -Value $projectJson
}

$deployArgs = @('vercel', 'deploy', $outputDir, '--prod', '--yes')

if ($env:VERCEL_TOKEN) {
  $deployArgs += @('--token', $env:VERCEL_TOKEN)
}

if ($env:VERCEL_ORG_ID) {
  $deployArgs += @('--scope', $env:VERCEL_ORG_ID)
}

npx @deployArgs
