param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CliArgs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:Version = "0.3.0"
$script:JsonOutput = $false
$script:Force = $false
$script:FixConfig = $false
$script:ActiveToo = $false
$script:InstallPrefix = ""
$script:InstallBinDir = ""
$script:Positionals = New-Object System.Collections.Generic.List[string]
$script:LockHeld = $false
$script:FatalMarker = "__codex_auth_snap_fatal__"
$script:IsWindowsHost = $PSVersionTable.PSVersion.Major -lt 6 -or ($null -ne (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue) -and $Global:IsWindows)

$script:ScriptPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) {
  $script:ScriptPath = $PSCommandPath
}

function Get-HomePath {
  if (-not [string]::IsNullOrWhiteSpace($HOME)) {
    return $HOME
  }
  $profilePath = [Environment]::GetFolderPath("UserProfile")
  if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
    return $profilePath
  }
  throw "Could not resolve the user home directory."
}

$script:HomeDir = Get-HomePath
$script:CodexHomeDir = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { $env:CODEX_HOME } else { Join-Path $script:HomeDir ".codex" }
if (-not [string]::IsNullOrWhiteSpace($env:CODEX_AUTH_SNAP_HOME)) {
  $script:SnapHomeDir = $env:CODEX_AUTH_SNAP_HOME
} elseif (-not [string]::IsNullOrWhiteSpace($env:CODEX_AUTH_SWITCH_HOME)) {
  $script:SnapHomeDir = $env:CODEX_AUTH_SWITCH_HOME
} elseif (-not [string]::IsNullOrWhiteSpace($env:CODEX_SWAP_HOME)) {
  $script:SnapHomeDir = $env:CODEX_SWAP_HOME
} else {
  $script:SnapHomeDir = Join-Path $script:HomeDir ".codex-auth-snap"
}

$script:AuthFile = Join-Path $script:CodexHomeDir "auth.json"
$script:ConfigFile = Join-Path $script:CodexHomeDir "config.toml"
$script:AccountsDir = Join-Path $script:SnapHomeDir "accounts"
$script:MetaDir = Join-Path $script:SnapHomeDir "meta"
$script:BeforeLoginDir = Join-Path $script:SnapHomeDir "before-login"
$script:CurrentFile = Join-Path $script:SnapHomeDir "current"
$script:PendingFile = Join-Path $script:SnapHomeDir "pending-login"
$script:InstallMetaFile = Join-Path $script:MetaDir "install.json"
$script:LockDir = Join-Path $script:SnapHomeDir "lock"

function Show-Usage {
  @"
Usage:
  codex-auth-snap.ps1 [--json] init [--fix] [--force]
  codex-auth-snap.ps1 [--json] save <name> [--force]
  codex-auth-snap.ps1 [--json] use <name> [--force]
  codex-auth-snap.ps1 [--json] begin-login <name> [--force]
  codex-auth-snap.ps1 [--json] finish-login [name] [--force]
  codex-auth-snap.ps1 [--json] abort-login [--force]
  codex-auth-snap.ps1 [--json] install [--prefix <dir>|--bin-dir <dir>] [--force]
  codex-auth-snap.ps1 [--json] list
  codex-auth-snap.ps1 [--json] current
  codex-auth-snap.ps1 [--json] remove <name> [--active-too]
  codex-auth-snap.ps1 [--json] doctor
  codex-auth-snap.ps1 [--json] paths
  codex-auth-snap.ps1 [--json] version

Local Codex ChatGPT auth.json snapshot switcher. It never calls the network and
never calls codex logout.
"@
}

function ConvertTo-CompactJson {
  param([Parameter(Mandatory = $true)]$Value)
  $Value | ConvertTo-Json -Depth 20 -Compress
}

function Write-Ok {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    $Result = ([ordered]@{})
  )
  if ($script:JsonOutput) {
    $envelope = [ordered]@{
      content = @([ordered]@{ type = "text"; text = $Text })
      structuredContent = [ordered]@{ result = $Result }
      isError = $false
    }
    ConvertTo-CompactJson $envelope
  } else {
    Write-Output $Text
  }
}

function Write-ErrorEnvelope {
  param(
    [Parameter(Mandatory = $true)][string]$Code,
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$SuggestedFix = "Check the command arguments and local files, then retry.",
    [bool]$Retryable = $false
  )
  if ($script:JsonOutput) {
    $envelope = [ordered]@{
      content = @([ordered]@{ type = "text"; text = $Message })
      structuredContent = [ordered]@{
        error = [ordered]@{
          code = $Code
          message = $Message
          retryable = $Retryable
          field_errors = @()
          suggested_fix = $SuggestedFix
        }
      }
      isError = $true
    }
    ConvertTo-CompactJson $envelope
  } else {
    [Console]::Error.WriteLine("ERROR: {0}" -f $Message)
  }
}

function Fatal {
  param(
    [Parameter(Mandatory = $true)][string]$Code,
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$SuggestedFix = "Check the command arguments and local files, then retry.",
    [bool]$Retryable = $false
  )
  Write-ErrorEnvelope -Code $Code -Message $Message -SuggestedFix $SuggestedFix -Retryable $Retryable
  throw $script:FatalMarker
}

function Warn {
  param([Parameter(Mandatory = $true)][string]$Message)
  [Console]::Error.WriteLine("WARN: {0}" -f $Message)
}

function Test-ReparsePoint {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return $false
  }
  $item = Get-Item -LiteralPath $Path -Force
  return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Refuse-ReparsePoint {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (Test-ReparsePoint $Path) {
    Fatal "symlink_refused" "Refusing to use reparse point path: $Path" "Replace the link with a real file or directory."
  }
}

function Protect-PathForCurrentUser {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not $script:IsWindowsHost -or -not (Test-Path -LiteralPath $Path)) {
    return
  }
  try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $item = Get-Item -LiteralPath $Path -Force
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    if ($item.PSIsContainer) {
      $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    } else {
      $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, "FullControl", "Allow")
    }
    $acl.ResetAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
  } catch {
    Warn "could not tighten ACL for ${Path}: $($_.Exception.Message)"
  }
}

