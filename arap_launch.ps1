# EXACT(구 ARAP) 실행 + 부동산원(R-ONE) 매매가격지수 자동 수신
# - 'EXACT 실행.bat'이 이 파일을 호출한다. 직접 실행해도 된다.
# - 지수 데이터(arap_index_data.js)가 없으면: 먼저 받고 앱을 연다.
# - 있으면: 앱을 먼저 열고, 하루 이상 지난 경우 백그라운드로 새로 받는다.
param([switch]$FetchOnly, [switch]$CapOnly)   # -CapOnly: 자본수익률(비주거)만 받아 기존 데이터에 병합 (주거 매매지수 재수신 생략 — 테스트·부분갱신용)

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

# 부동산원 API가 간헐적으로 느림 → 단일 호출 타임아웃(30초)에 걸리면 전체 수신이 중단됐음.
# 타임아웃 60초 + 최대 3회 재시도로 일시적 지연을 흡수한다(주거·비주거 공용).
function Invoke-Rone($url) {
  $attempt = 0
  while ($true) {
    $attempt++
    try { return Invoke-RestMethod -Uri $url -TimeoutSec 60 }
    catch {
      if ($attempt -ge 4) { throw }
      Write-Host ("    (재시도 {0}/3: {1})" -f $attempt, $_.Exception.Message) -ForegroundColor DarkYellow
      Start-Sleep -Seconds ([math]::Min(8, [math]::Pow(2, $attempt)))
    }
  }
}

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
  $s = ([string]$w) -replace '[^0-9A-Za-z]',''            # 2026.2 / 2026-Q2 → 20262 / 2026Q2
  if ($s -match '^(\d{4})[Qq]?0?([1-4])$')      { return "$($matches[1])$($matches[2])" }   # 20261 / 2026Q1 / 2026Q01
  if ($s -match '^(\d{4})(0[1-9]|1[0-2])$')      { $mm=[int]$matches[2]; $q=[math]::Ceiling($mm/3.0); return "$($matches[1])$q" }  # 202603(분기말월)→20261
  return $null
}
function Fetch-CapReturn {
  Write-Host "상업용부동산 자본수익률(분기) 수신 중..." -ForegroundColor Cyan
  try {
    $lurl = "{0}?Type=json&pIndex=1&pSize=1000&KEY={1}" -f $listBase, $apiKey
    $lj = Invoke-Rone $lurl
    $all = $lj.SttsApiTbl[1].row
  } catch { Write-Host "  통계목록 조회 실패(자본수익률 생략): $_" -ForegroundColor Yellow; return $null }
  if (-not $all) { Write-Host "  통계목록 비어있음 — 자본수익률 생략"; return $null }
  # 2024Q3 통계개편으로 표가 세대교체됨: 구세대는 "임대동향 자본수익률(…)", 신세대(2024년3분기~)는 "임대동향 수익률(분기)(…)"
  # 이름에 '자본수익률'만 매칭하면 신세대(최신 분기)를 놓침 → '임대동향'+'수익률'로 넓게 잡고, 행 단위 ITM_NM 필터가 자본수익률만 골라냄
  $cands = @($all | Where-Object { $_.STATBL_NM -match "임대동향" -and $_.STATBL_NM -match "수익률" })
  Write-Host ("  임대동향 수익률 통계표 후보 {0}건" -f $cands.Count)
  foreach ($c in $cands) { Write-Host ("    [{0}] {1} ({2})" -f $c.STATBL_ID, $c.STATBL_NM, $c.DTACYCLE_NM) }
  # 후보 표는 연도구간별로 쪼개져 있음(2022~, 2021, 2020, …) → 유형별로 모든 기간표를 병합해 전체 이력 확보.
  # 주기는 반드시 QY(분기)로 조회한다(목록의 DTACYCLE_CD는 '매년,분기' 복합값이라 그대로 쓰면 조회가 비어 SttsApiTblData=null).
  $byType = [ordered]@{}
  foreach ($c in $cands) {
    $kind = Get-CapType $c.STATBL_NM
    if (-not $kind) { continue }
    if (-not $byType.Contains($kind)) { $byType[$kind] = New-Object System.Collections.ArrayList }
    [void]$byType[$kind].Add([string]$c.STATBL_ID)
  }
  $types = [ordered]@{}
  $diagShown = $false
  foreach ($kind in $byType.Keys) {
    $regions = [ordered]@{}
    $latest = ""
    foreach ($sid in $byType[$kind]) {
      # 한 표가 지역 300개↑ × 분기 수십 개라 1,000행/페이지를 넘음 → 페이지를 끝까지 넘긴다 (안 그러면 최신 분기가 잘림)
      for ($pg = 1; $pg -le 40; $pg++) {
        try {
          $durl = "{0}?STATBL_ID={1}&DTACYCLE_CD=QY&Type=json&pIndex={2}&pSize=1000&KEY={3}" -f $apiBase, $sid, $pg, $apiKey
          $dj = Invoke-Rone $durl
        } catch { Write-Host ("    {0} {1} p{2} 호출실패: {3}" -f $kind, $sid, $pg, $_) -ForegroundColor Yellow; break }
        $rows = if ($dj.SttsApiTblData -and @($dj.SttsApiTblData).Count -ge 2) { $dj.SttsApiTblData[1].row } else { $null }
        if (-not $diagShown) {
          $diagShown = $true
          if ($rows -and @($rows).Count -ge 1) {
            $r0 = @($rows)[0]
            Write-Host ("    [진단] {0} 첫행: WRTTIME={1} CLS_NM={2} CLS_FULLNM={3} ITM_NM={4} DTA_VAL={5}" -f $sid, $r0.WRTTIME_IDTFR_ID, $r0.CLS_NM, $r0.CLS_FULLNM, $r0.ITM_NM, $r0.DTA_VAL) -ForegroundColor Cyan
          } else {
            $raw = ($dj | ConvertTo-Json -Depth 4 -Compress); if (-not $raw) { $raw = "(null)" }
            Write-Host ("    [진단] {0} 응답(앞400자): {1}" -f $sid, $raw.Substring(0, [math]::Min(400, $raw.Length))) -ForegroundColor Yellow
          }
        }
        if (-not $rows) { break }
        foreach ($r in $rows) {
          if ($r.ITM_NM -and ($r.ITM_NM -notmatch "자본수익률")) { continue }   # 한 표에 여러 항목(투자/소득/자본)이 섞임 — 자본수익률만
          $q = ConvertTo-QKey $r.WRTTIME_IDTFR_ID
          if (-not $q) { continue }
          # 지역은 시도 단위까지만(전체·서울·부산…). 상권 단위 300개↑는 시점수정에 안 쓰고 파일만 커짐
          $fullParts = @(([string]$r.CLS_FULLNM) -split ">")
          if ($fullParts.Count -gt 2) { continue }
          $reg = if ($r.CLS_NM) { [string]$r.CLS_NM } elseif ($r.CLS_FULLNM) { $fullParts[-1] } else { "전국" }
          $reg = $reg.Trim()
          if (-not $regions.Contains($reg)) { $regions[$reg] = [ordered]@{} }
          $regions[$reg][$q] = [math]::Round([double]$r.DTA_VAL, 2)   # 공표 자본수익률(%)은 소수 2자리
          if ($q -gt $latest) { $latest = $q }
        }
        if (@($rows).Count -lt 1000) { break }   # 마지막 페이지
      }
    }
    if ($regions.Count -eq 0) { Write-Host ("    {0} 자료없음" -f $kind) -ForegroundColor Yellow; continue }
    $types[$kind] = [ordered]@{ latest = $latest; regions = $regions }
    $sample = @($regions.Keys)[0]
    Write-Host ("    {0}: 지역 {1}개, 최신 {2}분기 (예: {3} {4}개분기)" -f $kind, $regions.Count, $latest, $sample, $regions[$sample].Count) -ForegroundColor Green
  }
  if ($types.Count -eq 0) { Write-Host "  자본수익률 표를 찾지 못함 — 앱은 수동입력으로 동작"; return $null }
  return [ordered]@{
    fetchedAt = (Get-Date -Format "yyyy-MM-dd HH:mm")
    source    = "한국부동산원 R-ONE 상업용부동산 임대동향조사 (분기) — 자본수익률"
    types     = $types
  }
}

