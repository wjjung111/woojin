#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
영어 대화 리스닝 음성 생성기 (edge-tts 사용, 무료 · API키 불필요)

대본파일(dialogue_*.txt)을 읽어 F:/M: 로 화자를 나눠
남/여 미국 원어민 신경망 음성으로 읽고, 하나의 mp3로 이어붙입니다.

사용법:
    python generate_audio.py dialogue_make.txt
    python generate_audio.py dialogue_make.txt --out make_리스닝.mp3
    python generate_audio.py dialogue_make.txt --rate -8%   (조금 천천히)
    python generate_audio.py dialogue_make.txt --dry-run    (인터넷 없이 구성만 점검)

인터넷 없이 만드는 게 아니라, 실행 순간에만 마이크로소프트 음성 서버에 접속합니다.
(개인 PC에서는 정상 동작. 회사/클라우드 방화벽 환경에선 막힐 수 있음)
"""
import sys, os, re, argparse, asyncio

# ── 화자별 목소리 설정 (여기만 바꾸면 목소리가 바뀜) ─────────────────
# 미국 영어 신경망 음성. 다른 후보:
#   남성: en-US-GuyNeural, en-US-ChristopherNeural, en-US-EricNeural, en-US-BrianNeural
#   여성: en-US-AriaNeural, en-US-JennyNeural, en-US-MichelleNeural, en-US-EmmaNeural
VOICE = {
    "F": "en-US-AriaNeural",   # 여자(Emma) — 자연스러운 대화체
    "M": "en-US-GuyNeural",    # 남자(Jake)
}
DEFAULT_RATE = "+0%"   # 말 속도. 천천히=-10%, 빠르게=+10%
# ────────────────────────────────────────────────────────────────

PAREN = re.compile(r"\([^)]*\)")   # (laughs) 같은 지문 제거용


def parse_dialogue(path):
    """대본파일 → [(speaker, text), ...]"""
    segs = []
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"^([FMfm]|남|여)\s*[:：]\s*(.+)$", line)
            if not m:
                continue
            spk = m.group(1).upper()
            spk = {"남": "M", "여": "F"}.get(spk, spk)
            text = PAREN.sub("", m.group(2)).strip()   # 지문 제거
            text = re.sub(r"\s{2,}", " ", text)
            if text:
                segs.append((spk, text))
    return segs


async def synth_segment(text, voice, rate, out_path):
    import edge_tts
    comm = edge_tts.Communicate(text, voice=voice, rate=rate)
    await comm.save(out_path)


async def build(segs, out_mp3, rate, workdir):
    os.makedirs(workdir, exist_ok=True)
    parts = []
    for i, (spk, text) in enumerate(segs):
        voice = VOICE.get(spk, VOICE["F"])
        part = os.path.join(workdir, f"seg_{i:03d}_{spk}.mp3")
        print(f"  [{i+1:>2}/{len(segs)}] {spk} · {voice} · {text[:48]}{'…' if len(text)>48 else ''}")
        await synth_segment(text, voice, rate, part)
        parts.append(part)
    # mp3 이어붙이기 (프레임 단순 연결 — 대부분 플레이어에서 정상 재생)
    with open(out_mp3, "wb") as w:
        for p in parts:
            with open(p, "rb") as r:
                w.write(r.read())
    print(f"\n✅ 완성: {out_mp3}  ({os.path.getsize(out_mp3)//1024} KB, 구간 {len(parts)}개)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dialogue", help="대본파일 경로 (예: dialogue_make.txt)")
    ap.add_argument("--out", default=None, help="출력 mp3 파일명")
    ap.add_argument("--rate", default=DEFAULT_RATE, help="말 속도 (예: -8%%, +0%%, +10%%)")
    ap.add_argument("--dry-run", action="store_true", help="인터넷 접속 없이 구성만 출력")
    args = ap.parse_args()

    if not os.path.isfile(args.dialogue):
        print(f"❌ 대본파일을 찾을 수 없습니다: {args.dialogue}"); sys.exit(1)

    segs = parse_dialogue(args.dialogue)
    if not segs:
        print("❌ 대본에서 읽을 대사(F:/M:)를 찾지 못했습니다."); sys.exit(1)

    base = os.path.splitext(os.path.basename(args.dialogue))[0]
    out_mp3 = args.out or (base + ".mp3")
    workdir = os.path.join(os.path.dirname(os.path.abspath(args.dialogue)), "_segments")

    print(f"대본: {args.dialogue}  대사 {len(segs)}줄  속도 {args.rate}")
    if args.dry_run:
        for i, (spk, text) in enumerate(segs):
            print(f"  [{i+1:>2}] {spk} · {VOICE.get(spk)} · {text}")
        print("\n(dry-run: 실제 음성은 만들지 않았습니다)"); return

    try:
        import edge_tts  # noqa
    except ImportError:
        print("❌ edge-tts 가 설치돼 있지 않습니다. 먼저:  pip install edge-tts"); sys.exit(1)

    try:
        asyncio.run(build(segs, out_mp3, args.rate, workdir))
    except Exception as e:
        print(f"\n❌ 음성 생성 중 오류: {e}")
        print("   (인터넷 연결/방화벽을 확인하세요. 회사망·클라우드에선 막힐 수 있습니다.)")
        sys.exit(1)


if __name__ == "__main__":
    main()
