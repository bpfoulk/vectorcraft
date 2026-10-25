<# Cargo bridge for VectorCraft.slnx (Visual Studio 2026, x64 MSVC).
   Build artifacts are isolated under target/visual-studio. No C# or C++ app is generated. #>
[CmdletBinding()]
param(
  [ValidateSet('Build', 'Rebuild', 'Clean')]
  [string] $Action = 'Build',
  [ValidateSet('Debug', 'Release')]
  [string] $Configuration = 'Debug'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Toolchain = '1.95.0-x86_64-pc-windows-msvc'
$Target = 'x86_64-pc-windows-msvc'
$Profile = if ($Configuration -eq 'Debug') { 'dev' } else { 'release' }

# Resolve Cargo even in a Visual Studio instance started before Rust was installed.
$CargoHomePath = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE '.cargo' }
$CargoExe = Join-Path $CargoHomePath 'bin\cargo.exe'
if (-not (Test-Path -LiteralPath $CargoExe -PathType Leaf)) {
  $CargoCommand = Get-Command cargo.exe -ErrorAction SilentlyContinue
  if ($null -eq $CargoCommand) {
    throw 'Cargo is missing. Install Rust with rustup; see docs/development.md, Windows: Visual Studio 2026.'
  }
  $CargoExe = $CargoCommand.Source
}
$SavedEnvironment = @{}
foreach ($Name in @('PATH', 'CARGO_TARGET_DIR', 'CARGO_TERM_COLOR', 'CARGO_PROFILE_DEV_OPT_LEVEL', 'CARGO_PROFILE_DEV_DEBUG')) {
  $SavedEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
}

function Invoke-Cargo([string[]] $CargoArguments) {
  & $CargoExe "+$Toolchain" @CargoArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Cargo $($CargoArguments[0]) failed with exit code $LASTEXITCODE."
  }
}

Push-Location $WorkspaceRoot
try {
  $env:PATH = "$(Split-Path -Parent $CargoExe);$env:PATH"
  $env:CARGO_TARGET_DIR = Join-Path $WorkspaceRoot 'target\visual-studio'
  $env:CARGO_TERM_COLOR = 'never'
  if ($Configuration -eq 'Debug') {
    # The regular dev profile optimizes workspace code. Disable that only for this solution;
    # third-party dependencies retain their existing opt-level = 2 for rendering performance.
    $env:CARGO_PROFILE_DEV_OPT_LEVEL = '0'
    $env:CARGO_PROFILE_DEV_DEBUG = '2'
  }
  Write-Output "VectorCraft $Configuration ($Target; Rust $Toolchain)"
  if ($Action -eq 'Clean' -or $Action -eq 'Rebuild') {
    Invoke-Cargo -CargoArguments @('clean', '--package', 'vectorcraft', '--target', $Target, '--profile', $Profile)
  }
  if ($Action -ne 'Clean') {
    Invoke-Cargo -CargoArguments @('build', '--locked', '--package', 'vectorcraft', '--bin', 'vectorcraft', '--target', $Target, '--profile', $Profile, '--message-format', 'short')
  }
} finally {
  Pop-Location
  foreach ($Name in $SavedEnvironment.Keys) {
    if ($null -eq $SavedEnvironment[$Name]) {
      # PowerShell 7 distinguishes an absent variable from an empty one; restore absence too.
      Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
    } else {
      [Environment]::SetEnvironmentVariable($Name, $SavedEnvironment[$Name], 'Process')
    }
  }
}