function Ensure-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)
  Refuse-ReparsePoint $Path
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Fatal "not_directory" "Path is not a directory: $Path" "Replace it with a directory."
  }
  Protect-PathForCurrentUser $Path
}

function Ensure-Dirs {
  Ensure-Directory $script:CodexHomeDir
  Ensure-Directory $script:SnapHomeDir
  Ensure-Directory $script:AccountsDir
  Ensure-Directory $script:MetaDir
  Ensure-Directory $script:BeforeLoginDir
  if (Test-Path -LiteralPath $script:AuthFile) {
    Refuse-ReparsePoint $script:AuthFile
    Protect-PathForCurrentUser $script:AuthFile
  }
}

function Ensure-InstallStateDirs {
  Ensure-Directory $script:SnapHomeDir
  Ensure-Directory $script:MetaDir
}

function Acquire-Lock {
  if (Test-Path -LiteralPath $script:LockDir) {
    Fatal "lock_exists" "Another codex-auth-snap process is running." "Wait for it to finish, or remove a verified stale lock directory."
  }
  New-Item -ItemType Directory -Path $script:LockDir -ErrorAction Stop | Out-Null
  $script:LockHeld = $true
  Protect-PathForCurrentUser $script:LockDir
}

function Release-Lock {
  if ($script:LockHeld) {
    Remove-Item -LiteralPath $script:LockDir -Force -ErrorAction SilentlyContinue
    $script:LockHeld = $false
  }
}

function Resolve-AbsolutePath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return (Join-Path (Get-Location).Path $Path)
}

function Get-SelectedInstallBinDir {
  if (-not [string]::IsNullOrWhiteSpace($script:InstallBinDir)) {
    return (Resolve-AbsolutePath $script:InstallBinDir)
  }
  if (-not [string]::IsNullOrWhiteSpace($script:InstallPrefix)) {
    return (Resolve-AbsolutePath (Join-Path $script:InstallPrefix "bin"))
  }
  return (Join-Path (Join-Path $script:HomeDir ".local") "bin")
}

function Get-SelectedInstallPath {
  return (Join-Path (Get-SelectedInstallBinDir) "codex-auth-snap.ps1")
}

function Test-AccountName {
  param([string]$Name)
  return ($Name -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')
}

function Validate-AccountName {
  param([string]$Name)
  if (-not (Test-AccountName $Name)) {
    Fatal "invalid_name" "Invalid account name: $Name" "Use 1-64 chars matching ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$."
  }
}

function Require-RegularFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Code = "file_missing",
    [string]$Message = "Missing file: $Path"
  )
  if (-not (Test-Path -LiteralPath $Path)) {
    Fatal $Code $Message "Create the file through the expected workflow, then retry."
  }
  Refuse-ReparsePoint $Path
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Fatal "not_regular_file" "Path is not a regular file: $Path" "Replace it with a regular file."
  }
  if ((Get-Item -LiteralPath $Path -Force).Length -le 0) {
    Fatal "empty_file" "File is empty: $Path" "Regenerate the file, then retry."
  }
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  $raw = Get-Content -LiteralPath $Path -Raw
  return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

function Test-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    Require-RegularFile $Path "file_missing" "Missing JSON file: $Path"
    [void](Read-JsonFile $Path)
    return $true
  } catch {
    if ($_.Exception.Message -eq $script:FatalMarker) {
      throw
    }
    return $false
  }
}

function Validate-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  Require-RegularFile $Path "file_missing" "Missing JSON file: $Path"
  try {
    [void](Read-JsonFile $Path)
  } catch {
    Fatal "invalid_json" "Invalid JSON file: $Path" "Regenerate or fix the JSON file before retrying."
  }
}

function Get-JsonField {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Field
  )
  $value = Read-JsonFile $Path
  foreach ($part in $Field.Split(".")) {
    $property = $value.PSObject.Properties[$part]
    if ($null -eq $property) {
      return $null
    }
    $value = $property.Value
  }
  return $value
}

function Test-JsonFieldExists {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Field
  )
  $value = Read-JsonFile $Path
  foreach ($part in $Field.Split(".")) {
    $property = $value.PSObject.Properties[$part]
    if ($null -eq $property) {
      return $false
    }
    $value = $property.Value
  }
  return $true
}

function Test-AuthLooksLikeChatGPT {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    $mode = Get-JsonField $Path "auth_mode"
    if ($mode -eq "chatgpt") {
      return $true
    }
    return (Test-JsonFieldExists $Path "tokens")
  } catch {
    return $false
  }
}

function Test-AuthHasRefreshToken {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    return (Test-JsonFieldExists $Path "tokens.refresh_token")
  } catch {
    return $false
  }
}

function Validate-AuthFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [bool]$AllowForce = $false
  )
  if (-not (Test-Path -LiteralPath $Path)) {
    Fatal "auth_missing" "auth.json does not exist: $Path" "Run codex login first, then retry."
  }
  Validate-JsonFile $Path
  if (-not (Test-AuthLooksLikeChatGPT $Path)) {
    if ($AllowForce) {
      Warn "auth.json does not look like Codex ChatGPT auth; continuing because --force was provided."
    } else {
      Fatal "not_chatgpt_auth" "auth.json does not look like Codex ChatGPT auth." "Run codex login for a ChatGPT account, or rerun with --force if you have verified this file."
    }
  }
}

function Test-AuthValidationStatus {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [bool]$AllowForce = $false
  )
  if (-not (Test-Path -LiteralPath $Path)) {
    return $false
  }
  Refuse-ReparsePoint $Path
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Fatal "not_regular_file" "Path is not a regular file: $Path" "Replace it with a regular file."
  }
  if ((Get-Item -LiteralPath $Path -Force).Length -le 0) {
    return $false
  }
  try {
    [void](Read-JsonFile $Path)
  } catch {
    return $false
  }
  if (-not (Test-AuthLooksLikeChatGPT $Path)) {
    return $AllowForce
  }
  return $true
}

