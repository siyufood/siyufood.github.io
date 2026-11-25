# 思雨食品 ERP · GitHub Pages + 本地后端

石门思雨食品有限公司 ERP V3.6 的 GitHub Pages 部署工程。

- Pages 入口：<https://siyufood.github.io>
- 前端：Vue 2 + Ant Design Vue，由 GitHub Actions 自动构建并发布
- 后端镜像：GitHub Actions 构建后推送 `ghcr.io/siyufood/siyu-erp-backend`
- 本地运行：Windows 便携版 MariaDB + Redis + JRE 8 + Caddy + ngrok；如本机已有 MySQL/Redis，可直接复用现有数据
- 数据：保存在本机 MySQL/MariaDB；GitHub 不托管数据库

> GitHub Pages 只托管静态前端；后端、MySQL、Redis 始终在本机运行。GitHub Packages 只保存后端镜像，不运行数据库。

## 架构

```text
浏览器
  └─ https://siyufood.github.io          (GitHub Pages 静态前端)
       └─ https://xxxx.ngrok.app/jshERP-boot  (ngrok HTTPS)
            └─ 本机 Caddy :9999          (CORS + 反向代理)
                 └─ Spring Boot :9998    (ERP 后端)
                      ├─ MySQL/MariaDB :3307   (本机数据)
                      └─ Redis :6379     (本机缓存)
```

本机 `9999` 是 Caddy API 网关，`9998` 是后端。这样 Pages 的 HTTPS 请求不会触发浏览器混合内容拦截，跨域预检也由 Caddy 统一处理。

> 本机如已运行 MySQL/MariaDB 或 Redis，请直接在 `deploy/local/.env` 写现有端口与账号，脚本会复用现有服务、不覆盖数据；只有端口空闲时才会启动便携版。

## 一、GitHub Pages 首次启用

1. 打开仓库 `siyufood/siyufood.github.io` 的 **Settings → Pages**。
2. **Source** 选择 **GitHub Actions**，不要选 “Deploy from a branch”。
3. 推送到 `main` 后，`.github/workflows/deploy.yml` 会：
   - `npm ci` + `npm run build` 构建 Vue 前端；
   - 生成 `404.html`（Vue history 路由回退）和 `.nojekyll`；
   - 上传并部署到 Pages；
   - 同时构建后端 Docker 镜像并推送 GHCR。
4. 首次 Actions 完成后访问 <https://siyufood.github.io>。

如果 Pages 页面显示 404，先确认仓库名必须是 `siyufood.github.io`，并确认 Pages Source 已选择 **GitHub Actions**。

## 二、本机首次安装

在 PowerShell 中执行：

```powershell
cd E:\思雨食品ERP\siyu-erp-pages
.\deploy\local\bootstrap.ps1
```

会下载并解压到 `deploy/local/.tools`：

- MariaDB 10.11.10（约 90 MB）
- Temurin JRE 8（约 40 MB）
- Redis 5.0.14.1（约 12 MB）
- Caddy 2（约 15 MB）
- ngrok v3（约 12 MB）

首次运行会生成 `deploy/local/.env`，其中包含随机数据库/Redis密码。打开它填入 ngrok：

```dotenv
NGROK_AUTHTOKEN=你的 ngrok authtoken
NGROK_DOMAIN=可选，例如 siyu-erp.ngrok.app
```

`NGROK_DOMAIN` 建议使用 ngrok 控制台里的静态域名；没有静态域名也可以留空，启动脚本会读取随机公网地址并自动回写前端配置。

## 三、初始化数据库

```powershell
.\deploy\local\init-db.ps1
```

脚本会：

- 端口 `DB_PORT` 空闲时初始化本机便携 MariaDB 数据目录；已有数据库则直接复用；
- 创建 `jsh_erp` 数据库（已存在则保留）；
- 新库导入基础表、插件表、插件菜单、品牌配置、角色 4/10 的插件菜单授权；已有库只做幂等的品牌/菜单授权更新；
- 保留并启动本机 MariaDB。

默认验收账号仍为 `jsh / 123456`、`admin / 123456`。正式使用前请在系统内修改密码并清理演示资料。

## 四、启动本机全栈

```powershell
.\deploy\local\start-local.ps1
```

启动顺序：

1. MySQL/MariaDB `127.0.0.1:3307`（已有则复用）
2. Redis `127.0.0.1:6379`（已有则复用）
3. Spring Boot `127.0.0.1:9998`
4. Caddy `127.0.0.1:9999`
5. ngrok `ngrok http 9999`

