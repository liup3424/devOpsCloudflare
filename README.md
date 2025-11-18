# LangChain RAG Q&A App

A simple **Retrieval-Augmented Generation (RAG)** Q&A application built with:

- **LangChain** + **FAISS** for retrieval  
- **FastAPI** for the HTTP API  
- **Docker** for containerization  
- **Terraform** + **AWS App Runner** for deployment  
- **Cloudflare** for custom domain

---

## Project Structure

```text
.
├── data/
│   └── data.txt              # Knowledge base text file
├── faiss_index/              # FAISS index folder (generated)
├── .github/
│   └── workflows/
│       └── deploy.yml        # GitHub Actions CI/CD workflow
├── app.py                    # FastAPI application (RAG API)
├── ingest.py                 # Build FAISS index from data.txt
├── main.tf                   # Terraform infrastructure
├── requirements.txt          # Python dependencies
├── Dockerfile                # Docker container definition
├── setup.sh                  # Local setup helper (venv + ingest)
└── README.md
```

## 1. Prerequisites

You will need:

- **AWS account** (example region: `us-east-1`)
- **AWS CLI** installed and configured
- **Terraform** ≥ 1.5
- **Docker** (with Buildx on Apple Silicon / M-series Mac)
- A **GitHub repository** for this project
- An **OpenAI API key**
- A **domain managed by Cloudflare** (for custom domain)

---

## 2. Local Development (Recommended Flow)

### 2.1 Set OpenAI environment variable

```bash
export OPENAI_API_KEY="your-api-key"
# optional overrides:
export OPENAI_MODEL="gpt-3.5-turbo"
export OPENAI_EMBEDDING_MODEL="text-embedding-3-small"
```

### 2.2 One-click local setup

Use the provided script to:

- Create a virtual environment in `.venv`
- Install dependencies
- Build the FAISS index into `./faiss_index`

```bash
chmod +x setup.sh
./setup.sh
```

If everything works, you should see something like:

- `.venv/` created
- `faiss_index/` generated

### 2.3 Activate venv & run the app

```bash
source .venv/bin/activate
uvicorn app:app --reload
```

Check locally:

- **Swagger UI**: http://localhost:8000/docs
- **Health check**: http://localhost:8000/health

Example request:

```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"question": "what are applications for relative value analysis?"}'
```

---

## 3. Docker Build & Local Run

**Important:** `setup.sh` already builds the FAISS index. Make sure `./faiss_index/` exists before building the image.

### 3.1 Build Docker image

**On M-series Mac** (ARM → linux/amd64 for AWS):

```bash
docker buildx build --platform linux/amd64 -t dev-ops-rag-app .
```

**On x86_64:**

```bash
docker build -t dev-ops-rag-app .
```

### 3.2 Run the container locally

```bash
docker run --rm -p 8000:8000 \
  -e OPENAI_API_KEY="your-api-key" \
  -e OPENAI_MODEL="gpt-3.5-turbo" \
  -e OPENAI_EMBEDDING_MODEL="text-embedding-3-small" \
  dev-ops-rag-app
```

Then:

```bash
curl http://localhost:8000/health

curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"question": "what are applications for relative value analysis?"}'
```

---

## 4. AWS Credentials & Terraform

### 4.1 Configure AWS credentials (for Terraform & local ECR operations)

You can either use `aws configure`:

```bash
aws configure
# AWS Access Key ID: <YOUR_AWS_ACCESS_KEY_ID>
# AWS Secret Access Key: <YOUR_AWS_SECRET_ACCESS_KEY>
# Default region name: us-east-1
# Default output format: json
```

or export env vars:

```bash
export AWS_ACCESS_KEY_ID=YOUR_AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=YOUR_AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=us-east-1
# (optional if using temporary creds)
# export AWS_SESSION_TOKEN=...
```

**In GitHub Actions**, we do not store access keys. CI uses OIDC + IAM role to get temporary credentials.

### 4.2 Terraform variables

Create `terraform.tfvars` in the repo root:

