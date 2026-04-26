# reports-cataloguer

A web application that lets authenticated users submit text reports and browse their history, organised by year / month / date.

## Architecture

```
├── bin/          Deploy scripts
├── cf/           AWS CloudFormation templates
├── service/      Python (Flask) API backend
└── frontend/     React frontend
```

### AWS services used

| Service | Purpose |
|---------|---------|
| Amazon Cognito | Email/password authentication |
| Amazon S3 | Submission storage (`{userId}/{year}/{month}/{day}/{uuid}.json`) |
| Amazon ECS (Fargate) | Container hosting for the API |
| Amazon ECR | Docker image registry |
| Application Load Balancer | HTTP ingress for the ECS service |

---

## Local development

### Backend (`/service`)

```bash
cd service
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # edit with real Cognito / S3 values
flask run --port 8000
```

### Frontend (`/frontend`)

```bash
cd frontend
npm install
cp .env.example .env          # set REACT_APP_API_URL if not using proxy
npm start                     # proxies /api/* to http://localhost:8000
```

---

## Deployment

### Prerequisites

- AWS CLI configured with sufficient permissions
- Docker
- An existing VPC with public + private subnets

### One-time: create the CloudFormation templates bucket

```bash
aws s3 mb s3://my-cf-templates-bucket --region us-east-1
```

### Build & push the Docker image

```bash
export AWS_REGION=us-east-1
export APP_NAME=reports-cataloguer
./bin/build-and-push.sh v1.0.0
```

### Deploy all stacks

```bash
export CF_TEMPLATES_BUCKET=my-cf-templates-bucket
export VPC_ID=vpc-xxxxxxxx
export PUBLIC_SUBNET_1=subnet-xxxxxxxx
export PUBLIC_SUBNET_2=subnet-yyyyyyyy
export PRIVATE_SUBNET_1=subnet-aaaaaaaa
export PRIVATE_SUBNET_2=subnet-bbbbbbbb
export BUCKET_SUFFIX=$(aws sts get-caller-identity --query Account --output text)

./bin/deploy.sh v1.0.0
```

This deploys three nested CloudFormation stacks:

1. **`cf/cognito.yaml`** – Cognito User Pool + App Client
2. **`cf/s3.yaml`** – Submissions S3 bucket
3. **`cf/ecs.yaml`** – ECS Fargate cluster, ALB, task definition & service

After deployment the ALB DNS name is printed – this is the API base URL.

Point the frontend's `REACT_APP_API_URL` at that URL and run `npm run build`, then serve the static files (e.g. via S3 + CloudFront).

---

## API

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET`  | `/api/health` | — | Health check |
| `POST` | `/api/auth/login` | — | Email/password login |
| `POST` | `/api/auth/refresh` | — | Refresh access token |
| `POST` | `/api/submissions` | ✓ | Create a submission |
| `GET`  | `/api/submissions` | ✓ | List submissions (grouped by year/month/day) |

### Login request/response

```jsonc
// POST /api/auth/login
{ "email": "user@example.com", "password": "S3cur3P@ss" }

// 200 OK
{
  "accessToken": "…",
  "idToken": "…",
  "refreshToken": "…",
  "expiresIn": 3600
}
```

### Create submission

```jsonc
// POST /api/submissions  (Authorization: Bearer <idToken>)
{ "text": "My report text" }

// 201 Created
{
  "id": "uuid",
  "userId": "cognito-sub",
  "email": "user@example.com",
  "text": "My report text",
  "createdAt": "2024-01-15T10:30:00+00:00"
}
```

### List submissions

```jsonc
// GET /api/submissions  (Authorization: Bearer <idToken>)
// 200 OK
{
  "total": 2,
  "submissions": {
    "2024": {
      "01": {
        "15": [ { "id": "…", "text": "…", "createdAt": "…" } ]
      }
    }
  }
}
```