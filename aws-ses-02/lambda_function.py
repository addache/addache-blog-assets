import json
import os
import urllib.request

WEBHOOK = os.environ["DISCORD_WEBHOOK_URL"]


def post_discord(content: str) -> int:
    payload = {"content": content}
    data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        WEBHOOK,
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "aws-lambda/discord-webhook",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=5) as resp:
        return resp.status


def lambda_handler(event, context):
    rec = event["Records"][0]

    # SESから受信したメール情報を取得
    mail = rec["ses"]["mail"]
    headers = mail.get("commonHeaders", {})

    subject = headers.get("subject", "(no subject)")
    sender = headers.get("from", ["(unknown)"])
    recipients = mail.get("destination", [])

    # Discordへ送信するメッセージを作成
    content = (
        f"📩 **メール通知**\n"
        f"- **件名**: {subject}\n"
        f"- **送信元**: {', '.join(sender)}\n"
        f"- **宛先**: {', '.join(recipients)}"
    )

    # Discordの文字数制限対策
    content = content[:1900]

    status = post_discord(content)
    print(f"discord_status={status}")

    return {"ok": True, "status": status}
