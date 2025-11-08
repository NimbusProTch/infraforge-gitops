# Simple API - InfraForge Demo Application

A lightweight Python Flask REST API to demonstrate the GitOps workflow.

## Features

- ✅ Health check endpoints (`/health`, `/ready`)
- ✅ Version information (`/version`)
- ✅ Echo endpoint for testing (`/echo`)
- ✅ Environment variables display (`/env`)
- ✅ Multi-stage Docker build
- ✅ Production-ready with Gunicorn
- ✅ Non-root user
- ✅ Health checks

## Endpoints

- `GET /` - Welcome message
- `GET /health` - Health check (liveness probe)
- `GET /ready` - Readiness check
- `GET /version` - Version and build information
- `POST /echo` - Echo back JSON payload
- `GET /env` - Show environment variables (filtered)

## Local Development

```bash
# Install dependencies
cd apps/simple-api/src
pip install -r requirements.txt

# Run locally
python app.py

# Test
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/version
```

## Docker Build

```bash
# Build
docker build -t simple-api:latest apps/simple-api/

# Run
docker run -p 8080:8080 -e APP_VERSION=1.0.0 simple-api:latest

# Test
curl http://localhost:8080/health
```

## CI/CD

GitHub Actions automatically:
1. Builds Docker image on push to main
2. Pushes to ECR
3. Updates `values.yaml` with new image tag
4. ArgoCD auto-syncs within 30 seconds

## Environment Variables

- `APP_VERSION` - Application version (default: 1.0.0)
- `BUILD_ID` - Build/commit ID
- `ENVIRONMENT` - Environment name (dev/prod)
- `PORT` - Server port (default: 8080)
- `DEBUG` - Enable debug mode (default: false)
