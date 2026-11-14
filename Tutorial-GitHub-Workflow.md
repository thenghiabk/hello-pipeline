# Tutorial: Luyện luồng Dev → Staging → Production với dự án Hello World

*Dành cho người mới bắt đầu · Thời gian: khoảng 60–90 phút · Chi phí: 0 đồng*

## Bạn sẽ làm được gì

Bạn sẽ xây một ứng dụng web Hello World cực nhỏ, rồi cho nó đi qua đúng luồng làm việc chuyên nghiệp đã nói ở trên:

1. Viết code và chạy thử trên máy bạn (Dev).
2. Đẩy code lên Git, hệ thống CI tự chạy test và build Docker image.
3. Test đạt thì tự động triển khai lên Staging.
4. Kiểm tra trên Staging.
5. Có người duyệt thì **cùng image đó** được triển khai lên Production.
6. Có lỗi thì rollback về phiên bản cũ.

Để không tốn tiền thuê server, tutorial này “mô phỏng” Staging và Production: hai container Docker chạy trên hai cổng khác nhau (8081 và 8080) với cấu hình riêng. Cách làm, script và pipeline giống hệt thật. Khi có VPS, bạn chỉ cần đổi bước triển khai cuối cùng (xem phần cuối bài).

## Chuẩn bị

- **Git** và một tài khoản **GitHub** (miễn phí).
- **Docker** (Docker Desktop trên Windows/macOS, Docker Engine trên Linux). Kiểm tra bằng `docker --version`.
- **Node.js 20 trở lên** để chạy thử ở máy (không bắt buộc, vì CI cũng chạy test). Kiểm tra bằng `node --version`.
- Một trình soạn code, ví dụ VS Code.
- Nếu dùng Windows: hãy chạy lệnh trong **Git Bash** hoặc **WSL2** để dùng được các lệnh bash trong bài.

## Phần 1: Tạo dự án (môi trường Dev)

Mở terminal và tạo cấu trúc thư mục:

```bash
mkdir hello-pipeline && cd hello-pipeline
git init -b main
mkdir test env
```

Tạo file **`package.json`**:

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

Tạo file **`server.js`**. Ứng dụng đọc tên môi trường và phiên bản từ biến môi trường, nên cùng một code chạy được ở mọi môi trường:

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
    res.end(`Hello World! Môi trường: ${APP_ENV} | Phiên bản: ${VERSION}\n`);
  });
}

if (require.main === module) {
  createServer().listen(PORT, () => {
    console.log(`Server chạy ở cổng ${PORT} (${APP_ENV})`);
  });
}

module.exports = { createServer };
```

Tạo file **`test/server.test.js`**:

```js
const test = require('node:test');
const assert = require('node:assert');
const { createServer } = require('../server');

function startServer() {
  return new Promise((resolve) => {
    const server = createServer().listen(0, '127.0.0.1', () => resolve(server));
  });
}

