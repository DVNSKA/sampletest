# DevOps Assignment — Multi-Cloud Deployment

A Next.js 14 frontend + FastAPI backend deployed to **AWS** and **Azure** with full Infrastructure as Code, three environments per cloud, automated CI/CD, and production-grade architecture.

---

## Live URLs

### AWS (ECS Fargate + ALB)
| Environment | URL |
|---|---|
| Dev | http://devops-assignment-dev-alb-136419091.ap-south-1.elb.amazonaws.com |
| Staging | http://devops-assignment-staging-alb-233079257.ap-south-1.elb.amazonaws.com |
| Prod | http://devops-assignment-prod-alb-1738265231.ap-south-1.elb.amazonaws.com |

### Azure (Container Apps)
| Environment | URL |
|---|---|
| Dev | https://devops-assign-dev-fe.icyplant-0fc40f5f.centralindia.azurecontainerapps.io |
| Staging | https://devops-assign-staging-fe.icyplant-0fc40f5f.centralindia.azurecontainerapps.io |
| Prod | https://devops-assign-prod-fe.icyplant-0fc40f5f.centralindia.azurecontainerapps.io |

---

## Architecture

### AWS — ECS Fargate + ALB

```
Internet
    │
    ▼
Application Load Balancer (Public Subnets)
    ├── /* ──────────────► Frontend ECS Task (Port 3000)
    └── /api/* ──────────► Backend ECS Task  (Port 8000)
                              ▲
                         Private Subnets
                         (Staging + Prod)
```

- **VPC** with dedicated CIDR per environment (10.0/10.1/10.2.0.0/16)
- **ALB** in public subnets with path-based routing rules
- **ECS Fargate** tasks in private subnets (staging/prod) or public subnets (dev — no NAT to save cost)
- **ECR** per environment with lifecycle policies (keep last 5 images)
- **IAM** least-privilege roles — separate execution role and task role
- **CloudWatch** logs + Container Insights (prod only)
- **Auto-scaling** on CPU 70% threshold (staging + prod)
- **Terraform state** in S3 with versioning and AES256 encryption

### Azure — Container Apps

```
Internet
    │
    ├──► Frontend Container App (External, HTTPS auto, Port 3000)
    │
    └──► Backend Container App  (External, HTTPS auto, Port 8000)

         Both inside: Container App Environment (Managed Networking)
```

- **Azure Container Apps** — serverless, no VPC or load balancer config needed
- **HTTPS automatic** — no certificate management required
- **ACR** (Azure Container Registry) per environment
- **Scale to zero** in dev — no cost when idle
- **Log Analytics Workspace** for monitoring
- **Terraform state** in Azure Storage Account
- Shared Container App Environment (free tier: 1 environment per subscription)

---

## Why Different Architectures?

| | AWS | Azure |
|---|---|---|
| Networking | Full VPC, explicit subnets, security groups | Fully managed, no config needed |
| Load Balancing | Explicit ALB with listener rules | Built into Container Apps ingress |
| HTTPS | Manual (requires ACM + domain) | Automatic |
| Cold starts | None (always warm) | Dev scales to zero |
| Registry auth | IAM role-based | Admin credentials via secrets |
| Operational overhead | Medium | Low |
| Cost model | Per task-hour | Per request + CPU/memory-second |

---

## Environment Differences

### AWS

| | Dev | Staging | Prod |
|---|---|---|---|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| NAT Gateway | ❌ | ✅ | ✅ |
| ECS Subnets | Public | Private | Private |
| CPU / Memory | 256 / 512MB | 512 / 1024MB | 1024 / 2048MB |
| Min Tasks | 1 | 1 | 2 |
| Max Tasks | 1 | 3 | 10 |
| Auto-scaling | ❌ | ✅ CPU 70% | ✅ CPU 70% |
| Log Retention | 7 days | 7 days | 30 days |
| Container Insights | ❌ | ❌ | ✅ |
| ALB Deletion Protection | ❌ | ❌ | ✅ |

### Azure

| | Dev | Staging | Prod |
|---|---|---|---|
| ACR SKU | Basic | Basic | Standard |
| Min Replicas | 0 (scale to zero) | 1 | 2 |
| Max Replicas | 2 | 3 | 10 |
| CPU | 0.25 vCPU | 0.5 vCPU | 1.0 vCPU |
| Memory | 0.5Gi | 1Gi | 2Gi |
| Cold starts | Yes | No | No |

---

## Project Structure