function Get-FileSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant())
}

function Get-ShortHash {
  param([string]$Hash)
  if ([string]::IsNullOrWhiteSpace($Hash)) {
    return ""
  }
  if ($Hash.Length -lt 12) {
    return $Hash
  }
  return $Hash.Substring(0, 12)
}

function Get-CliVersionFromFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Test-ReparsePoint $Path)) {
    return ""
  }
  $match = Select-String -LiteralPath $Path -Pattern '^\$script:Version = "([^"]+)"' -List -ErrorAction SilentlyContinue
  if ($null -eq $match) {
    return ""
  }
  return $match.Matches[0].Groups[1].Value
}

function Test-LooksLikeCodexAuthSnap {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Test-ReparsePoint $Path)) {
    return $false
  }
  $content = Get-Content -LiteralPath $Path -Raw
  return ($content.Contains("Local Codex ChatGPT auth.json snapshot switcher") -and -not [string]::IsNullOrWhiteSpace((Get-CliVersionFromFile $Path)))
}

function Get-NowIso {
  return (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
}

function Get-NowStamp {
  return (Get-Date).ToString("yyyyMMdd-HHmmss")
}

function Write-SecureText {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Text
  )
  $dir = Split-Path -Parent $Path
  Ensure-Directory $dir
  $tmp = Join-Path $dir (".tmp.{0}" -f [Guid]::NewGuid().ToString("N"))
  Set-Content -LiteralPath $tmp -Value $Text -Encoding UTF8
  Protect-PathForCurrentUser $tmp
  if (Test-ReparsePoint $Path) {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Fatal "symlink_refused" "Refusing to overwrite reparse point file: $Path" "Replace the link with a real file."
  }
  Move-Item -LiteralPath $tmp -Destination $Path -Force
  Protect-PathForCurrentUser $Path
}

function Copy-JsonAtomically {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  Validate-JsonFile $Source
  $dir = Split-Path -Parent $Destination
  Ensure-Directory $dir
  if (Test-ReparsePoint $Destination) {
    Fatal "symlink_refused" "Refusing to overwrite reparse point file: $Destination" "Replace the link with a real file."
  }
  $tmp = Join-Path $dir (".tmp.{0}" -f [Guid]::NewGuid().ToString("N"))
  Copy-Item -LiteralPath $Source -Destination $tmp -Force
  Protect-PathForCurrentUser $tmp
  Move-Item -LiteralPath $tmp -Destination $Destination -Force
  Protect-PathForCurrentUser $Destination
}

function Copy-ScriptAtomically {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  if (-not (Test-Path -LiteralPath $Source -PathType Leaf) -or (Test-ReparsePoint $Source)) {
    Fatal "source_missing" "Install source is not a regular file: $Source" "Run install from a real codex-auth-snap PowerShell script."
  }
  $dir = Split-Path -Parent $Destination
  Ensure-Directory $dir
  if (Test-ReparsePoint $Destination) {
    Fatal "symlink_refused" "Refusing to overwrite reparse point file: $Destination" "Rerun install --force only after you verify the link should be replaced."
  }
  $tmp = Join-Path $dir (".codex-auth-snap.tmp.{0}.ps1" -f [Guid]::NewGuid().ToString("N"))
  Copy-Item -LiteralPath $Source -Destination $tmp -Force
  Protect-PathForCurrentUser $tmp
  Move-Item -LiteralPath $tmp -Destination $Destination -Force
  Protect-PathForCurrentUser $Destination
}

function Get-SnapshotPath {
  param([Parameter(Mandatory = $true)][string]$Name)
  return (Join-Path $script:AccountsDir ("{0}.auth.json" -f $Name))
}

function Get-MetaPath {
  param([Parameter(Mandatory = $true)][string]$Name)
  return (Join-Path $script:MetaDir ("{0}.json" -f $Name))
}

function Get-HiddenAuthPath {
  param([Parameter(Mandatory = $true)][string]$Name)
  return (Join-Path $script:BeforeLoginDir ("active-hidden.{0}.json" -f $Name))
}

function Remove-BeforeLoginArtifacts {
  param([Parameter(Mandatory = $true)][string]$Name)
  Validate-AccountName $Name
  $hidden = Get-HiddenAuthPath $Name
  if (Test-Path -LiteralPath $hidden) {
    Refuse-ReparsePoint $hidden
    Remove-Item -LiteralPath $hidden -Force
  }
  $pattern = "auth.before-login.{0}.*.json" -f $Name
  foreach ($backup in @(Get-ChildItem -LiteralPath $script:BeforeLoginDir -Filter $pattern -File -Force -ErrorAction SilentlyContinue)) {
    Refuse-ReparsePoint $backup.FullName
    Remove-Item -LiteralPath $backup.FullName -Force
  }
}

function Read-TextFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Test-ReparsePoint $Path)) {
    return ""
  }
  return (Get-Content -LiteralPath $Path -Raw).TrimEnd("`r", "`n")
}

function Write-Current {
  param([Parameter(Mandatory = $true)][string]$Name)
  Write-SecureText $script:CurrentFile $Name
}

function Write-Pending {
  param([Parameter(Mandatory = $true)][string]$Name)
  Write-SecureText $script:PendingFile $Name
}

function Write-Meta {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$SavedFile
  )
  $hash = Get-FileSha256 $SavedFile
  $meta = [ordered]@{
    name = $Name
    saved_at = Get-NowIso
    source = $Source
    sha256 = $hash
    codex_home = $script:CodexHomeDir
  }
  Write-SecureText (Get-MetaPath $Name) (ConvertTo-CompactJson $meta)
}

