# EXACT(구 ARAP) 실행 + 부동산원(R-ONE) 매매가격지수 자동 수신
# - 'EXACT 실행.bat'이 이 파일을 호출한다. 직접 실행해도 된다.
# - 지수 데이터(arap_index_data.js)가 없으면: 먼저 받고 앱을 연다.
# - 있으면: 앱을 먼저 열고, 하루 이상 지난 경우 백그라운드로 새로 받는다.
param([switch]$FetchOnly)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataFile = Join-Path $root "arap_index_data.js"
$htmlFile = Join-Path $root "exact_집합건물v1.0.html"
# API 키는 저장소(공개)에 올리지 않는다 — 환경변수 RONE_API_KEY 또는 로컬파일 arap_apikey.local.txt에서 읽음.
# 두 곳 다 없으면 지수 수신만 생략, 앱은 기존 데이터로 정상 작동.
$apiKey = $env:RONE_API_KEY
if (-not $apiKey) {
  $keyFile = Join-Path $root "arap_apikey.local.txt"
  if (Test-Path $keyFile) { $apiKey = (Get-Content $keyFile -Raw).Trim() }
}
$apiBase  = "https://www.reb.or.kr/r-one/openapi/SttsApiTblData.do"
$listBase = "https://www.reb.or.kr/r-one/openapi/SttsApiTbl.do"   # 통계목록(자본수익률 표 자동탐색용)

# 서울 지역코드 (R-ONE CLS_ID, 2026-07 확인 — 통계코드는 고정값)
# 아파트(A_2024_00045)는 구 단위까지, 연립다세대(A_2024_00080)는 권역 단위까지만 공표됨
$tables = [ordered]@{
  "아파트" = @{
    id  = "A_2024_00045"
    cls = @(500008,510009,510010,520010,520011,520012,520014,520015,
            530011,530012,530013,530015,530016,530017,530018,530019,530020,530021,530022,
            530024,530025,530026,530029,530030,530031,530032,530033,530034,530035,
            530037,530038,530039,530040)
  }
  "연립다세대" = @{
    id  = "A_2024_00080"
    cls = @(500008,510009,510010,520010,520011,520012,520014,520015)
  }
}

