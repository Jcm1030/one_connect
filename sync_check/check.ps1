# Compares every Dart file in YOUR project with the files I wrote.
# Run it from the project root (C:\dev\oneconnect):
#     powershell -ExecutionPolicy Bypass -File sync_check\check.ps1
# It only READS files. It never changes anything.
#
# It ignores line endings, spaces, line breaks and commas, so a file that VS Code
# or "dart format" only re-formatted still counts as the same code.

$root = (Get-Location).Path
$manifest = Join-Path $PSScriptRoot 'manifest.txt'
$sha = [System.Security.Cryptography.SHA256]::Create()

function Get-Sha([string]$text) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
  return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLower()
}

$expectedPaths = @{}
$identical = 0
$formattingOnly = 0
$problems = 0

foreach ($line in Get-Content $manifest) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  $parts = $line -split '  ', 3
  $exactExpected = $parts[0]
  $compactExpected = $parts[1]
  $path = $parts[2]
  $expectedPaths[$path] = $true

  if (-not (Test-Path $path)) {
    Write-Host "MISSING    $path" -ForegroundColor Red
    $problems++
    continue
  }
  $text = [System.IO.File]::ReadAllText((Resolve-Path $path).Path, [System.Text.Encoding]::UTF8)
  $text = ($text -replace "`r`n", "`n").TrimEnd("`n") + "`n"
  $compact = $text -replace '[\s,]', ''

  if ((Get-Sha $text) -eq $exactExpected) {
    $identical++
  } elseif ((Get-Sha $compact) -eq $compactExpected) {
    $formattingOnly++
  } else {
    Write-Host "DIFFERENT  $path   (the code itself is different)" -ForegroundColor Yellow
    $problems++
  }
}

# Dart files in lib or test that are NOT on my list (stray copies, old names...)
Get-ChildItem lib, test -Recurse -Filter *.dart | ForEach-Object {
  $relative = ($_.FullName.Substring($root.Length + 1)) -replace '\\', '/'
  if (-not $expectedPaths.ContainsKey($relative) -and $relative -ne 'lib/firebase_options.dart') {
    Write-Host "EXTRA      $relative   (not in my list: a stray or old copy?)" -ForegroundColor Cyan
    $problems++
  }
}

Write-Host ""
Write-Host "$identical identical, $formattingOnly same code with different formatting, $problems need attention."