function Write-InstallMeta {
  param(
    [Parameter(Mandatory = $true)][string]$InstallPath,
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$Hash
  )
  $meta = [ordered]@{
    installed_at = Get-NowIso
    install_path = $InstallPath
    source_path = $SourcePath
    version = $script:Version
    sha256 = $Hash
  }
  Write-SecureText $script:InstallMetaFile (ConvertTo-CompactJson $meta)
}

function Save-CurrentIfPossible {
  $current = Read-TextFile $script:CurrentFile
  if ([string]::IsNullOrWhiteSpace($current)) {
    return
  }
  if (-not (Test-AccountName $current)) {
    Warn "current account name is invalid; skipping active auth stash."
    return
  }
  if (-not (Test-Path -LiteralPath $script:AuthFile)) {
    return
  }
  if (-not (Test-AuthValidationStatus $script:AuthFile $script:Force)) {
    Warn "active auth.json is invalid or not a ChatGPT auth file; skipping active auth stash."
    return
  }
  $target = Get-SnapshotPath $current
  Copy-JsonAtomically $script:AuthFile $target
  Write-Meta $current $script:AuthFile $target
}

function Get-ConfigStoreValue {
  if (-not (Test-Path -LiteralPath $script:ConfigFile -PathType Leaf)) {
    return "missing"
  }
  $matches = @(Select-String -LiteralPath $script:ConfigFile -Pattern '^\s*cli_auth_credentials_store\s*=' -ErrorAction SilentlyContinue)
  if ($matches.Count -eq 0) {
    return "unset"
  }
  $line = $matches[$matches.Count - 1].Line
  if ($line -match '"file"') {
    return "file"
  }
  return "non_file"
}

function Set-ConfigFileBacked {
  Ensure-Directory $script:CodexHomeDir
  Refuse-ReparsePoint $script:ConfigFile
  if (-not (Test-Path -LiteralPath $script:ConfigFile)) {
    Write-SecureText $script:ConfigFile 'cli_auth_credentials_store = "file"'
    return
  }
  $state = Get-ConfigStoreValue
  if ($state -eq "file") {
    return
  }
  if ($state -eq "unset") {
    $existing = Get-Content -LiteralPath $script:ConfigFile -Raw
    Write-SecureText $script:ConfigFile ($existing.TrimEnd("`r", "`n") + [Environment]::NewLine + 'cli_auth_credentials_store = "file"')
    return
  }
  if (-not $script:Force) {
    Fatal "config_store_not_file" "config.toml is not configured for file-backed auth." "Rerun with --fix --force to update it non-interactively."
  }
  $lines = @(Get-Content -LiteralPath $script:ConfigFile)
  $newLines = New-Object System.Collections.Generic.List[string]
  $replaced = $false
  foreach ($line in $lines) {
    if ($line -match '^\s*cli_auth_credentials_store\s*=') {
      if (-not $replaced) {
        [void]$newLines.Add('cli_auth_credentials_store = "file"')
        $replaced = $true
      }
    } else {
      [void]$newLines.Add($line)
    }
  }
  if (-not $replaced) {
    [void]$newLines.Add('cli_auth_credentials_store = "file"')
  }
  Write-SecureText $script:ConfigFile ($newLines -join [Environment]::NewLine)
}

function Invoke-Init {
  Ensure-Dirs
  Acquire-Lock
  if ($script:FixConfig) {
    Set-ConfigFileBacked
  }
  $configState = Get-ConfigStoreValue
  if ($configState -ne "file") {
    if ($script:FixConfig) {
      Fatal "config_store_not_file" "config.toml is not configured for file-backed auth." "Inspect $script:ConfigFile, then rerun with --fix --force if safe."
    } else {
      Warn "config.toml is not configured for file-backed auth. Run: codex-auth-snap.ps1 init --fix"
    }
  }
  Write-Ok "Initialized codex-auth-snap." ([ordered]@{
    command = "init"
    codex_home = $script:CodexHomeDir
    snap_home = $script:SnapHomeDir
    switch_home = $script:SnapHomeDir
    config_state = $configState
  })
}

function Invoke-Install {
  $sourcePath = $script:ScriptPath
  $binDir = Get-SelectedInstallBinDir
  if ([string]::IsNullOrWhiteSpace($binDir)) {
    Fatal "missing_argument" "install target directory is empty." "Pass --bin-dir <dir> or --prefix <dir>."
  }
  $target = Join-Path $binDir "codex-auth-snap.ps1"
  if (Test-ReparsePoint $binDir) {
    Fatal "symlink_refused" "Refusing to install into reparse point directory: $binDir" "Use a real directory for the installed command."
  }
  Ensure-Directory $binDir
  Ensure-InstallStateDirs
  Acquire-Lock
  if (Test-ReparsePoint $target) {
    if (-not $script:Force) {
      Fatal "install_target_symlink" "Install target is a reparse point: $target" "Rerun install --force to replace it with a real copied script."
    }
    Remove-Item -LiteralPath $target -Force
  }
  if (Test-Path -LiteralPath $target) {
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
      Fatal "not_regular_file" "Install target is not a regular file: $target" "Choose another --bin-dir or remove the path after inspection."
    }
    if (-not (Test-LooksLikeCodexAuthSnap $target) -and -not $script:Force) {
      Fatal "install_target_exists" "Install target exists and does not look like codex-auth-snap: $target" "Use --force only if you want to replace this file."
    }
  }
  $sourceHash = Get-FileSha256 $sourcePath
  $alreadyCurrent = $false
  if ((Test-Path -LiteralPath $target -PathType Leaf) -and -not (Test-ReparsePoint $target)) {
    $targetHash = Get-FileSha256 $target
    if ($targetHash -eq $sourceHash) {
      $alreadyCurrent = $true
    }
  }
  if (-not $alreadyCurrent) {
    Copy-ScriptAtomically $sourcePath $target
  }
  Write-InstallMeta $target $sourcePath $sourceHash
  $text = if ($alreadyCurrent) { "codex-auth-snap is already installed: $target" } else { "Installed codex-auth-snap to: $target" }
  Write-Ok $text ([ordered]@{
    command = "install"
    install_path = $target
    version = $script:Version
    sha256_short = Get-ShortHash $sourceHash
    already_current = $alreadyCurrent
  })
}