```
.
├── backend/
│   ├── app/main.py              # FastAPI app with /api/health, /api/message
│   └── requirements.txt
├── frontend/
│   ├── pages/index.js           # Next.js page
│   ├── next.config.js           # output: standalone
│   └── package.json
├── docker/
│   ├── backend/Dockerfile       # Single-stage Python, non-root user (UID 1001)
│   └── frontend/Dockerfile      # Multi-stage: deps → builder → runner
├── docker-compose.yml           # Local development
├── .github/
│   └── workflows/
│       ├── deploy-aws.yml       # AWS CI/CD pipeline
│       └── deploy-azure.yml     # Azure CI/CD pipeline
├── terraform/
│   ├── aws/
│   │   ├── modules/
│   │   │   ├── networking/      # VPC, subnets, IGW, NAT, route tables
│   │   │   ├── ecr/             # Container registries + lifecycle policies
│   │   │   ├── iam/             # ECS execution + task roles
│   │   │   ├── alb/             # Load balancer, target groups, listener rules
│   │   │   └── ecs/             # Cluster, task definitions, services, auto-scaling
│   │   └── environments/
│   │       ├── dev/main.tf
│   │       ├── staging/main.tf
│   │       └── prod/main.tf
│   └── azure/
│       ├── modules/
│       │   ├── acr/             # Azure Container Registry
│       │   └── container-apps/  # Environment + container apps
│       └── environments/
│           ├── dev/main.tf
│           ├── staging/main.tf
│           └── prod/main.tf
└── README.md
```

---

## CI/CD Pipeline (GitHub Actions)

| Branch | Deploys To |
|---|---|
| `dev` | AWS dev + Azure dev |
| `staging` | AWS staging + Azure staging |
| `main` | AWS prod + Azure prod |

### AWS Pipeline Steps
1. Detect environment from branch name
2. Configure AWS credentials (GitHub Secrets)
3. Login to ECR
4. Fetch ALB DNS for the target environment
5. Build backend image (`--platform linux/amd64`), tag `:latest` + `:git-sha`, push to ECR
6. Build frontend with `NEXT_PUBLIC_API_URL` baked in, push to ECR
7. Force new ECS deployment for both services
8. Wait for services to stabilize (rolling deploy)
9. Health check — `curl /api/health` on ALB, fail if unhealthy

---

## Local Development

```bash
docker-compose up --build

# Frontend: http://localhost:3000
# Backend:  http://localhost:8000/api/health
```

---

## Manual Deploy

### AWS

```bash
# Login
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin 380652644852.dkr.ecr.ap-south-1.amazonaws.com

# Build and push backend
docker build --platform linux/amd64 \
  -t 380652644852.dkr.ecr.ap-south-1.amazonaws.com/devops-assignment-dev-backend:latest \
  -f docker/backend/Dockerfile ./backend
docker push 380652644852.dkr.ecr.ap-south-1.amazonaws.com/devops-assignment-dev-backend:latest

# Build and push frontend
docker build --platform linux/amd64 \
  --build-arg NEXT_PUBLIC_API_URL=http://<alb-dns> \
  -t 380652644852.dkr.ecr.ap-south-1.amazonaws.com/devops-assignment-dev-frontend:latest \
  -f docker/frontend/Dockerfile ./frontend
docker push 380652644852.dkr.ecr.ap-south-1.amazonaws.com/devops-assignment-dev-frontend:latest

# Force redeploy
aws ecs update-service --cluster devops-assignment-dev \
  --service devops-assignment-dev-backend --force-new-deployment --region ap-south-1
aws ecs update-service --cluster devops-assignment-dev \
  --service devops-assignment-dev-frontend --force-new-deployment --region ap-south-1
```

### Azure

```bash
az acr login --name devopsassignmentdevacr

docker build --platform linux/amd64 \
  -t devopsassignmentdevacr.azurecr.io/backend:latest \
  -f docker/backend/Dockerfile ./backend
docker push devopsassignmentdevacr.azurecr.io/backend:latest

az containerapp update \
  --name devops-assign-dev-be \
  --resource-group devops-assignment \
  --image devopsassignmentdevacr.azurecr.io/backend:latest
```

### Terraform

```bash
cd terraform/aws/environments/dev
terraform init && terraform apply -auto-approve

cd terraform/azure/environments/dev
terraform init && terraform apply -auto-approve
```

---

## Security

- Non-root containers — frontend (nextjs, UID 1001) and backend (appuser, UID 1001)
- Least-privilege IAM — separate ECS execution role and task role
- Private subnets — ECS tasks in staging/prod not internet-accessible directly
- ECR image scanning — enabled on push
- No secrets in images or git — `.gitignore` excludes `.terraform/`, state files
- S3 state encryption — AES256, versioning enabled
- GitHub Secrets — AWS credentials stored encrypted, never in logs
- Dedicated CI/CD IAM user — minimal permissions only (ECS, ECR, ELB read)

---

## API Endpoints

| Endpoint | Method | Response |
|---|---|---|
| `/api/health` | GET | `{"status": "healthy", "message": "Backend is running successfully"}` |
| `/api/message` | GET | `{"message": "You've successfully integrated the backend!"}` |

---

## Known Limitations

| Item | Decision |
|---|---|
| HTTPS on AWS | Requires domain + ACM. HTTP sufficient for demo |
| NAT Gateway in dev | Removed to save ~$32/month |
| Azure shared environment | Free tier allows 1 Container App Environment per subscription |
| DynamoDB state locking | Not used — single operator, S3 versioning sufficient |
| WAF / DDoS protection | Out of scope for this assignment |
| IAM user vs root | Root account used — should use IAM user with MFA in production |