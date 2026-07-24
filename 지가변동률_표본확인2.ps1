# 지가변동률 표본 확인 2 — 효율적 다운로드 방법 확인용 (A_2024_00007 전용)
# - 목적: 매일 자동갱신을 가볍게 하기 위해 ①지역 필터(GRP_ID) ②기간 필터(START/END_WRTTIME)가
#         먹는지, ③최신 공표월이 언제인지 확인. (본 다운로드 코드 설계 근거)
# - 사용법: 저장소 루트에서  powershell -ExecutionPolicy Bypass -File .\지가변동률_표본확인2.ps1
# - 결과는 '지가변동률_표본결과2.txt'로 저장됨 → 붙여넣어 주세요. 읽기 전용.

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$outFile = Join-Path $root "지가변동률_표본결과2.txt"
$script:logLines = New-Object System.Collections.ArrayList
function Log($msg, $color) { [void]$script:logLines.Add([string]$msg); if ($color) { Write-Host $msg -ForegroundColor $color } else { Write-Host $msg } }

$apiKey = $env:RONE_API_KEY
if (-not $apiKey) { $kf = Join-Path $root "arap_apikey.local.txt"; if (Test-Path $kf) { $apiKey = (Get-Content $kf -Raw).Trim() } }
if (-not $apiKey) { Write-Host "API 키 없음 (RONE_API_KEY / arap_apikey.local.txt)" -ForegroundColor Red; exit 1 }

$apiBase = "https://www.reb.or.kr/r-one/openapi/SttsApiTblData.do"
$SID = "A_2024_00007"
function Invoke-Rone($url) {
  $a = 0; while ($true) { $a++; try { return Invoke-RestMethod -Uri $url -TimeoutSec 60 } catch { if ($a -ge 4) { throw }; Start-Sleep -Seconds ([math]::Min(8,[math]::Pow(2,$a))) } }
}
function Get-Rows($dj) { if ($dj.SttsApiTblData -and @($dj.SttsApiTblData).Count -ge 2) { return $dj.SttsApiTblData[1].row }; return $null }
function Describe($rows, $label) {
  if (-not $rows) { Log ("    [{0}] 데이터 없음(null)" -f $label) Yellow; return }
  $rows = @($rows)
  $grp = @($rows | ForEach-Object { $_.GRP_FULLNM } | Where-Object { $_ } | Select-Object -Unique)
  $cls = @($rows | ForEach-Object { $_.CLS_NM }     | Where-Object { $_ } | Select-Object -Unique)
  $tim = @($rows | ForEach-Object { [string]$_.WRTTIME_IDTFR_ID } | Where-Object { $_ } | Sort-Object)
  Log ("    [{0}] {1}행 · 지역(GRP)고유 {2}개 · 용도지역(CLS) {3}종 [{4}] · 월 {5}~{6}" -f `
        $label, $rows.Count, $grp.Count, $cls.Count, (($cls) -join "/"), $tim[0], $tim[-1])
  if ($grp.Count -le 6) { Log ("        지역표본: " + (($grp | Select-Object -First 6) -join ", ")) }
}

Log "==== A_2024_00007 (월) 용도지역별 지가변동률 — 효율적 수신 방법 확인 ====" Cyan

# 기준: 필터 없이 1페이지 (비교군)
Log "1) 필터 없음 (pSize=1000, pIndex=1)"
try { Describe (Get-Rows (Invoke-Rone ("{0}?STATBL_ID={1}&DTACYCLE_CD=MM&Type=json&pIndex=1&pSize=1000&KEY={2}" -f $apiBase,$SID,$apiKey))) "no-filter" }
catch { Log ("    호출실패: {0}" -f $_) Yellow }

# 2) 지역 필터 GRP_ID (대구>중구 = 910064)  → 한 지역만 나오면 지역단위 수신 가능
Log "2) GRP_ID=910064 (대구>중구) 필터"
try { Describe (Get-Rows (Invoke-Rone ("{0}?STATBL_ID={1}&DTACYCLE_CD=MM&GRP_ID=910064&Type=json&pIndex=1&pSize=1000&KEY={2}" -f $apiBase,$SID,$apiKey))) "GRP_ID" }
catch { Log ("    호출실패: {0}" -f $_) Yellow }

# 3) 기간 필터 START/END_WRTTIME  → 최근 몇 년만 받기 가능한지
Log "3) START_WRTTIME=202401 & END_WRTTIME=202412 필터"
try { Describe (Get-Rows (Invoke-Rone ("{0}?STATBL_ID={1}&DTACYCLE_CD=MM&START_WRTTIME=202401&END_WRTTIME=202412&Type=json&pIndex=1&pSize=1000&KEY={2}" -f $apiBase,$SID,$apiKey))) "START/END_WRTTIME" }
catch { Log ("    호출실패: {0}" -f $_) Yellow }

# 4) 지역+기간 동시 (대구 중구, 2024년) → 이 조합이 되면 지역×연도 단위로 잘게 받을 수 있음
Log "4) GRP_ID=910064 + START/END_WRTTIME=2024"
try { Describe (Get-Rows (Invoke-Rone ("{0}?STATBL_ID={1}&DTACYCLE_CD=MM&GRP_ID=910064&START_WRTTIME=202401&END_WRTTIME=202412&Type=json&pIndex=1&pSize=1000&KEY={2}" -f $apiBase,$SID,$apiKey))) "GRP_ID+기간" }
catch { Log ("    호출실패: {0}" -f $_) Yellow }

# 5) 최신 공표월 확인: GRP_ID 필터가 되면 한 지역 전체를 받아 최대 WRTTIME 확인 (여러 페이지)
Log "5) 대구>중구 전체 페이지 스캔 → 최신 공표월/지역당 행수"
try {
  $acc = New-Object System.Collections.ArrayList
  for ($pg=1; $pg -le 10; $pg++) {
    $rows = Get-Rows (Invoke-Rone ("{0}?STATBL_ID={1}&DTACYCLE_CD=MM&GRP_ID=910064&Type=json&pIndex={2}&pSize=1000&KEY={3}" -f $apiBase,$SID,$pg,$apiKey))
    if (-not $rows) { break }
    foreach ($r in @($rows)) { [void]$acc.Add($r) }
    if (@($rows).Count -lt 1000) { break }
  }
  Describe $acc "대구중구-전체"
  $latest = @($acc | ForEach-Object { [string]$_.WRTTIME_IDTFR_ID } | Sort-Object | Select-Object -Last 1)
  Log ("    ★ 최신 공표월 = {0}" -f $latest) Green
} catch { Log ("    호출실패: {0}" -f $_) Yellow }

Log "==== 끝. '지가변동률_표본결과2.txt' 저장됨 — 붙여넣어 주세요. ====" Cyan
($script:logLines -join "`r`n") | Set-Content -Encoding UTF8 $outFile