test('GET / trả về lời chào Hello World', async () => {
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

test('GET /health trả về ok', async () => {
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

Chạy thử ở máy bạn:

```bash
npm test      # cả hai test phải báo pass
npm start     # mở http://localhost:3000
```

Trình duyệt hiện: `Hello World! Môi trường: development | Phiên bản: dev`. Nhấn Ctrl+C để dừng. Vậy là bạn đã có môi trường **Dev**.

## Phần 2: Đóng gói bằng Docker

Tạo file **`Dockerfile`**:

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package.json server.js ./
ARG APP_VERSION=dev
ENV NODE_ENV=production APP_VERSION=$APP_VERSION
EXPOSE 3000
CMD ["node", "server.js"]
```

Tạo file **`.dockerignore`** (giữ image gọn):

```
node_modules
.git
.github
test
env
```

Build và chạy thử image:

```bash
docker build --build-arg APP_VERSION=v1 -t hello-pipeline:v1 .
docker run --rm -p 3000:3000 hello-pipeline:v1
```

Mở http://localhost:3000, bạn thấy `Môi trường: development` (giá trị mặc định). Nhấn Ctrl+C để dừng. Lưu ý image chỉ chứa code và phiên bản, **không** chứa thông tin riêng của môi trường nào.

## Phần 3: Tách cấu hình theo môi trường

Tạo hai file cấu hình trong thư mục `env`.

**`env/staging.env`**

```
APP_ENV=staging
```

**`env/prod.env`**

```
APP_ENV=production
```

Trong dự án thật, các file này còn chứa địa chỉ database, API key... và **mật khẩu không bao giờ được commit lên Git** (hãy dùng GitHub Secrets hoặc dịch vụ quản lý bí mật). Ở bài này chỉ có tên môi trường nên an toàn để để trong repo.

Nếu dùng Windows, hãy lưu các file `.env` và `deploy.sh` với kiểu xuống dòng **LF** (VS Code hiển thị ở góc dưới bên phải). Kiểu CRLF sẽ làm giá trị biến bị dính ký tự thừa.

## Phần 4: Viết script triển khai dùng chung

Tạo file **`deploy.sh`**. Một script duy nhất cho mọi môi trường, nhận tên môi trường và phiên bản image:

```bash
#!/bin/bash
set -euo pipefail

ENV_NAME=$1
VERSION=$2
IMAGE="${IMAGE:-hello-pipeline}"

case "$ENV_NAME" in
  staging) PORT=8081 ;;
  prod)    PORT=8080 ;;
  *) echo "Môi trường không hợp lệ: $ENV_NAME (dùng staging hoặc prod)"; exit 1 ;;
esac

NAME="hello-$ENV_NAME"

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --env-file "env/$ENV_NAME.env" -p "$PORT:3000" "$IMAGE:$VERSION"

echo "Đang kiểm tra (smoke test) $ENV_NAME ..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://localhost:$PORT/health" >/dev/null; then
    echo "Triển khai thành công lên $ENV_NAME:"
    curl -fsS "http://localhost:$PORT/"
    exit 0
  fi
  sleep 1
done

echo "Smoke test thất bại!"
docker logs "$NAME"
exit 1
```

Script làm bốn việc: xóa container cũ, chạy container mới với file cấu hình đúng môi trường, kiểm tra `/health` để chắc ứng dụng đã sống, rồi in lời chào ra để bạn thấy môi trường và phiên bản.

## Phần 5: Luyện luồng thủ công trên máy bạn

Trước khi tự động hóa, hãy tự tay đi qua luồng một lần để hiểu từng bước.

**Bước 1: Phát hành v1 lên Staging rồi Production**

```bash
docker build --build-arg APP_VERSION=v1 -t hello-pipeline:v1 .
bash deploy.sh staging v1
bash deploy.sh prod v1
```

Kiểm tra: http://localhost:8081 hiện `Môi trường: staging | Phiên bản: v1`, còn http://localhost:8080 hiện `Môi trường: production | Phiên bản: v1`. Cùng một image, hai môi trường, hai cấu hình khác nhau.

**Bước 2: Phát hành v2 đúng quy trình**

Trong `server.js`, đổi `Hello World!` thành `Hello World v2!`, rồi:

```bash
npm test
docker build --build-arg APP_VERSION=v2 -t hello-pipeline:v2 .
bash deploy.sh staging v2
```

Mở cổng 8081 để kiểm tra. Prod (cổng 8080) vẫn là v1, đây chính là lợi ích của Staging. Hài lòng thì mới lên Prod:

```bash
bash deploy.sh prod v2
```

**Bước 3: Rollback**

Giả sử v2 có lỗi, bạn đưa Prod về v1 bằng đúng script đó, không cần build lại:

```bash
bash deploy.sh prod v1
```

**Bước 4: Dọn dẹp**

```bash
docker rm -f hello-staging hello-prod
```

## Phần 6: Tự động hóa bằng GitHub Actions

Bây giờ bạn giao các bước lặp đi lặp lại cho máy làm.

**6.1. Chuẩn bị repo trên GitHub**

1. Tạo file `.gitignore` chứa một dòng `node_modules`.
2. Trên GitHub, tạo repo mới tên `hello-pipeline`, chọn **Public** (xem lưu ý bên dưới), không tick thêm README.
3. Vào **Settings → Environments**, tạo hai environment: `staging` và `production`.
4. Trong environment `production`, bật **Required reviewers** và chọn chính bạn. Đây là chốt chặn “có người duyệt mới lên Prod”.

Lưu ý: tính năng bắt buộc duyệt của Environments miễn phí với repo public. Repo private cần gói GitHub trả phí.

**6.2. Tạo file pipeline**

Tạo file **`.github/workflows/deploy.yml`**:

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
      - name: Chạy test
        run: npm test
      - name: Đặt tên image (chữ thường)
        run: echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_ENV"
      - name: Đăng nhập registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build và đẩy image
        run: |
          docker build --build-arg APP_VERSION=${{ github.sha }} -t $IMAGE:${{ github.sha }} .
          docker push $IMAGE:${{ github.sha }}

  deploy-staging:
    needs: build-and-test
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - name: Đặt tên image (chữ thường)
        run: echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_ENV"
      - name: Đăng nhập registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Triển khai lên staging
        run: bash deploy.sh staging ${{ github.sha }}

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - name: Đặt tên image (chữ thường)
        run: echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_ENV"
      - name: Đăng nhập registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Triển khai lên production
        run: bash deploy.sh prod ${{ github.sha }}
```

Chú ý hai điểm: image chỉ được **build một lần** ở job đầu, hai job sau chỉ kéo đúng image đó về; và `deploy.sh` chính là script bạn đã luyện ở Phần 5.

**6.3. Đẩy code lên GitHub**

```bash
git add .
git commit -m "Hello pipeline: phiên bản đầu tiên"
git remote add origin https://github.com/<tên-github-của-bạn>/hello-pipeline.git
git push -u origin main
```

**6.4. Quan sát pipeline chạy**

Vào tab **Actions** của repo và theo dõi:

1. `build-and-test` chạy test, build rồi đẩy image lên GitHub Container Registry.
2. `deploy-staging` tự chạy ngay sau đó. Mở log bước “Triển khai lên staging”, bạn sẽ thấy dòng lời chào có `Môi trường: staging`.
3. `deploy-production` **dừng lại** với trạng thái chờ duyệt. Bấm **Review deployments**, tick `production`, bấm **Approve and deploy**.
4. Job chạy xong, log hiện `Môi trường: production` cùng mã commit làm phiên bản.

Lưu ý: ở bài này “server” là máy ảo tạm của GitHub nên container biến mất khi job kết thúc. Điều bạn đang luyện là luồng, cổng duyệt, smoke test và nguyên tắc “build một lần, triển khai nhiều nơi”, đúng cái mà pipeline thật cũng làm.

## Phần 7: Bài tập luyện thêm

**Bài 1: Phát hành bình thường.** Đổi lời chào trong `server.js`, chạy `npm test` ở máy, commit rồi push. Theo dõi pipeline và duyệt lên production.

**Bài 2: Test chặn lỗi.** Cố ý đổi lời chào thành “Xin chào” (test đang chờ chữ Hello World), rồi push. Pipeline sẽ đỏ ở `build-and-test` và hai job deploy không chạy. Đây là lý do CI tồn tại: lỗi bị chặn trước khi tới bất kỳ môi trường nào. Sửa lại và push để pipeline xanh.

**Bài 3: Từ chối duyệt.** Push một thay đổi, để staging chạy xong, rồi bấm **Reject** ở bước production. Staging đã có bản mới nhưng production không bị động tới.

**Bài 4: Rollback.** Chạy `git revert HEAD`, rồi `git push`. Pipeline chạy lại toàn bộ luồng với code cũ. Trong thực tế, cách nhanh hơn là triển khai lại image cũ đã có sẵn trong registry (giống `bash deploy.sh prod v1` ở Phần 5), vì không cần build lại.

**Bài 5 (nâng cao): Chạy đúng image do CI tạo.** Vào trang repo, mục **Packages**, mở package `hello-pipeline` và lấy mã commit của một phiên bản. Đặt package ở chế độ Public (Package settings), rồi chạy ở máy bạn:

```bash
docker run --rm -p 9000:3000 -e APP_ENV=production ghcr.io/<tên-github-viết-thường>/hello-pipeline:<mã-commit>
```

Đây chính là file đóng gói mà staging và production đã dùng, chỉ khác phần cấu hình.

## Xử lý lỗi thường gặp

- **`permission denied` khi chạy `deploy.sh`**: dùng `bash deploy.sh ...` như trong bài, hoặc chạy `chmod +x deploy.sh`.
- **`port is already allocated`**: có container hoặc ứng dụng khác đang chiếm cổng 8080/8081. Chạy `docker rm -f hello-staging hello-prod` hoặc đổi cổng trong script.
- **Đẩy image bị `denied` hoặc 403**: kiểm tra khối `permissions` có `packages: write` và tên image phải viết thường (đã xử lý bằng `${GITHUB_REPOSITORY,,}`).
- **Job production không chờ duyệt**: bạn chưa bật Required reviewers, hoặc đang dùng repo private ở gói miễn phí.
- **Môi trường hiện sai, ví dụ `production` kèm ký tự lạ**: file `.env` đang xuống dòng kiểu CRLF, hãy lưu lại bằng LF.
- **`npm test` không chạy test**: kiểm tra phiên bản Node (cần 20 trở lên) và file test nằm đúng thư mục `test`.

## Bước tiếp theo: lên server thật

Khi đã quen luồng này, bạn nâng cấp theo thứ tự:

1. Thuê một VPS nhỏ có cài Docker, tạo người dùng riêng cho việc triển khai và khóa SSH.
2. Lưu địa chỉ server và khóa SSH vào **Environment secrets** của GitHub, tách riêng cho `staging` và `production`.
3. Trong hai job deploy, thay lệnh `bash deploy.sh` bằng lệnh SSH vào server rồi chạy các lệnh `docker pull` và `docker run` với file cấu hình nằm trên server.
4. Tách hẳn Staging và Production ra hai server (hoặc hai tài khoản cloud), mỗi môi trường có database riêng.
5. Khi hệ thống lớn dần, mới cân nhắc Kubernetes và Terraform.

Nếu bạn muốn, hãy cho tôi biết nhà cung cấp VPS bạn định dùng, tôi sẽ viết sẵn phiên bản triển khai qua SSH cho bước 3.
