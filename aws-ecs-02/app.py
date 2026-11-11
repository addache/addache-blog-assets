import os

import boto3
from botocore.exceptions import ClientError
from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

AWS_REGION = os.getenv("AWS_REGION", "ap-northeast-1")
DYNAMODB_TABLE = os.getenv("DYNAMODB_TABLE", "ecs-sample-table")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table(DYNAMODB_TABLE)


@app.get("/")
def index():
    return "Hello"


@app.get("/api")
def api():
    fallback = {
        "title": "Message",
        "message": "Hello from AWS ECS!",
        "version": None,
        "accessCount": None,
        "source": "ECS"
    }

    try:
        response = table.update_item(
            Key={
                "id": "AzureToAWS"
            },
            UpdateExpression="ADD AccessCount :increment",
            ExpressionAttributeValues={
                ":increment": 1
            },

            # PKが存在しない場合に、新しい不完全なレコードを
            # 勝手に作らないための条件
            ConditionExpression="attribute_exists(id)",

            # 更新後のレコードをそのまま受け取る
            ReturnValues="ALL_NEW"
        )

        item = response["Attributes"]

        return jsonify({
            "title": item.get("Title", "Message"),
            "message": item.get("Message", "Hello from AWS ECS!"),
            "version": item.get("Version"),
            "accessCount": int(item.get("AccessCount", 0)),
            "source": "DynamoDB"
        })

    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]

        if error_code == "ConditionalCheckFailedException":
            app.logger.warning("DynamoDB record AzureToAWS was not found")
        else:
            app.logger.exception("Failed to update DynamoDB")

        return jsonify(fallback)

    except Exception:
        app.logger.exception("Unexpected API error")
        return jsonify(fallback)


@app.get("/health")
def health():
    return "ok", 200
