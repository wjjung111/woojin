#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
listen/dialogues/*.json → listen/audio/<id>/ 에
  NNN.mp3      문장별 파일 (탭 재생 예비용)
  full.mp3     전체 연속 파일 (문장 사이 자연스러운 쉼 포함)
  timings.json 각 문장의 full.mp3 내 시작~끝 초 (앱이 하이라이트/탭이동에 사용)
GitHub Actions에서 실행됨 (edge-tts = Azure Neural 음성, 무료·API키 불필요).

- 대본 내용이 안 바뀐 챕터는 건너뜀 (.stamp 에 대본 해시 저장)
- 끝나면 listen/manifest.json 갱신 (앱이 챕터 목록으로 사용)
"""
import asyncio, hashlib, json, os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DLG_DIR = ROOT / "dialogues"
AUD_DIR = ROOT / "audio"
FAKE = os.environ.get("FAKE_TTS") == "1"   # 로컬 구조 테스트용 (음성서버 접속 없음)
GAP_SECONDS = 0.45                         # 화자 교대 사이 쉼 — 실제 대화 호흡


def mp3_duration(path):
    if FAKE:
        return 1.0
    from mutagen.mp3 import MP3
    return MP3(str(path)).info.length


def build_silence():
    """문장 사이에 끼울 무음 mp3 (edge-tts와 동일 포맷: 24kHz mono 48kbps)."""
    sil = AUD_DIR / "_silence.mp3"
    if FAKE:
        return b"", 0.0
    AUD_DIR.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono",
             "-t", str(GAP_SECONDS), "-c:a", "libmp3lame", "-b:a", "48k", "-ac", "1", str(sil)],
            check=True, capture_output=True)
        data = sil.read_bytes()
        dur = mp3_duration(sil)
        sil.unlink()
        return data, dur
    except Exception as e:
        print(f"  (무음 생성 실패 — 쉼 없이 이어붙임: {e})")
        return b"", 0.0


async def synth(text, voice, out_path):
    if FAKE:
        out_path.write_bytes(b"FAKE:" + voice.encode() + b":" + text.encode()[:30]); return
    import edge_tts
    await edge_tts.Communicate(text, voice=voice).save(str(out_path))


async def build_dialogue(dlg_file, sil_bytes, sil_dur):
    data = json.loads(dlg_file.read_text(encoding="utf-8"))
    did, lines = data["id"], data["lines"]
    outdir = AUD_DIR / did
    outdir.mkdir(parents=True, exist_ok=True)

    # v2: ffmpeg 무음 삽입 성공본부터 유효 — 버전 올리면 전 챕터 강제 재생성
    content_hash = hashlib.sha256(dlg_file.read_bytes() + f"gap={GAP_SECONDS};v2".encode()).hexdigest()
    stamp = outdir / ".stamp"
    complete = (all((outdir / f"{i:03d}.mp3").exists() for i in range(len(lines)))
                and (outdir / "full.mp3").exists() and (outdir / "timings.json").exists())
    if stamp.exists() and stamp.read_text().strip() == content_hash and complete:
        print(f"  [{did}] 변경 없음 — 건너뜀")
        return data

    print(f"  [{did}] {len(lines)}문장 생성 중...")
    for i, ln in enumerate(lines):
        voice = data["voices"][ln["s"]]
        await synth(ln["en"], voice, outdir / f"{i:03d}.mp3")
        print(f"    {i+1}/{len(lines)} {ln['s']} · {ln['en'][:40]}")

    # 전체 연속본: 문장 mp3 + 사이 무음. 동일 포맷 CBR이라 바이트 연결로 재생·탐색 정상.
    t = 0.0
    timings = []
    with open(outdir / "full.mp3", "wb") as w:
        for i in range(len(lines)):
            seg = outdir / f"{i:03d}.mp3"
            start = t
            w.write(seg.read_bytes())
            t += mp3_duration(seg)
            timings.append({"s": round(start, 3), "e": round(t, 3)})
            if i < len(lines) - 1 and sil_bytes:
                w.write(sil_bytes)
                t += sil_dur
    (outdir / "timings.json").write_text(
        json.dumps(timings, ensure_ascii=False), encoding="utf-8")

    stamp.write_text(content_hash)
    return data


async def main():
    dlg_files = sorted(DLG_DIR.glob("*.json"))
    if not dlg_files:
        print("dialogues/*.json 없음"); sys.exit(1)

    sil_bytes, sil_dur = build_silence()
    manifest = []
    for f in dlg_files:
        data = await build_dialogue(f, sil_bytes, sil_dur)
        manifest.append({
            "id": data["id"],
            "order": data.get("order", 999),
            "title": data["title"],
            "lines": len(data["lines"]),
        })
    manifest.sort(key=lambda m: m["order"])
    (ROOT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"완료: 챕터 {len(manifest)}개, manifest.json 갱신")


if __name__ == "__main__":
    asyncio.run(main())
