<#
.SYNOPSIS
  Installs the optional dev tools the kit uses, from their official sources only.

.DESCRIPTION
  luacheck   lunarmodules/luacheck official GitHub release (v1.2.0, luacheck.exe).
             https://github.com/lunarmodules/luacheck/releases
             Installed to %LOCALAPPDATA%\wow-addon-kit\bin (no admin, nothing on PATH changed).
  API index  Blizzard's generated API docs for WoW: Forever (Gethe/wow-ui-source, branch "forever").
  VS Code    Prints the command for the "WoW API" extension (ketho.wow-api, built on LuaLS);
             it is not installed automatically.

.EXAMPLE
  .\Install-WowDevTools.ps1
  .\Install-WowDevTools.ps1 -SkipApiIndex
#>
[CmdletBinding()]
param(
	[string]$LuacheckVersion = 'v1.2.0',
	[switch]$SkipApiIndex,
	[switch]$Force
)

Import-Module (Join-Path $PSScriptRoot 'WowKit.psm1') -Force
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- luacheck ---
$bin = Get-WowKitToolDir
$exe = Join-Path $bin 'luacheck.exe'
if ((Test-Path $exe) -and -not $Force) {
	Write-Host "luacheck already installed: $exe"
} else {
	New-Item -ItemType Directory -Force -Path $bin | Out-Null
	$rel = Invoke-RestMethod "https://api.github.com/repos/lunarmodules/luacheck/releases/tags/$LuacheckVersion" -Headers @{ 'User-Agent' = 'wow-forever-addons-plugin' }
	$asset = $rel.assets | Where-Object name -eq 'luacheck.exe'
	if (-not $asset) { throw "Release $LuacheckVersion has no luacheck.exe asset." }
	Write-Host "Downloading $($asset.browser_download_url)"
	Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $exe
	if ((Get-Item $exe).Length -ne $asset.size) { Remove-Item $exe; throw 'Download size does not match the release asset; removed.' }
	Write-Host ("luacheck installed: {0}  (SHA256 {1})" -f $exe, (Get-FileHash $exe -Algorithm SHA256).Hash)
}
& $exe --version

# --- Forever API index ---
if (-not $SkipApiIndex) {
	$idx = Join-Path (Get-WowKitRoot) 'data\api-forever.json'
	if ((Test-Path $idx) -and -not $Force -and ((Get-Date) - (Get-Item $idx).LastWriteTime).TotalDays -lt 7) {
		Write-Host "Forever API index is fresh: $idx"
	} else {
		& (Join-Path $PSScriptRoot 'Update-WowApiIndex.ps1') -Branch forever
	}
}

# --- Editor ---
Write-Host ''
Write-Host 'Recommended editor setup (optional):' -ForegroundColor Cyan
Write-Host '  code --install-extension ketho.wow-api   # WoW API IntelliSense for VS Code (LuaLS)'