function Invoke-Save {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) {
    Fatal "missing_argument" "save requires <name>." "Run codex-auth-snap.ps1 save <name>."
  }
  Ensure-Dirs
  Acquire-Lock
  Validate-AccountName $Name
  Validate-AuthFile $script:AuthFile $script:Force
  $target = Get-SnapshotPath $Name
  Copy-JsonAtomically $script:AuthFile $target
  Write-Current $Name
  Write-Meta $Name $script:AuthFile $target
  $hash = Get-FileSha256 $target
  $hasRefreshToken = Test-AuthHasRefreshToken $target
  Write-Ok "Saved current auth as: $Name" ([ordered]@{
    command = "save"
    name = $Name
    snapshot = $target
    sha256_short = Get-ShortHash $hash
    has_refresh_token = $hasRefreshToken
  })
}

function Invoke-Use {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) {
    Fatal "missing_argument" "use requires <name>." "Run codex-auth-snap.ps1 use <name>."
  }
  Ensure-Dirs
  Acquire-Lock
  Validate-AccountName $Name
  $target = Get-SnapshotPath $Name
  if (-not (Test-Path -LiteralPath $target)) {
    Fatal "snapshot_missing" "No saved auth snapshot for: $Name" "Run codex-auth-snap.ps1 list, or save/login this account first."
  }
  Validate-AuthFile $target $script:Force
  Save-CurrentIfPossible
  Copy-JsonAtomically $target $script:AuthFile
  Write-Current $Name
  $text = "Switched to: $Name" + [Environment]::NewLine + "Restart Codex CLI/App for the change to take effect."
  Write-Ok $text ([ordered]@{
    command = "use"
    name = $Name
    auth_file = $script:AuthFile
  })
}

function Invoke-BeginLogin {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) {
    Fatal "missing_argument" "begin-login requires <name>." "Run codex-auth-snap.ps1 begin-login <name>."
  }
  Ensure-Dirs
  Acquire-Lock
  Validate-AccountName $Name
  if ((Test-Path -LiteralPath $script:PendingFile -PathType Leaf) -and -not (Test-ReparsePoint $script:PendingFile)) {
    $pending = Read-TextFile $script:PendingFile
    Fatal "pending_exists" "A pending login already exists: $pending" "Run finish-login or abort-login before starting another login."
  }
  $hidden = Get-HiddenAuthPath $Name
  if (Test-Path -LiteralPath $hidden) {
    Fatal "stale_hidden" "A stale before-login hidden auth exists for: $Name" "Inspect or remove $hidden, then rerun begin-login."
  }
  $backup = ""
  if (Test-Path -LiteralPath $script:AuthFile) {
    Validate-AuthFile $script:AuthFile $script:Force
    Save-CurrentIfPossible
    $stamp = Get-NowStamp
    $backup = Join-Path $script:BeforeLoginDir ("auth.before-login.{0}.{1}.json" -f $Name, $stamp)
    if (Test-ReparsePoint $backup -or Test-ReparsePoint $hidden) {
      Fatal "symlink_refused" "Refusing to write before-login backup through reparse point." "Remove the link first."
    }
    Copy-Item -LiteralPath $script:AuthFile -Destination $backup -Force
    Protect-PathForCurrentUser $backup
    Move-Item -LiteralPath $script:AuthFile -Destination $hidden -Force
    Protect-PathForCurrentUser $hidden
  }
  Write-Pending $Name
  $text = "Run codex login for the target account." + [Environment]::NewLine +
    "Codex will open the login page. The account currently signed in to the browser does not decide which account gets saved." + [Environment]::NewLine +
    "After login completes, run:" + [Environment]::NewLine +
    "  codex-auth-snap.ps1 finish-login"
  Write-Ok $text ([ordered]@{
    command = "begin-login"
    name = $Name
    pending_file = $script:PendingFile
    hidden_auth = $hidden
    backup = $backup
  })
}

function Invoke-FinishLogin {
  param([string]$Name)
  Ensure-Dirs
  Acquire-Lock
  if ([string]::IsNullOrWhiteSpace($Name)) {
    $Name = Read-TextFile $script:PendingFile
  }
  if ([string]::IsNullOrWhiteSpace($Name)) {
    Fatal "pending_missing" "No pending login and no account name was provided." "Run codex-auth-snap.ps1 finish-login <name>, or start with begin-login."
  }
  Validate-AccountName $Name
  Validate-AuthFile $script:AuthFile $script:Force
  $target = Get-SnapshotPath $Name
  Copy-JsonAtomically $script:AuthFile $target
  Write-Current $Name
  Write-Meta $Name $script:AuthFile $target
  Remove-BeforeLoginArtifacts $Name
  if (Test-Path -LiteralPath $script:PendingFile) {
    Refuse-ReparsePoint $script:PendingFile
    Remove-Item -LiteralPath $script:PendingFile -Force
  }
  Write-Ok "Saved new login as: $Name" ([ordered]@{
    command = "finish-login"
    name = $Name
    snapshot = $target
  })
}