启动脚本会自动读取 ngrok 公网地址，写入 `jshERP-web/public/config.js`，并 `git commit + git push`。推送后 GitHub Actions 重新构建 Pages，前端就指向当前 ngrok 地址。

如果 ngrok 是随机域名，每次重启后重新执行：

```powershell
.\deploy\local\start-local.ps1
```

或者只更新地址：

```powershell
.\deploy\local\set-api-base.ps1 -FromNgrok -Push
```

如果使用固定静态域名，配置只需写入一次，后续重启 ngrok 不需要重新推送。

## 五、停止本机全栈

```powershell
.\deploy\local\stop-local.ps1
```

数据目录 `deploy/local/data` 不会被删除；本机已有的 MySQL/Redis 系统服务也不会被停止。重新启动仍使用原来的数据。

## 六、Docker Compose（可选）

本机已安装 Docker Desktop 时，可以不使用便携版运行：

```powershell
Copy-Item .\deploy\local\.env.example .\deploy\local\.env
# 编辑 deploy/local/.env，填入 DB_PASSWORD / REDIS_PASSWORD / NGROK_AUTHTOKEN
docker compose --env-file .\deploy\local\.env up -d --build
ngrok http 9999
```

Compose 会启动 MariaDB、Redis、后端和 Caddy。数据库初始化脚本按顺序放在 `deploy/db-init`。

## 七、GitHub Packages

Actions 构建的镜像：

```text
ghcr.io/siyufood/siyu-erp-backend:latest
ghcr.io/siyufood/siyu-erp-backend:<commit-sha>
```

默认 GHCR 包是私有的。需要在本机拉取时：

```powershell
docker login ghcr.io -u siyufood
docker pull ghcr.io/siyufood/siyu-erp-backend:latest
```

也可以在 GitHub 的 Package 设置中把包改为 public。便携版本机运行直接使用仓库内的 `deploy/backend/jshERP.jar`，不依赖 GHCR。

## 八、关键文件

```text
.github/workflows/deploy.yml            Pages + GHCR 工作流
jshERP-web/                             Vue 前端源码
jshERP-boot/                            Spring Boot 源码（镜像使用预构建 JAR）
jshERP-plugin-suite/                    插件源码
deploy/backend/jshERP.jar               后端可执行 JAR
deploy/backend/plugins/                 插件 JAR
deploy/backend/Dockerfile               后端镜像
deploy/caddy/Caddyfile                  CORS + 反向代理
deploy/db-init/                         Docker 数据库初始化顺序
deploy/local/                           Windows 便携版启动脚本
sql/                                    基础库与品牌 SQL
plugins/                                插件表、菜单、授权 SQL
```

## 九、常见问题

**Pages 打开后登录失败**

1. 确认本机 `start-local.ps1` 正在运行；
2. 确认 `jshERP-web/public/config.js` 里的 `apiBase` 是当前 ngrok HTTPS 地址；
3. 确认 Actions 已重新部署完成；
4. 浏览器控制台若出现 CORS，检查 Caddy 是否监听 9999、ngrok 是否穿透 9999。

**ngrok 提示 authtoken 缺失**

在 <https://dashboard.ngrok.com/get-started/your-authtoken> 复制 token，填入 `deploy/local/.env` 的 `NGROK_AUTHTOKEN`。

**本机 3306 / 3307 / 6379 / 9999 被占用**

本机已有 MySQL 时不要把 `DB_PORT` 改成已占用端口；本项目默认复用 `3307` 的现有库、`6379` 的现有 Redis。`9999` 必须是空闲端口或被本项目的 Caddy 占用；如旧的 ERP 后端仍在 `9999`，先停止旧后端再运行 `start-local.ps1`。不要直接删除 `deploy/local/data`，否则会丢失便携库数据。

**GitHub Actions 构建前端失败**

查看 Actions 日志中的 `npm ci` / `npm run build`。前端使用 Node 16 构建，工作流已固定 `ubuntu-22.04`。

**后端镜像构建失败**

确认 `deploy/backend/jshERP.jar` 和 `deploy/backend/plugins/jsh-plugin-suite-1.0.0.jar` 已提交；`deploy/backend/Dockerfile` 使用预构建 JAR，不在 Actions 里重新编译 Java。
