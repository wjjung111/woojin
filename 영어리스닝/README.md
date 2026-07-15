# 영어 대화 리스닝 음성 만들기

원어민 남·여 두 명이 영어로 대화하는 짧은 음성(mp3)을 **무료로** 만드는 도구입니다.
리스닝(듣기) 연습용. 마이크로소프트의 신경망 음성(edge-tts)을 써서 실제 사람처럼
자연스럽게(축약형·연음 포함) 읽어 줍니다. **API 키가 필요 없습니다.**

## 가장 쉬운 사용법 (Windows)

1. 이 폴더의 **`영어리스닝_음성만들기.bat`** 를 더블클릭
2. 잠시 기다리면 같은 폴더에 **`make_리스닝.mp3`** 가 생김
3. mp3를 재생해서 들으면 끝

> 처음 실행 땐 음성 엔진(edge-tts)을 자동으로 한 번 설치합니다. (인터넷 필요)
> 파이썬이 없다면 https://www.python.org 에서 설치 (설치 화면에서 **Add Python to PATH** 체크).

## 직접 명령으로 쓰기 (속도·목소리 조절)

```bash
# 기본
python generate_audio.py dialogue_make.txt --out make_리스닝.mp3

# 조금 천천히 (초보 리스닝용)
python generate_audio.py dialogue_make.txt --rate -8%

# 인터넷 없이 구성만 확인
python generate_audio.py dialogue_make.txt --dry-run
```

## 대본을 바꾸고 싶을 때

- `dialogue_make.txt` 를 열어 대사를 고치면 됩니다.
- 규칙: 줄 맨 앞에 **`F:`**(여자) 또는 **`M:`**(남자). `#`으로 시작하는 줄과 `(괄호)` 지문은 무시됩니다.
- 다른 주제로 새 대본을 만들면 파일명만 바꿔서 (`dialogue_take.txt` 등) 같은 방식으로 실행하세요.

## 목소리 바꾸기

`generate_audio.py` 위쪽 `VOICE` 부분을 수정:

```python
VOICE = {
    "F": "en-US-AriaNeural",   # 여자
    "M": "en-US-GuyNeural",    # 남자
}
```
- 남성 후보: `en-US-GuyNeural`, `en-US-ChristopherNeural`, `en-US-EricNeural`, `en-US-BrianNeural`
- 여성 후보: `en-US-AriaNeural`, `en-US-JennyNeural`, `en-US-MichelleNeural`, `en-US-EmmaNeural`

## 참고

- 현재 대본(`dialogue_make.txt`)은 **김재우 기본동사100 DAY22~24 (make ①②③)** 표현으로 구성했습니다.
  한글 번역·용법 정리는 `make_대화_대본.md` 참고.
- 이 도구는 **개인 PC에서** 잘 동작합니다. 회사망·클라우드처럼 방화벽이 센 환경에선 음성 서버 접속이 막힐 수 있습니다.
