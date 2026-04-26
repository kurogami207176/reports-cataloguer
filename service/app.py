import os
import json
import uuid
import boto3
import requests
import jwt
from datetime import datetime, timezone
from functools import wraps
from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": os.getenv("ALLOWED_ORIGINS", "*")}})

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
COGNITO_USER_POOL_ID = os.getenv("COGNITO_USER_POOL_ID")
COGNITO_CLIENT_ID = os.getenv("COGNITO_CLIENT_ID")
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME")

s3_client = boto3.client("s3", region_name=AWS_REGION)
cognito_client = boto3.client("cognito-idp", region_name=AWS_REGION)

_cognito_public_keys = None


def get_cognito_public_keys():
    global _cognito_public_keys
    if _cognito_public_keys is None:
        jwks_url = (
            f"https://cognito-idp.{AWS_REGION}.amazonaws.com/"
            f"{COGNITO_USER_POOL_ID}/.well-known/jwks.json"
        )
        resp = requests.get(jwks_url, timeout=10)
        resp.raise_for_status()
        _cognito_public_keys = resp.json()["keys"]
    return _cognito_public_keys


def decode_token(token):
    keys = get_cognito_public_keys()
    header = jwt.get_unverified_header(token)
    kid = header.get("kid")
    key_data = next((k for k in keys if k["kid"] == kid), None)
    if key_data is None:
        raise ValueError("Public key not found")
    public_key = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(key_data))
    return jwt.decode(
        token,
        public_key,
        algorithms=["RS256"],
        options={"verify_exp": True},
    )


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing or invalid Authorization header"}), 401
        token = auth_header[len("Bearer "):]
        try:
            payload = decode_token(token)
        except Exception:
            return jsonify({"error": "Token validation failed"}), 401
        request.user_sub = payload.get("sub")
        request.user_email = payload.get("email")
        return f(*args, **kwargs)
    return decorated


# ---------------------------------------------------------------------------
# Auth routes
# ---------------------------------------------------------------------------

@app.route("/api/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/api/auth/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    email = data.get("email", "").strip()
    password = data.get("password", "")
    if not email or not password:
        return jsonify({"error": "email and password are required"}), 400
    try:
        resp = cognito_client.initiate_auth(
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={"USERNAME": email, "PASSWORD": password},
            ClientId=COGNITO_CLIENT_ID,
        )
    except cognito_client.exceptions.NotAuthorizedException:
        return jsonify({"error": "Invalid email or password"}), 401
    except cognito_client.exceptions.UserNotFoundException:
        return jsonify({"error": "Invalid email or password"}), 401
    except Exception:
        return jsonify({"error": "An unexpected error occurred"}), 500

    auth_result = resp.get("AuthenticationResult", {})
    return jsonify(
        {
            "accessToken": auth_result.get("AccessToken"),
            "idToken": auth_result.get("IdToken"),
            "refreshToken": auth_result.get("RefreshToken"),
            "expiresIn": auth_result.get("ExpiresIn"),
        }
    )


@app.route("/api/auth/refresh", methods=["POST"])
def refresh():
    data = request.get_json(silent=True) or {}
    refresh_token = data.get("refreshToken", "")
    if not refresh_token:
        return jsonify({"error": "refreshToken is required"}), 400
    try:
        resp = cognito_client.initiate_auth(
            AuthFlow="REFRESH_TOKEN_AUTH",
            AuthParameters={"REFRESH_TOKEN": refresh_token},
            ClientId=COGNITO_CLIENT_ID,
        )
    except Exception:
        return jsonify({"error": "Token refresh failed"}), 401
    auth_result = resp.get("AuthenticationResult", {})
    return jsonify(
        {
            "accessToken": auth_result.get("AccessToken"),
            "idToken": auth_result.get("IdToken"),
            "expiresIn": auth_result.get("ExpiresIn"),
        }
    )


# ---------------------------------------------------------------------------
# Submissions routes
# ---------------------------------------------------------------------------

@app.route("/api/submissions", methods=["POST"])
@require_auth
def create_submission():
    data = request.get_json(silent=True) or {}
    text = data.get("text", "").strip()
    if not text:
        return jsonify({"error": "text is required"}), 400

    now = datetime.now(tz=timezone.utc)
    submission_id = str(uuid.uuid4())
    key = (
        f"{request.user_sub}/"
        f"{now.year:04d}/{now.month:02d}/{now.day:02d}/"
        f"{submission_id}.json"
    )
    payload = {
        "id": submission_id,
        "userId": request.user_sub,
        "email": request.user_email,
        "text": text,
        "createdAt": now.isoformat(),
    }
    s3_client.put_object(
        Bucket=S3_BUCKET_NAME,
        Key=key,
        Body=json.dumps(payload, ensure_ascii=False),
        ContentType="application/json",
    )
    return jsonify(payload), 201


@app.route("/api/submissions", methods=["GET"])
@require_auth
def list_submissions():
    prefix = f"{request.user_sub}/"
    paginator = s3_client.get_paginator("list_objects_v2")
    pages = paginator.paginate(Bucket=S3_BUCKET_NAME, Prefix=prefix)

    items = []
    for page in pages:
        for obj in page.get("Contents", []):
            # Each submission is a small JSON object; individual GETs are simple
            # but scale linearly with submission count. For large datasets a
            # prefix-based listing combined with S3 Select or a metadata index
            # (e.g. DynamoDB) would be preferable.
            raw = s3_client.get_object(Bucket=S3_BUCKET_NAME, Key=obj["Key"])
            items.append(json.loads(raw["Body"].read()))

    # Sort newest first
    items.sort(key=lambda x: x.get("createdAt", ""), reverse=True)

    # Group by year/month/date
    grouped: dict = {}
    for item in items:
        created = item.get("createdAt", "")
        try:
            dt = datetime.fromisoformat(created)
            year = str(dt.year)
            month = f"{dt.month:02d}"
            day = f"{dt.day:02d}"
        except ValueError:
            year, month, day = "unknown", "unknown", "unknown"
        grouped.setdefault(year, {}).setdefault(month, {}).setdefault(day, []).append(item)

    return jsonify({"submissions": grouped, "total": len(items)})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 8000)), debug=False)