# -CapOnly: 주거 매매지수는 그대로 두고 자본수익률만 새로 받아 기존 파일에 병합 (테스트 1회 2~3분)
function Update-CapReturnOnly {
  if (-not $apiKey) { throw "API 키가 없습니다. (환경변수 RONE_API_KEY 또는 arap_apikey.local.txt)" }
  if (-not (Test-Path $dataFile)) { throw "기존 arap_index_data.js가 없습니다. 전체 수신(-FetchOnly)을 먼저 실행하세요." }
  $txt = [IO.File]::ReadAllText($dataFile)
  $json = $txt -replace '^\s*window\.ARAP_INDEX_DATA\s*=\s*', ''
  $json = $json.TrimEnd().TrimEnd(';')
  $out = $json | ConvertFrom-Json
  $cap = Fetch-CapReturn
  if (-not $cap) { throw "자본수익률 수신 실패 — 기존 파일은 그대로 둠" }
  $out | Add-Member -NotePropertyName capReturn -NotePropertyValue $cap -Force
  $js = "window.ARAP_INDEX_DATA=" + ($out | ConvertTo-Json -Depth 8 -Compress) + ";"
  $tmp = $dataFile + ".tmp"
  [IO.File]::WriteAllText($tmp, $js, (New-Object Text.UTF8Encoding($false)))
  Move-Item -Force $tmp $dataFile
  Write-Host ("완료(자본수익률만 갱신): {0}" -f (@($cap.types.Keys) -join "/")) -ForegroundColor Green
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
      $j = Invoke-Rone $url
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

if ($CapOnly) { Update-CapReturnOnly; exit 0 }

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
