# Tutorial: Practice Dev → Staging → Production Workflow with Hello World Project

*For beginners · Estimated time: 60–90 minutes · Cost: Free*

## What You Will Learn

You will build a minimal Hello World web application and take it through a professional deployment workflow:

1. Write and test code locally (Dev).
2. Push code to Git; CI system automatically runs tests and builds the Docker image.
3. If tests pass, automatically deploy to Staging.
4. Verify on Staging.
5. Once approved, deploy the **exact same image** to Production.
6. Rollback to the previous version if errors occur.

To avoid server hosting costs, this tutorial "simulates" Staging and Production using two Docker containers running on different ports (8081 and 8080) with their own configurations. The methodology, scripts, and pipeline are identical to real-world setups. Once you have a VPS, you only need to change the final deployment step (see the end of this guide).

## Prerequisites

- **Git** and a free **GitHub** account.
- **Docker** (Docker Desktop on Windows/macOS, Docker Engine on Linux). Verify with `docker --version`.
- **Node.js 20 or higher** to run tests locally (optional, since CI also runs tests). Verify with `node --version`.
- A code editor, e.g., VS Code.
- Windows users: run commands in **Git Bash** or **WSL2** to use the bash commands in this guide.

## Part 1: Project Setup (Dev Environment)

Open your terminal and create the directory structure:

```bash
mkdir hello-pipeline && cd hello-pipeline
git init -b main
mkdir test env
```

Create **`package.json`**:

```json
{
  "name": "hello-pipeline",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "test": "node --test"
  }
}
```

Create **`server.js`**. The application reads the environment name and version from environment variables, allowing the same code to run across all environments:

```js
const http = require('http');

const APP_ENV = process.env.APP_ENV || 'development';
const VERSION = process.env.APP_VERSION || 'dev';
const PORT = process.env.PORT || 3000;

function createServer() {
  return http.createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ status: 'ok' }));
    }
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(`Hello World! Environment: ${APP_ENV} | Version: ${VERSION}\n`);
  });
}

if (require.main === module) {
  createServer().listen(PORT, () => {
    console.log(`Server running at port ${PORT} in ${APP_ENV} environment with version ${VERSION}`);
  });
}

module.exports = { createServer };
```

Create **`test/server.test.js`**:

```js
const test = require('node:test');
const assert = require('node:assert');
const { createServer } = require('../server');

function startServer() {
  return new Promise((resolve) => {
    const server = createServer().listen(0, '127.0.0.1', () => resolve(server));
  });
}

test('GET / should return Hello World', async () => {
  const server = await startServer();
  try {
    const { port } = server.address();
    const res = await fetch(`http://127.0.0.1:${port}/`);
    const body = await res.text();
    assert.strictEqual(res.status, 200);
    assert.match(body, /Hello World/);
  } finally {
    server.close();
    server.closeAllConnections();
  }
});

test('GET /health should return ok', async () => {
  const server = await startServer();
  try {
    const { port } = server.address();
    const res = await fetch(`http://127.0.0.1:${port}/health`);
    const data = await res.json();
    assert.strictEqual(data.status, 'ok');
  } finally {
    server.close();
    server.closeAllConnections();
  }
});
```

Test locally:

```bash
npm test      # both tests should pass
npm start     # open http://localhost:3000
```

Browser shows: `Hello World! Environment: development | Version: dev`. Press `Ctrl+C` to stop. You now have a working **Dev** environment.

## Part 2: Packaging with Docker

Create **`Dockerfile`**:

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package.json server.js ./
ARG APP_VERSION=dev
ENV NODE_ENV=production APP_VERSION=$APP_VERSION
EXPOSE 3000
CMD ["node", "server.js"]
```

Create **`.dockerignore`** (keep the image lean):

```
node_modules
.git
.github
test
env
```

Build and test run the image:

```bash
docker build --build-arg APP_VERSION=v1 -t hello-pipeline:v1 .
docker run --rm -p 3000:3000 hello-pipeline:v1
```

Open http://localhost:3000, you will see `Environment: development` (default value). Press `Ctrl+C` to stop. Notice that the image contains only code and version, **not** any environment-specific configuration.

## Part 3: Separating Environment Configuration

Create two configuration files in the `env` directory:

**`env/staging.env`**

```
APP_ENV=staging
```

**`env/prod.env`**

```
APP_ENV=production
```