function Invoke-AbortLogin {
  Ensure-Dirs
  Acquire-Lock
  $pending = Read-TextFile $script:PendingFile
  if ([string]::IsNullOrWhiteSpace($pending)) {
    Fatal "pending_missing" "No pending login to abort." "Nothing needs to be aborted."
  }
  Validate-AccountName $pending
  if ((Test-Path -LiteralPath $script:AuthFile) -and -not $script:Force) {
    Fatal "active_exists" "Active auth.json already exists; refusing to overwrite it." "Rerun abort-login --force only if you want to replace active auth.json."
  }
  if ((Test-Path -LiteralPath $script:AuthFile) -and $script:Force) {
    Refuse-ReparsePoint $script:AuthFile
    Remove-Item -LiteralPath $script:AuthFile -Force
  }
  $hidden = Get-HiddenAuthPath $pending
  if (-not (Test-Path -LiteralPath $hidden)) {
    Fatal "hidden_missing" "No hidden active auth backup was found for: $pending" "Inspect $script:BeforeLoginDir and restore manually if needed."
  }
  Refuse-ReparsePoint $hidden
  Move-Item -LiteralPath $hidden -Destination $script:AuthFile -Force
  Protect-PathForCurrentUser $script:AuthFile
  Remove-Item -LiteralPath $script:PendingFile -Force
  Remove-BeforeLoginArtifacts $pending
  Write-Ok "Aborted pending login and restored previous active auth." ([ordered]@{
    command = "abort-login"
    restored = $script:AuthFile
    pending_name = $pending
  })
}

function Invoke-RemoveSnapshot {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) {
    Fatal "missing_argument" "remove requires <name>." "Run codex-auth-snap.ps1 remove <name>."
  }
  Ensure-Dirs
  Acquire-Lock
  Validate-AccountName $Name
  $snapshot = Get-SnapshotPath $Name
  $meta = Get-MetaPath $Name
  if (Test-ReparsePoint $snapshot -or Test-ReparsePoint $meta) {
    Fatal "symlink_refused" "Refusing to remove reparse point snapshot/meta for $Name." "Remove suspicious links manually after inspection."
  }
  Remove-Item -LiteralPath $snapshot, $meta -Force -ErrorAction SilentlyContinue
  $current = Read-TextFile $script:CurrentFile
  if ($current -eq $Name) {
    Remove-Item -LiteralPath $script:CurrentFile -Force -ErrorAction SilentlyContinue
    if ($script:ActiveToo -and (Test-Path -LiteralPath $script:AuthFile)) {
      Refuse-ReparsePoint $script:AuthFile
      Remove-Item -LiteralPath $script:AuthFile -Force
    }
  }
  $activeRemoved = ($current -eq $Name -and $script:ActiveToo)
  Write-Ok "Removed snapshot: $Name" ([ordered]@{
    command = "remove"
    name = $Name
    active_removed = $activeRemoved
  })
}

function Invoke-Current {
  $current = Read-TextFile $script:CurrentFile
  if ([string]::IsNullOrWhiteSpace($current)) {
    Write-Ok "(none)" ([ordered]@{ command = "current"; name = $null })
  } else {
    Write-Ok $current ([ordered]@{ command = "current"; name = $current })
  }
}

function Get-MetaField {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Field
  )
  try {
    $value = Get-JsonField $Path $Field
    if ($null -eq $value) {
      return ""
    }
    return [string]$value
  } catch {
    return ""
  }
}

function Invoke-List {
  Ensure-Dirs
  $current = Read-TextFile $script:CurrentFile
  $accounts = New-Object System.Collections.Generic.List[object]
  $textLines = New-Object System.Collections.Generic.List[string]
  foreach ($file in @(Get-ChildItem -LiteralPath $script:AccountsDir -Filter "*.auth.json" -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
    if (Test-ReparsePoint $file.FullName) {
      continue
    }
    $name = $file.Name -replace '\.auth\.json$', ''
    $meta = Get-MetaPath $name
    $savedAt = ""
    if ((Test-Path -LiteralPath $meta -PathType Leaf) -and -not (Test-ReparsePoint $meta)) {
      $savedAt = Get-MetaField $meta "saved_at"
    }
    $hash = Get-FileSha256 $file.FullName
    $short = Get-ShortHash $hash
    $isCurrent = ($name -eq $current)
    $prefix = if ($isCurrent) { "*" } else { " " }
    [void]$textLines.Add(("{0} {1}    saved {2}    sha256 {3}" -f $prefix, $name, $(if ([string]::IsNullOrWhiteSpace($savedAt)) { "unknown" } else { $savedAt }), $short))
    [void]$accounts.Add([ordered]@{
      name = $name
      current = $isCurrent
      saved_at = $savedAt
      sha256_short = $short
    })
  }
  $text = if ($textLines.Count -eq 0) { "(none)" } else { $textLines -join [Environment]::NewLine }
  Write-Ok $text ([ordered]@{
    command = "list"
    current = $current
    accounts = @($accounts)
  })
}

function Invoke-Paths {
  $installPath = Get-SelectedInstallPath
  $text = "CODEX_HOME:      $script:CodexHomeDir" + [Environment]::NewLine +
    "AUTH_FILE:       $script:AuthFile" + [Environment]::NewLine +
    "SNAP_HOME:       $script:SnapHomeDir" + [Environment]::NewLine +
    "ACCOUNTS_DIR:    $script:AccountsDir" + [Environment]::NewLine +
    "CURRENT_FILE:    $script:CurrentFile" + [Environment]::NewLine +
    "PENDING_FILE:    $script:PendingFile"
  Write-Ok $text ([ordered]@{
    command = "paths"
    codex_home = $script:CodexHomeDir
    auth_file = $script:AuthFile
    snap_home = $script:SnapHomeDir
    switch_home = $script:SnapHomeDir
    accounts_dir = $script:AccountsDir
    current_file = $script:CurrentFile
    pending_file = $script:PendingFile
    install_path = $installPath
  })
}

function Invoke-Version {
  Write-Ok $script:Version ([ordered]@{
    command = "version"
    version = $script:Version
  })
}

$script:Issues = New-Object System.Collections.Generic.List[object]
$script:DoctorErrors = 0

function Add-Issue {
  param(
    [Parameter(Mandatory = $true)][string]$Severity,
    [Parameter(Mandatory = $true)][string]$Code,
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$Path = ""
  )
  [void]$script:Issues.Add([ordered]@{
    severity = $Severity
    code = $Code
    message = $Message
    path = $Path
  })
  if ($Severity -eq "ERROR") {
    $script:DoctorErrors += 1
  }
}

function Test-CloudPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return ($Path -like "*iCloud Drive*" -or $Path -like "*Mobile Documents*" -or $Path -like "*Dropbox*" -or $Path -like "*Google Drive*" -or $Path -like "*OneDrive*")
}

