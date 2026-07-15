@echo off
REM ============================================================
REM  영어 대화 리스닝 음성 만들기 (더블클릭 실행)
REM  - dialogue_make.txt 를 남/여 미국 원어민 음성으로 읽어 mp3 생성
REM  - edge-tts 사용 (무료, API키 불필요). 실행 순간에만 인터넷 필요.
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"

echo.
echo [1/3] 파이썬 확인 중...
python --version >nul 2>&1
if errorlevel 1 (
  echo    X 파이썬이 설치돼 있지 않습니다.
  echo      https://www.python.org 에서 Python 설치 후 다시 실행하세요.
  echo      (설치 시 "Add Python to PATH" 체크 필수)
  pause
  exit /b 1
)

echo [2/3] 음성 엔진(edge-tts) 확인/설치 중...
python -c "import edge_tts" >nul 2>&1
if errorlevel 1 (
  echo    - edge-tts 설치 중... (처음 한 번만)
  python -m pip install --quiet --upgrade edge-tts
)

echo [3/3] 음성 생성 중... (남:Guy / 여:Aria)
echo.
python generate_audio.py dialogue_make.txt --out make_리스닝.mp3
if errorlevel 1 (
  echo.
  echo X 생성에 실패했습니다. 위 오류 메시지를 확인하세요.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo  완료! 이 폴더의  make_리스닝.mp3  파일을 재생해 보세요.
echo  (속도 조절: 이 창을 닫고, 아래 명령을 직접 실행)
echo    python generate_audio.py dialogue_make.txt --rate -8%%
echo ============================================================
pause
