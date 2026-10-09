# Screenshot the concept page in headless Chrome and print any JS errors (they also show in red at the top of the shot).
# Usage: shot.ps1 -Only skin -Hold 60 -Sim 2 -H 40 -Out skin60.png
param([string]$Only = '', [int]$Hold = 60, [double]$Sim = 2, [int]$H = 40, [int]$W = 420, [string]$Out = 'shot.png', [string]$Extra = '')
$dir = $PSScriptRoot
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$url = 'file:///' + $dir.Replace([char]92, [char]47) + "/index.html?only=$Only&hold=$Hold&sim=$Sim&h=$H&w=$W" + $(if ($Extra) { "&$Extra" } else { '' })
$outPath = Join-Path $dir $Out
$tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
$prof = Join-Path $dir ".chrome-$tag"; $domFile = Join-Path $dir ".dom-$tag.txt"
$common = @('--headless=new', '--disable-gpu', '--hide-scrollbars', "--user-data-dir=$prof", '--virtual-time-budget=1500')
Start-Process -Wait -NoNewWindow -FilePath $chrome -ArgumentList ($common + @('--window-size=1000,1100', "--screenshot=$outPath", $url)) -RedirectStandardError "$domFile.err"
Start-Process -Wait -NoNewWindow -FilePath $chrome -ArgumentList ($common + @('--dump-dom', $url)) -RedirectStandardOutput $domFile -RedirectStandardError "$domFile.err"
$dom = Get-Content -Raw $domFile
Remove-Item -Recurse -Force $prof, $domFile, "$domFile.err" -ErrorAction SilentlyContinue
if ($dom -match '<div id="errors">([^<]*)</div>') { if ($Matches[1].Trim()) { Write-Host "JS ERRORS: $($Matches[1])" } else { Write-Host 'no JS errors' } } else { Write-Host 'could not read the page' }
Write-Host "Screenshot: $outPath"