function Test-CodexProcessRunning {
  try {
    $process = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(Codex|codex)$' } | Select-Object -First 1
    return ($null -ne $process)
  } catch {
    return $false
  }
}

function Invoke-Doctor {
  $script:Issues = New-Object System.Collections.Generic.List[object]
  $script:DoctorErrors = 0
  if (Test-ReparsePoint $script:CodexHomeDir) {
    Add-Issue "ERROR" "symlink_refused" "CODEX_HOME is a reparse point." $script:CodexHomeDir
  }
  if (Test-ReparsePoint $script:SnapHomeDir) {
    Add-Issue "ERROR" "symlink_refused" "snap home is a reparse point." $script:SnapHomeDir
  }
  if (Test-ReparsePoint $script:AuthFile) {
    Add-Issue "ERROR" "symlink_refused" "auth.json is a reparse point." $script:AuthFile
  }
  if (-not (Test-Path -LiteralPath $script:AuthFile -PathType Leaf)) {
    Add-Issue "WARN" "auth_missing" "auth.json does not exist." $script:AuthFile
  } elseif (-not (Test-ReparsePoint $script:AuthFile)) {
    try {
      [void](Read-JsonFile $script:AuthFile)
    } catch {
      Add-Issue "ERROR" "invalid_json" "auth.json is not valid JSON." $script:AuthFile
    }
  }
  $configState = Get-ConfigStoreValue
  if ($configState -ne "file") {
    Add-Issue "WARN" "config_not_file_backed" 'config.toml is not configured with cli_auth_credentials_store = "file".' $script:ConfigFile
  }
  foreach ($dir in @($script:SnapHomeDir, $script:AccountsDir, $script:MetaDir, $script:BeforeLoginDir)) {
    if (Test-ReparsePoint $dir) {
      Add-Issue "ERROR" "symlink_refused" "state directory is a reparse point." $dir
    }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
      Add-Issue "WARN" "state_dir_missing" "state directory is missing." $dir
    }
  }
  if ((Test-Path -LiteralPath $script:PendingFile -PathType Leaf) -and -not (Test-ReparsePoint $script:PendingFile)) {
    Add-Issue "WARN" "pending_login" "pending-login exists." $script:PendingFile
  } elseif (Test-ReparsePoint $script:PendingFile) {
    Add-Issue "ERROR" "symlink_refused" "pending-login is a reparse point." $script:PendingFile
  }
  if (Test-Path -LiteralPath $script:AccountsDir -PathType Container) {
    foreach ($file in @(Get-ChildItem -LiteralPath $script:AccountsDir -Filter "*.auth.json" -Force -ErrorAction SilentlyContinue)) {
      if (Test-ReparsePoint $file.FullName) {
        Add-Issue "ERROR" "symlink_refused" "auth snapshot is a reparse point." $file.FullName
        continue
      }
      if ($file.PSIsContainer) {
        continue
      }
      try {
        [void](Read-JsonFile $file.FullName)
      } catch {
        Add-Issue "ERROR" "invalid_json" "auth snapshot is not valid JSON." $file.FullName
      }
    }
  }
  if (Test-Path -LiteralPath $script:MetaDir -PathType Container) {
    foreach ($file in @(Get-ChildItem -LiteralPath $script:MetaDir -Filter "*.json" -File -Force -ErrorAction SilentlyContinue)) {
      if (Test-ReparsePoint $file.FullName) {
        Add-Issue "ERROR" "symlink_refused" "state file is a reparse point." $file.FullName
      }
    }
  }
  if (Test-ReparsePoint $script:CurrentFile) {
    Add-Issue "ERROR" "symlink_refused" "state file is a reparse point." $script:CurrentFile
  }
  if (Test-CloudPath $script:SnapHomeDir) {
    Add-Issue "WARN" "cloud_synced_path" "auth snapshots are stored under a cloud-synced-looking path." $script:SnapHomeDir
  }
  if (Test-CodexProcessRunning) {
    Add-Issue "WARN" "codex_running" "Codex App/CLI appears to be running; restart it after switching." ""
  }

  $installPath = Get-SelectedInstallPath
  if ((Test-Path -LiteralPath $script:InstallMetaFile -PathType Leaf) -and -not (Test-ReparsePoint $script:InstallMetaFile) -and [string]::IsNullOrWhiteSpace($script:InstallBinDir) -and [string]::IsNullOrWhiteSpace($script:InstallPrefix)) {
    $metaInstallPath = Get-MetaField $script:InstallMetaFile "install_path"
    if (-not [string]::IsNullOrWhiteSpace($metaInstallPath)) {
      $installPath = $metaInstallPath
    }
  }
  $installStatus = "missing"
  $installedVersion = ""
  $installedHash = ""
  $sourcePath = $script:ScriptPath
  $sourceHash = ""
  if ((Test-Path -LiteralPath $sourcePath -PathType Leaf) -and -not (Test-ReparsePoint $sourcePath)) {
    $sourceHash = Get-FileSha256 $sourcePath
  }
  if (Test-ReparsePoint $installPath) {
    $installStatus = "symlink"
    Add-Issue "WARN" "installed_path_symlink" "installed codex-auth-snap is a reparse point; run install --force to replace it with a copied script." $installPath
  } elseif (-not (Test-Path -LiteralPath $installPath)) {
    Add-Issue "WARN" "installed_missing" "installed codex-auth-snap was not found; run codex-auth-snap.ps1 install if you want a stable path outside this checkout." $installPath
  } elseif (-not (Test-Path -LiteralPath $installPath -PathType Leaf)) {
    $installStatus = "not_regular"
    Add-Issue "WARN" "installed_not_regular" "installed codex-auth-snap path is not a regular file." $installPath
  } elseif (-not (Test-LooksLikeCodexAuthSnap $installPath)) {
    $installStatus = "unknown"
    Add-Issue "WARN" "installed_unknown" "installed path does not look like codex-auth-snap." $installPath
  } else {
    $installStatus = "ok"
    $installedVersion = Get-CliVersionFromFile $installPath
    $installedHash = Get-FileSha256 $installPath
    if ($installedVersion -ne $script:Version) {
      $installStatus = "version_mismatch"
      Add-Issue "WARN" "installed_version_mismatch" "installed codex-auth-snap version $installedVersion differs from current $script:Version; rerun install." $installPath
    } elseif (-not [string]::IsNullOrWhiteSpace($sourceHash) -and $installedHash -ne $sourceHash -and $installPath -ne $sourcePath) {
      $installStatus = "hash_mismatch"
      Add-Issue "WARN" "installed_hash_mismatch" "installed codex-auth-snap differs from the current script even though the version matches; rerun install." $installPath
    }
  }
  $ok = ($script:DoctorErrors -eq 0)
  $result = [ordered]@{
    command = "doctor"
    version = $script:Version
    ok = $ok
    config_state = $configState
    paths = [ordered]@{
      codex_home = $script:CodexHomeDir
      auth_file = $script:AuthFile
      snap_home = $script:SnapHomeDir
      switch_home = $script:SnapHomeDir
    }
    installation = [ordered]@{
      path = $installPath
      status = $installStatus
      current_version = $script:Version
      installed_version = $installedVersion
      source_sha256_short = Get-ShortHash $sourceHash
      installed_sha256_short = Get-ShortHash $installedHash
    }
    issues = @($script:Issues)
  }
  if ($script:DoctorErrors -gt 0) {
    if ($script:JsonOutput) {
      $envelope = [ordered]@{
        content = @([ordered]@{ type = "text"; text = "codex-auth-snap doctor found errors." })
        structuredContent = [ordered]@{
          result = $result
          error = [ordered]@{
            code = "doctor_failed"
            message = "doctor found local safety errors"
            retryable = $true
            field_errors = @()
            suggested_fix = "Inspect structuredContent.result.issues and fix ERROR entries."
          }
        }
        isError = $true
      }
      ConvertTo-CompactJson $envelope
    } else {
      [Console]::Error.WriteLine("ERROR: doctor found local safety errors")
      foreach ($issue in $script:Issues) {
        [Console]::Error.WriteLine((ConvertTo-CompactJson $issue))
      }
    }
    throw $script:FatalMarker
  }
  Write-Ok "codex-auth-snap doctor OK." $result
}