# 비주거용(상업용) 시점수정용 — 상업용부동산 임대동향조사 '자본수익률'(분기)을 자동수신.
# 통계표 ID를 하드코딩하지 않고 통계목록(SttsApiTbl)에서 이름으로 자동탐색한다(오탐 방지·유지보수 용이).
# 결과 구조: capReturn.types.{유형}.regions.{지역}.{YYYYQ} = 자본수익률(%, 예 0.56). 앱 buildNrCapText가 /100 하여 복리산식에 사용.
# ※ 앱은 이 데이터가 없어도 정상 동작(자동계산만 비활성) → 실패해도 매매지수는 그대로 저장한다.
function Get-CapType($nm) {
  if ($nm -match "집합")   { return "집합상가" }
  if ($nm -match "중대형") { return "중대형상가" }
  if ($nm -match "소규모") { return "소규모상가" }
  if ($nm -match "오피스텔") { return $null }      # 오피스텔은 주택계열 — 상업용 자본수익률 아님
  if ($nm -match "오피스") { return "오피스" }
  return $null
}
function ConvertTo-QKey($w) {
  $s = [string]$w
  if ($s -match '^(\d{4})[Qq]?0?([1-4])$')      { return "$($matches[1])$($matches[2])" }   # 20261 / 2026Q1 / 2026Q01
  if ($s -match '^(\d{4})(0[1-9]|1[0-2])$')      { $mm=[int]$matches[2]; $q=[math]::Ceiling($mm/3.0); return "$($matches[1])$q" }  # 202603(분기말월)→20261
  return $null
}
function Fetch-CapReturn {
  Write-Host "상업용부동산 자본수익률(분기) 수신 중..." -ForegroundColor Cyan
  try {
    $lurl = "{0}?Type=json&pIndex=1&pSize=1000&KEY={1}" -f $listBase, $apiKey
    $lj = Invoke-RestMethod -Uri $lurl -TimeoutSec 30
    $all = $lj.SttsApiTbl[1].row
  } catch { Write-Host "  통계목록 조회 실패(자본수익률 생략): $_" -ForegroundColor Yellow; return $null }
  if (-not $all) { Write-Host "  통계목록 비어있음 — 자본수익률 생략"; return $null }
  $cands = @($all | Where-Object { $_.STATBL_NM -match "자본수익률" })
  Write-Host ("  '자본수익률' 통계표 후보 {0}건" -f $cands.Count)
  foreach ($c in $cands) { Write-Host ("    [{0}] {1} ({2})" -f $c.STATBL_ID, $c.STATBL_NM, $c.DTACYCLE_NM) }
  $types = [ordered]@{}
  foreach ($c in $cands) {
    $kind = Get-CapType $c.STATBL_NM
    if (-not $kind -or $types.Contains($kind)) { continue }   # 유형별 첫 표만
    $cyc = if ($c.DTACYCLE_CD) { [string]$c.DTACYCLE_CD } else { "QY" }
    try {
      $durl = "{0}?STATBL_ID={1}&DTACYCLE_CD={2}&Type=json&pIndex=1&pSize=1000&KEY={3}" -f $apiBase, $c.STATBL_ID, $cyc, $apiKey
      $dj = Invoke-RestMethod -Uri $durl -TimeoutSec 30
      $rows = $dj.SttsApiTblData[1].row
    } catch { Write-Host ("    {0} 데이터 실패: {1}" -f $kind, $_) -ForegroundColor Yellow; continue }
    if (-not $rows) { Write-Host ("    {0} 자료없음" -f $kind); continue }
    $regions = [ordered]@{}
    $latest = ""
    foreach ($r in $rows) {
      if ($r.ITM_NM -and ($r.ITM_NM -notmatch "자본수익률")) { continue }   # 한 표에 여러 항목이 섞인 경우 자본수익률만
      $q = ConvertTo-QKey $r.WRTTIME_IDTFR_ID
      if (-not $q) { continue }
      $reg = if ($r.CLS_NM) { [string]$r.CLS_NM } elseif ($r.CLS_FULLNM) { ([string]$r.CLS_FULLNM -split ">")[-1] } else { "전국" }
      $reg = $reg.Trim()
      if (-not $regions.Contains($reg)) { $regions[$reg] = [ordered]@{} }
      $regions[$reg][$q] = [math]::Round([double]$r.DTA_VAL, 2)   # 공표 자본수익률(%)은 소수 2자리
      if ($q -gt $latest) { $latest = $q }
    }
    if ($regions.Count -eq 0) { continue }
    $types[$kind] = [ordered]@{ statblId = [string]$c.STATBL_ID; latest = $latest; regions = $regions }
    Write-Host ("    {0}: 지역 {1}개, 최신 {2}분기" -f $kind, $regions.Count, $latest) -ForegroundColor Green
  }
  if ($types.Count -eq 0) { Write-Host "  자본수익률 표를 찾지 못함 — 앱은 수동입력으로 동작"; return $null }
  return [ordered]@{
    fetchedAt = (Get-Date -Format "yyyy-MM-dd HH:mm")
    source    = "한국부동산원 R-ONE 상업용부동산 임대동향조사 (분기) — 자본수익률"
    types     = $types
  }
}