```hcl
github_org_or_user             = "your-github-username-or-org"
github_repo_name               = "devOpsCloudflare"
openai_api_key                 = "your-openai-api-key"
manage_apprunner_via_terraform = true
```

`manage_apprunner_via_terraform = true` → Terraform also creates the App Runner service and outputs its ARN & URL.

### 4.3 Initialize & apply

```bash
terraform init
terraform plan
terraform apply
```

After a successful apply, grab the outputs:

```bash
terraform output github_actions_role_arn      # → GitHub secret AWS_IAM_ROLE_TO_ASSUME
terraform output ecr_repository_name          # → GitHub secret ECR_REPOSITORY
terraform output apprunner_service_arn        # → GitHub secret APP_RUNNER_ARN
terraform output apprunner_url                # → default App Runner URL
```

---

## 5. CI/CD with GitHub Actions (deploy.yml)

The workflow in `.github/workflows/deploy.yml`:

1. Triggers on push to `main`
2. Uses OIDC to assume the IAM role created by Terraform (`github-actions-deploy-role`)
3. Logs in to Amazon ECR
4. Builds & pushes the Docker image (tagged with short Git SHA + `latest`)
5. Deploys the new image to AWS App Runner using `awslabs/amazon-app-runner-deploy@main`

### 5.1 Required GitHub Secrets

In **GitHub repo** → **Settings** → **Secrets and variables** → **Actions**:

- **`AWS_REGION`**
  - e.g. `us-east-1`
- **`ECR_REPOSITORY`**
  - value from `terraform output ecr_repository_name`
- **`APP_RUNNER_ARN`**
  - value from `terraform output apprunner_service_arn`
- **`AWS_IAM_ROLE_TO_ASSUME`**
  - value from `terraform output github_actions_role_arn`

**No `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` secrets in GitHub.** The workflow authenticates with AWS via OIDC and `aws-actions/configure-aws-credentials@v4`.

---

## 6. Custom Domain via Cloudflare (Optional)

Assume App Runner URL is:

```text
https://<random>.us-east-1.awsapprunner.com
```

You want:

```text
https://rag.yourdomain.com
```

**Steps:**

1. In **App Runner console** → your service → **Custom domains**
   - Add `rag.yourdomain.com`.

2. AWS will show:
   - 2× CNAME records for ACM validation (names starting with `_...rag.yourdomain.com`)
   - 1× CNAME record for the target:
     - `rag.yourdomain.com -> <random>.us-east-1.awsapprunner.com`

3. In **Cloudflare** → your zone → **DNS**:
   - Create the two ACM validation CNAMEs exactly as shown (Proxy: **DNS only**).
   - Create one CNAME:
     - **Name**: `rag`
     - **Target**: `<random>.us-east-1.awsapprunner.com`
     - Start with **DNS only** (after certificate Active, you may switch to **Proxied** if desired).

4. Wait until App Runner shows custom domain status **Active**, then test:

```bash
curl https://rag.yourdomain.com/health
curl https://rag.yourdomain.com/docs
```

---

## 7. API Summary

- **`GET /`** – Returns a simple JSON with service info.
- **`GET /health`** – Returns: `{"status": "healthy"}`
- **`POST /chat`** – 
  - Request body:
    ```json
    { "question": "Your question here" }
    ```
  - Response:
    ```json
    { "answer": "Helpful Answer: V4 ..." }
    ```

---

## 8. Environment Variables Summary

**Application (local & container):**

- `OPENAI_API_KEY` (required)
- `OPENAI_MODEL` (optional, default: `gpt-3.5-turbo`)
- `OPENAI_EMBEDDING_MODEL` (optional, default: `text-embedding-3-small`)

**Local AWS tooling (Terraform / manual ECR work):**

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (optional for temporary credentials)
- `AWS_DEFAULT_REGION` / `AWS_REGION` (e.g. `us-east-1`)

**In CI**, AWS credentials are obtained via OIDC → IAM role, so access keys are not stored in GitHub.