In real projects, these files also contain database URLs, API keys... and **passwords must never be committed to Git** (use GitHub Secrets or a secret management service). In this tutorial, they only contain environment names, so keeping them in the repo is safe.

If using Windows, save `.env` and `deploy.sh` files with **LF** line endings (VS Code shows this in the bottom right corner). CRLF will append extraneous characters to variable values.

## Part 4: Writing a Shared Deployment Script

Create **`deploy.sh`**. A single script for all environments that accepts the environment name and image version:

```bash
#!/bin/bash
set -euo pipefail

ENV_NAME=$1
VERSION=$2

# Project configuration (modify this block when adapting to another project)
APP_NAME="${APP_NAME:-hello-pipeline}"
IMAGE="${IMAGE:-$APP_NAME}"
APP_PORT=3000
HEALTH_ENDPOINT="/health"

# Validate environment and assign host port
case "$ENV_NAME" in
  staging) HOST_PORT=8081 ;;
  prod)    HOST_PORT=8080 ;;
  *) echo "Invalid environment: $ENV_NAME (use staging or prod)"; exit 1 ;;
esac

NAME="$APP_NAME-$ENV_NAME"

# Stop and remove existing container if running
docker rm -f "$NAME" >/dev/null 2>&1 || true

# Run new container with environment configuration
docker run -d --name "$NAME" --env-file "env/$ENV_NAME.env" -p "$HOST_PORT:$APP_PORT" "$IMAGE:$VERSION"

# Run smoke test
echo "Running smoke test on $ENV_NAME ..."
for i in {1..10}; do
  if curl -fsS "http://localhost:$HOST_PORT$HEALTH_ENDPOINT" >/dev/null; then
    echo "Successfully deployed to $ENV_NAME!"
    exit 0
  fi
  sleep 1
done

# Smoke test failed
echo "Smoke test failed!"
docker logs "$NAME"
exit 1
```

The script performs four tasks: removes the old container, runs a new container with the appropriate environment configuration file, checks `/health` to ensure the application is healthy, and verifies that the deployment succeeded.

## Part 5: Manual Walkthrough on Your Machine

Before automating, practice the workflow manually to understand each step.

**Step 1: Release v1 to Staging then Production**

```bash
docker build --build-arg APP_VERSION=v1 -t hello-pipeline:v1 .
bash deploy.sh staging v1
bash deploy.sh prod v1
```

Verify: http://localhost:8081 displays `Environment: staging | Version: v1`, while http://localhost:8080 displays `Environment: production | Version: v1`. Same image, two environments, two different configurations.

**Step 2: Release v2 Following Proper Procedure**

In `server.js`, change `Hello World!` to `Hello World v2!`, then:

```bash
npm test
docker build --build-arg APP_VERSION=v2 -t hello-pipeline:v2 .
bash deploy.sh staging v2
```

Open port 8081 to verify. Prod (port 8080) is still running v1 — this is the core benefit of Staging. Once satisfied, promote to Prod:

```bash
bash deploy.sh prod v2
```

**Step 3: Rollback**

Suppose v2 has an issue; rollback Prod to v1 using the exact same script without rebuilding:

```bash
bash deploy.sh prod v1
```

**Step 4: Cleanup**

```bash
docker rm -f hello-pipeline-staging hello-pipeline-prod
```

## Part 6: Automation with GitHub Actions

Now automate these repetitive steps.

**6.1. Prepare GitHub Repository**

1. Create a `.gitignore` containing `node_modules`.
2. On GitHub, create a new repo named `hello-pipeline`, set to **Public** (see note below), without adding a README.
3. Go to **Settings → Environments**, create two environments: `staging` and `production`.
4. In the `production` environment, enable **Required reviewers** and select yourself. This is the approval gate before deploying to Prod.

Note: The Required Reviewers feature for Environments is free on public repositories. Private repositories require a paid GitHub plan.

**6.2. Create Pipeline File**

Create **`.github/workflows/deploy.yml`**:

