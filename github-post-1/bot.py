import json
import os
import random
from pathlib import Path

import requests
from requests_oauthlib import OAuth1

POSTS_FILE = Path("posts.txt")
STATE_FILE = Path("state.json")

HEADS = [
    "【今日の1本】",
    "【過去記事】",
    "【備忘録】",
    "【技術メモ】",
    "【メモ置き場】",
    "【アーカイブ】",
    "【積み上げ】",
    "【朝の一本】",
    "【通勤のお供】",
]

def load_posts():
    posts = [line.strip() for line in POSTS_FILE.read_text(encoding="utf-8").splitlines()]
    posts = [p for p in posts if p and not p.startswith("#")]
    if not posts:
        raise RuntimeError("posts.txt が空です")
    return posts

def load_state():
    if not STATE_FILE.exists():
        return {"posted_urls": [], "last_url": None}
    s = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    s.setdefault("posted_urls", [])
    s.setdefault("last_url", None)
    return s

def save_state(state):
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")

def build_text(url: str) -> str:
    head = random.choice(HEADS)
    return f"{head}\n{url}\n#addache"

def post_to_x(text: str):
    api_key = os.environ["X_API_KEY"]
    api_secret = os.environ["X_API_SECRET"]
    access_token = os.environ["X_ACCESS_TOKEN"]
    access_secret = os.environ["X_ACCESS_TOKEN_SECRET"]

    auth = OAuth1(api_key, api_secret, access_token, access_secret)

    r = requests.post(
        "https://api.twitter.com/2/tweets",
        auth=auth,
        json={"text": text},
        timeout=30,
    )
    if r.status_code >= 300:
        raise RuntimeError(f"X投稿失敗: {r.status_code} {r.text}")
    return r.json()

def main():
    posts = load_posts()
    state = load_state()

    i = int(state.get("next_index", 0)) % len(posts)
    url = posts[i]
    text = build_text(url)

    res = post_to_x(text)
    print("posted:", res)

    state["next_index"] = i + 1
    save_state(state)

if __name__ == "__main__":
    main()
