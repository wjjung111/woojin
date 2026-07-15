#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
listen/dialogues/*.json → listen/audio/<id>/NNN.mp3 (문장별) + full.mp3 (전체)
GitHub Actions에서 실행됨 (edge-tts = Azure Neural 음성, 무료·API키 불필요).

- 대본 내용이 안 바뀐 챕터는 건너뜀 (.stamp 에 대본 해시 저장)
- 끝나면 listen/manifest.json 갱신 (앱이 챕터 목록으로 사용)
"""
import asyncio, hashlib, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DLG_DIR = ROOT / "dialogues"
AUD_DIR = ROOT / "audio"


async def synth(text, voice, out_path):
    import edge_tts
    # 폰에서 배속 조절(playbackRate)을 쓰므로 원본은 표준 속도로 생성
    await edge_tts.Communicate(text, voice=voice).save(str(out_path))


async def build_dialogue(dlg_file):
    data = json.loads(dlg_file.read_text(encoding="utf-8"))
    did, lines = data["id"], data["lines"]
    outdir = AUD_DIR / did
    outdir.mkdir(parents=True, exist_ok=True)

    content_hash = hashlib.sha256(dlg_file.read_bytes()).hexdigest()
    stamp = outdir / ".stamp"
    complete = all((outdir / f"{i:03d}.mp3").exists() for i in range(len(lines))) and (outdir / "full.mp3").exists()
    if stamp.exists() and stamp.read_text().strip() == content_hash and complete:
        print(f"  [{did}] 변경 없음 — 건너뜀")
        return data

    print(f"  [{did}] {len(lines)}문장 생성 중...")
    for i, ln in enumerate(lines):
        voice = data["voices"][ln["s"]]
        await synth(ln["en"], voice, outdir / f"{i:03d}.mp3")
        print(f"    {i+1}/{len(lines)} {ln['s']} · {ln['en'][:40]}")

    # 전체본 = 문장 mp3 단순 연결 (같은 인코딩이라 이어 재생됨)
    with open(outdir / "full.mp3", "wb") as w:
        for i in range(len(lines)):
            w.write((outdir / f"{i:03d}.mp3").read_bytes())

    stamp.write_text(content_hash)
    return data


async def main():
    dlg_files = sorted(DLG_DIR.glob("*.json"))
    if not dlg_files:
        print("dialogues/*.json 없음"); sys.exit(1)

    manifest = []
    for f in dlg_files:
        data = await build_dialogue(f)
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
