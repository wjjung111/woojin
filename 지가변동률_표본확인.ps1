# 지가변동률 표본 확인 스크립트 (A안 착수 전 구조 확인용)
# - 목적: R-ONE 전국지가변동률조사 통계표가 ①용도지역별(주거/상업/공업/녹지…) 구분을 주는지
#         ②지역(시군구) 코드 구조 ③월별 값·누계 형태가 어떤지 눈으로 확인.
# - 사용법: 이 파일을 저장소 루트(arap_apikey.local.txt 있는 폴더)에 두고 PowerShell에서 실행.
#           PowerShell 창에서:  powershell -ExecutionPolicy Bypass -File .\지가변동률_표본확인.ps1
# - 결과는 화면에 뜨고 '지가변동률_표본결과.txt'로도 저장됨 → 그 파일 내용을 저에게 붙여넣어 주시면 됩니다.
# - 이 스크립트는 아무것도 안 바꿉니다(읽기 전용). arap_index_data.js 등 기존 파일 손대지 않음.

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$outFile = Join-Path $root "지가변동률_표본결과.txt"

# 화면 + 파일 동시 기록
$script:logLines = New-Object System.Collections.ArrayList
function Log($msg, $color) {
  [void]$script:logLines.Add([string]$msg)
  if ($color) { Write-Host $msg -ForegroundColor $color } else { Write-Host $msg }
}

# API 키: arap_launch.ps1과 동일하게 환경변수 → 로컬파일 순으로 읽음
$apiKey = $env:RONE_API_KEY
if (-not $apiKey) {
  $keyFile = Join-Path $root "arap_apikey.local.txt"
  if (Test-Path $keyFile) { $apiKey = (Get-Content $keyFile -Raw).Trim() }
}
if (-not $apiKey) {
  Write-Host "API 키가 없습니다. 환경변수 RONE_API_KEY 또는 같은 폴더 arap_apikey.local.txt 를 확인하세요." -ForegroundColor Red
  exit 1
}

$apiBase  = "https://www.reb.or.kr/r-one/openapi/SttsApiTblData.do"
$listBase = "https://www.reb.or.kr/r-one/openapi/SttsApiTbl.do"

function Invoke-Rone($url) {
  $attempt = 0
  while ($true) {
    $attempt++
    try { return Invoke-RestMethod -Uri $url -TimeoutSec 60 }
    catch {
      if ($attempt -ge 4) { throw }
      Start-Sleep -Seconds ([math]::Min(8, [math]::Pow(2, $attempt)))
    }
  }
}

# ── 1) 통계목록에서 '지가변동률' 관련 통계표 자동 탐색 ─────────────────────────
Log "==== 1) 지가변동률 통계표 탐색 ====" Cyan
$lurl = "{0}?Type=json&pIndex=1&pSize=1000&KEY={1}" -f $listBase, $apiKey
$lj = Invoke-Rone $lurl
$all = $lj.SttsApiTbl[1].row
if (-not $all) { Log "통계목록이 비어있음 — 키/네트워크 확인" Red; ($script:logLines -join "`r`n") | Set-Content -Encoding UTF8 $outFile; exit 1 }

# 이름에 '지가변동' 이 들어간 표를 모두 나열 (누가 용도지역별인지 이름/주기로 판단)
$cands = @($all | Where-Object { $_.STATBL_NM -match "지가변동" })
Log ("  '지가변동' 포함 통계표 {0}건:" -f $cands.Count)
foreach ($c in $cands) {
  Log ("    [{0}] {1}  (주기:{2})" -f $c.STATBL_ID, $c.STATBL_NM, $c.DTACYCLE_NM)
}
if ($cands.Count -eq 0) {
  Log "  '지가변동' 표를 못 찾음 → '지가' 로 넓혀서 재탐색:" Yellow
  $cands = @($all | Where-Object { $_.STATBL_NM -match "지가" })
  foreach ($c in $cands) { Log ("    [{0}] {1}  (주기:{2})" -f $c.STATBL_ID, $c.STATBL_NM, $c.DTACYCLE_NM) }
}

# ── 2) 후보 표들의 실제 데이터 구조 확인 (용도지역 구분·지역코드·월별값) ──────
# 월별(MM) 우선 시도, 비면 무주기로 재시도. 각 표에서 앞부분 몇 행만 떠서 구조 파악.
Log ""
Log "==== 2) 각 후보 표의 데이터 구조 표본 ====" Cyan
$maxTables = [math]::Min(6, $cands.Count)   # 후보가 많으면 앞 6개만
for ($i = 0; $i -lt $maxTables; $i++) {
  $c = $cands[$i]
  Log ""
  Log ("── [{0}] {1} ─────────────" -f $c.STATBL_ID, $c.STATBL_NM) Green
  $rows = $null
  foreach ($cyc in @("MM", "", "YY")) {
    $cycParam = if ($cyc) { "&DTACYCLE_CD=$cyc" } else { "" }
    $durl = "{0}?STATBL_ID={1}{2}&Type=json&pIndex=1&pSize=1000&KEY={3}" -f $apiBase, $c.STATBL_ID, $cycParam, $apiKey
    try { $dj = Invoke-Rone $durl } catch { Log ("    (주기 '{0}' 호출 실패)" -f $cyc) Yellow; continue }
    $r = if ($dj.SttsApiTblData -and @($dj.SttsApiTblData).Count -ge 2) { $dj.SttsApiTblData[1].row } else { $null }
    if ($r) { $rows = $r; Log ("    (주기 '{0}' 로 데이터 있음, 이 페이지 {1}행)" -f $cyc, @($r).Count); break }
  }
  if (-not $rows) { Log "    데이터를 못 받음(주기 MM/무/YY 모두 비어있음)" Yellow; continue }

  # 첫 행 전체 필드 덤프 → 어떤 컬럼이 있는지 확인
  $r0 = @($rows)[0]
  Log "    [첫 행 전체 필드]"
  Log ("      " + (($r0 | ConvertTo-Json -Depth 3 -Compress)))

  # ITM_NM(항목) 고유값 — 여기에 용도지역(주거/상업/공업/녹지)이 들어있을 가능성
  $itms = @($rows | ForEach-Object { $_.ITM_NM } | Where-Object { $_ } | Select-Object -Unique)
  Log ("    [ITM_NM 고유값 {0}개]  {1}" -f $itms.Count, (($itms | Select-Object -First 30) -join " | "))

  # CLS_FULLNM(분류 전체경로) 표본 — 지역(시군구)/용도지역이 여기 계층으로 들어있을 가능성
  $cls = @($rows | ForEach-Object { $_.CLS_FULLNM } | Where-Object { $_ } | Select-Object -Unique)
  Log ("    [CLS_FULLNM 고유값 {0}개, 앞 20개]" -f $cls.Count)
  foreach ($x in ($cls | Select-Object -First 20)) { Log ("      · {0}" -f $x) }

  # 시점(WRTTIME) 범위
  $times = @($rows | ForEach-Object { [string]$_.WRTTIME_IDTFR_ID } | Where-Object { $_ } | Sort-Object)
  if ($times.Count) { Log ("    [WRTTIME 범위]  최소 {0} ~ 최대 {1} (표본 {2}개)" -f $times[0], $times[-1], $times.Count) }
}

Log ""
Log "==== 끝. 위 내용을 '지가변동률_표본결과.txt' 로 저장했습니다. 그 파일을 붙여넣어 주세요. ====" Cyan
($script:logLines -join "`r`n") | Set-Content -Encoding UTF8 $outFile