function Fetch-IndexData {
  if (-not $apiKey) {
    throw "API 키가 없습니다. 같은 폴더에 'arap_apikey.local.txt' 파일을 만들고 부동산원 R-ONE 인증키를 한 줄로 넣으세요. (환경변수 RONE_API_KEY 로 넣어도 됨)"
  }
  Write-Host "부동산원 매매가격지수 수신 중..." -ForegroundColor Cyan
  $out = [ordered]@{
    fetchedAt = (Get-Date -Format "yyyy-MM-dd HH:mm")
    source    = "한국부동산원 R-ONE 전국주택가격동향조사 (월간)"
    tables    = [ordered]@{}
  }
  foreach ($kind in $tables.Keys) {
    $t = $tables[$kind]
    $regions = [ordered]@{}
    $latest = ""
    $n = 0
    foreach ($cid in $t.cls) {
      $n++
      Write-Host ("  {0} {1}/{2}" -f $kind, $n, $t.cls.Count) -NoNewline
      $url = "{0}?STATBL_ID={1}&DTACYCLE_CD=MM&CLS_ID={2}&Type=json&pIndex=1&pSize=1000&KEY={3}" -f $apiBase, $t.id, $cid, $apiKey
      $j = Invoke-RestMethod -Uri $url -TimeoutSec 30
      $rows = $j.SttsApiTblData[1].row
      if (-not $rows) { Write-Host " (자료없음)"; continue }
      $full = $rows[0].CLS_FULLNM
      $name = ($full -split ">")[-1]           # 마지막 구간 = 구/권역/서울 (서울 내에서 유일함 확인됨)
      $series = [ordered]@{}
      foreach ($r in $rows) {
        # 공표 지수는 소수 1자리 — 산식 표기와 일치하도록 반올림 저장
        $series[[string]$r.WRTTIME_IDTFR_ID] = [math]::Round([double]$r.DTA_VAL, 1)
        if ([string]$r.WRTTIME_IDTFR_ID -gt $latest) { $latest = [string]$r.WRTTIME_IDTFR_ID }
      }
      $regions[$name] = [ordered]@{ cls = $cid; full = $full; s = $series }
      Write-Host (" {0} ({1}개월)" -f $name, $series.Count)
    }
    $out.tables[$kind] = [ordered]@{ statblId = $t.id; latest = $latest; regions = $regions }
  }
  # 비주거용 자본수익률(분기) — 실패해도 매매지수는 정상 저장
  try { $cap = Fetch-CapReturn; if ($cap) { $out.capReturn = $cap } }
  catch { Write-Host "자본수익률 수신 실패(매매지수는 정상 저장): $_" -ForegroundColor Yellow }
  $json = $out | ConvertTo-Json -Depth 8 -Compress
  $js = "window.ARAP_INDEX_DATA=" + $json + ";"
  $tmp = $dataFile + ".tmp"
  [IO.File]::WriteAllText($tmp, $js, (New-Object Text.UTF8Encoding($false)))
  Move-Item -Force $tmp $dataFile
  $capNote = if ($out.capReturn) { "자본수익률 " + (@($out.capReturn.types.Keys) -join "/") } else { "자본수익률 없음" }
  Write-Host ("완료: {0} (매매지수 최신 {1} · {2})" -f (Split-Path -Leaf $dataFile), $out.tables["아파트"].latest, $capNote) -ForegroundColor Green
}

$hasData = Test-Path $dataFile

if (-not $FetchOnly -and $hasData) {
  # 앱부터 즉시 열고, 데이터가 하루 이상 묵었으면 조용히 갱신 (다음 새로고침/실행부터 반영)
  Start-Process $htmlFile
  $ageDays = ((Get-Date) - (Get-Item $dataFile).LastWriteTime).TotalDays
  if ($ageDays -gt 1) {
    try { Fetch-IndexData } catch { Write-Host "지수 갱신 실패(오프라인?) — 기존 데이터 사용: $_" -ForegroundColor Yellow }
  }
}
else {
  # 첫 실행(데이터 없음) 또는 FetchOnly: 받고 나서 연다
  try { Fetch-IndexData }
  catch {
    Write-Host "지수 수신 실패: $_" -ForegroundColor Red
    Write-Host "인터넷 연결을 확인하세요. 데이터 없이 앱만 엽니다. (자동계산 버튼은 비활성 안내가 뜹니다)"
    Start-Sleep -Seconds 3
  }
  if (-not $FetchOnly) { Start-Process $htmlFile }
}