function Parse-Args {
  param([string[]]$InputArgs)
  $script:Positionals.Clear()
  for ($i = 0; $i -lt $InputArgs.Count; $i++) {
    $arg = $InputArgs[$i]
    if ($arg -eq "--json") {
      $script:JsonOutput = $true
    } elseif ($arg -eq "--force") {
      $script:Force = $true
    } elseif ($arg -eq "--fix") {
      $script:FixConfig = $true
    } elseif ($arg -eq "--active-too") {
      $script:ActiveToo = $true
    } elseif ($arg -eq "--prefix") {
      $i += 1
      if ($i -ge $InputArgs.Count) {
        Fatal "missing_argument" "--prefix requires a directory." "Pass --prefix <dir>."
      }
      $script:InstallPrefix = $InputArgs[$i]
    } elseif ($arg.StartsWith("--prefix=")) {
      $script:InstallPrefix = $arg.Substring("--prefix=".Length)
    } elseif ($arg -eq "--bin-dir") {
      $i += 1
      if ($i -ge $InputArgs.Count) {
        Fatal "missing_argument" "--bin-dir requires a directory." "Pass --bin-dir <dir>."
      }
      $script:InstallBinDir = $InputArgs[$i]
    } elseif ($arg.StartsWith("--bin-dir=")) {
      $script:InstallBinDir = $arg.Substring("--bin-dir=".Length)
    } elseif ($arg -eq "--version") {
      Write-Output $script:Version
      exit 0
    } elseif ($arg -eq "-h" -or $arg -eq "--help") {
      Show-Usage
      exit 0
    } else {
      [void]$script:Positionals.Add($arg)
    }
  }
}

function Invoke-CodexAuthSnap {
  param([string[]]$InputArgs)
  Parse-Args $InputArgs
  $command = ""
  $commandArgs = @()
  if ($script:Positionals.Count -gt 0) {
    $command = $script:Positionals[0]
  }
  if ($script:Positionals.Count -gt 1) {
    $commandArgs = @($script:Positionals.ToArray()[1..($script:Positionals.Count - 1)])
  }
  switch ($command) {
    "init" { Invoke-Init }
    "save" { Invoke-Save @commandArgs }
    "use" { Invoke-Use @commandArgs }
    "begin-login" { Invoke-BeginLogin @commandArgs }
    "finish-login" { Invoke-FinishLogin @commandArgs }
    "abort-login" { Invoke-AbortLogin }
    "install" { Invoke-Install }
    "list" { Invoke-List }
    "current" { Invoke-Current }
    "remove" { Invoke-RemoveSnapshot @commandArgs }
    "doctor" { Invoke-Doctor }
    "paths" { Invoke-Paths }
    "version" { Invoke-Version }
    "" { Show-Usage }
    default { Fatal "unknown_command" "Unknown command: $command" "Run codex-auth-snap.ps1 --help." }
  }
}

$exitCode = 0
try {
  Invoke-CodexAuthSnap $CliArgs
} catch {
  if ($_.Exception.Message -ne $script:FatalMarker) {
    Write-ErrorEnvelope "unexpected_error" $_.Exception.Message "Inspect the local files and rerun with --json for structured output." $false
  }
  $exitCode = 1
} finally {
  Release-Lock
}
exit $exitCode