```yaml
name: CI/CD

on:
  push:
    branches: [main]

permissions:
  contents: read
  packages: write

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - name: Run tests
        run: npm test
      - name: Set image name (lowercase)
        run: echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_ENV"
      - name: Log in to registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build and push image
        run: |
          docker build --build-arg APP_VERSION=${{ github.sha }} -t $IMAGE:${{ github.sha }} .
          docker push $IMAGE:${{ github.sha }}

  deploy-staging:
    needs: build-and-test
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - name: Set image name (lowercase)
        run: echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_ENV"
      - name: Log in to registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Deploy to staging
        run: bash deploy.sh staging ${{ github.sha }}

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - name: Set image name (lowercase)
        run: echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_ENV"
      - name: Log in to registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Deploy to production
        run: bash deploy.sh prod ${{ github.sha }}
```

Notice two key points: the image is **built only once** in the first job; the two subsequent deployment jobs pull that exact image; and `deploy.sh` is the exact script you practiced in Part 5.

**6.3. Push Code to GitHub**

```bash
git add .
git commit -m "Hello pipeline: initial release"
git remote add origin https://github.com/<your-github-username>/hello-pipeline.git
git push -u origin main
```

**6.4. Monitor Pipeline Execution**

Navigate to the **Actions** tab of your repo:

1. `build-and-test` runs tests, builds, and pushes the image to GitHub Container Registry.
2. `deploy-staging` automatically runs immediately after. Open the "Deploy to staging" step logs; you will see the greeting with `Environment: staging`.
3. `deploy-production` pauses with waiting for review status. Click **Review deployments**, check `production`, and click **Approve and deploy**.
4. Once the job completes, the logs display `Environment: production` with the commit hash as the version.

Note: In this tutorial, the "server" is GitHub's ephemeral virtual machine, so containers terminate when the job ends. What you are practicing is the workflow, approval gate, smoke tests, and the principle of "build once, deploy anywhere", exactly as in production pipelines.

## Part 7: Additional Exercises

**Exercise 1: Standard Release.** Change the greeting message in `server.js`, run `npm test` locally, commit, and push. Monitor the pipeline and approve deployment to production.

**Exercise 2: Tests Block Bad Code.** Intentionally break the test by changing the greeting without updating the test expectation, then push. The pipeline will fail at `build-and-test` and neither deploy job will run. This is why CI exists: errors are caught before reaching any environment. Fix and push to turn the pipeline green.

**Exercise 3: Reject Deployment.** Push a change, allow staging to complete, then click **Reject** on the production step. Staging gets the new version while production remains untouched.

**Exercise 4: Rollback.** Run `git revert HEAD`, then `git push`. The pipeline re-runs the entire workflow with the previous code. In production, a faster approach is redeploying an existing image from the registry (similar to `bash deploy.sh prod v1` in Part 5) without rebuilding.

**Exercise 5 (Advanced): Run the Exact CI Image Locally.** Go to your repo's **Packages** tab, open `hello-pipeline`, and copy the commit hash of a version. Set the package to Public (Package settings), then run locally:

```bash
docker run --rm -p 9000:3000 -e APP_ENV=production ghcr.io/<lowercase-github-username>/hello-pipeline:<commit-hash>
```

This is the exact packaged artifact used by staging and production, differing only in configuration.

## Troubleshooting Common Issues

- **`permission denied` when running `deploy.sh`**: Use `bash deploy.sh ...` as shown in the guide, or run `chmod +x deploy.sh`.
- **`port is already allocated`**: Another container or application is occupying port 8080/8081. Run `docker rm -f hello-pipeline-staging hello-pipeline-prod` or change the ports in the script.
- **Image push `denied` or 403**: Ensure the `permissions` block has `packages: write` and the image name is lowercase (handled by `${GITHUB_REPOSITORY,,}`).
- **Production job does not wait for approval**: You have not enabled Required reviewers, or you are using a private repository on a free plan.
- **Environment displayed incorrectly (e.g. `production` with strange trailing characters)**: The `.env` file uses CRLF line endings; re-save with LF.
- **`npm test` does not run tests**: Check your Node version (20+ required) and ensure the test file is located in the `test` directory.

## Next Steps: Deploying to a Real Server

Once comfortable with this workflow, upgrade progressively:

1. Rent a small VPS with Docker installed, set up a dedicated deployment user, and configure SSH keys.
2. Store server host address and SSH keys in GitHub **Environment secrets**, separated for `staging` and `production`.
3. In both deploy jobs, replace `bash deploy.sh` with an SSH command to the server executing `docker pull` and `docker run` with server-side environment files.
4. Completely separate Staging and Production across two distinct servers (or cloud accounts), each with its own database.
5. As the system scales, consider adopting Kubernetes and Terraform.
