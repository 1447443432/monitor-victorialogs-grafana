# VictoriaLogs + Grafana 监控镜像

将 VictoriaLogs、Grafana 和 VictoriaLogs Grafana 数据源插件打包为单容器镜像，用于 MongoDB 慢查询日志采集、存储和查询展示。

## 采集器兼容范围

- `1.0.0`：面向 Promtail 采集器的日志字段和 Dashboard 配置。
- `1.1.0` 及后续版本：面向 Grafana Alloy 采集器的日志字段和 Dashboard 配置。

本项目镜像本身不包含 Promtail 或 Alloy，职责是运行 VictoriaLogs、Grafana 及 VictoriaLogs 数据源插件。采集器负责采集、解析 MongoDB 慢查询日志并写入 VictoriaLogs；Dashboard 依赖采集器写入的字段和标签，例如 `job`、`ns`、`durationMillis`、`attr`、`planSummary` 和 `docsExamined`。使用 `1.1.0+` 时，应配套 Alloy 的采集配置。

### Alloy 日志字段约定

以下是 Dashboard 查询使用的日志字段/标签，不是容器环境变量。Alloy 采集 MongoDB 慢查询日志时，应将解析结果写入 VictoriaLogs，并保持这些字段名称：

| 字段/标签 | 用途 |
|---|---|
| `job` | 采集任务标识，Dashboard 默认匹配 `mongodb-*` |
| `ns` | MongoDB 命名空间，例如数据库和集合 |
| `durationMillis` | 慢查询耗时，单位为毫秒 |
| `attr` | 查询属性、command 或原始结构化内容 |
| `_msg` | 原始日志消息 |
| `planSummary` | 查询执行计划，例如 `COLLSCAN` |
| `docsExamined` | 扫描文档数量 |

容器环境变量（如 `VL_*`、`GRAFANA_*`）只负责配置 VictoriaLogs 和 Grafana 的运行参数，不负责配置 Alloy 采集流程。

VictoriaLogs 默认启用 HTTP Basic Auth。Alloy 向 `http://<victorialogs-host>:9428` 写入日志时，必须在 Alloy 的写入配置中使用 `MONITOR_AUTH_USERNAME` 和 `MONITOR_AUTH_PASSWORD` 对应的账号密码；Grafana 查询端由容器启动脚本自动复用同一套认证。

## 版本

| 组件 | 版本 |
|---|---|
| 基础镜像 | Alpine 3.23 |
| VictoriaLogs | v1.53.0 |
| Grafana | 13.2.4_38252365904 |
| VictoriaLogs Grafana 数据源插件 | v0.33.1 |
| 支持架构 | linux/amd64、linux/arm64 |

容器内同时运行 VictoriaLogs 和 Grafana：

- VictoriaLogs：9428 端口
- Grafana：3000 端口
- Grafana 启动命令：grafana server

## 目录结构

~~~text
.
├── .github/
│   ├── image-make/              # GitHub Actions 构建辅助脚本
│   └── workflows/image-make.yml # 镜像构建、打包、Release workflow
├── packages/                    # Git LFS 管理的离线构建包
├── provisioning/                # Grafana 数据源和 Dashboard 配置
├── scripts/entrypoint.sh        # VictoriaLogs/Grafana 启动脚本
├── scripts/download-packages.ps1 # 离线包下载、续传和校验
├── Dockerfile
├── Dockerfile.slim              # 可选：基于官方 Grafana slim 镜像
├── docker-compose.yaml
├── docker-compose.example.yaml  # 完整 Compose 配置示例
├── .image-build.env             # 镜像 workflow 项目配置
├── packages/package-manifest.yaml # 离线包版本、地址、校验码和发布时间
├── download-packages.cmd        # Windows 双击下载入口
├── build.sh                     # 本地镜像构建
└── export-image.sh              # 本地镜像导出
~~~

## 获取完整源码

构建包通过 Git LFS 存储。克隆后必须拉取 LFS 对象：

~~~bash
git lfs install
git clone https://github.com/1447443432/monitor-victorialogs-grafana.git
cd monitor-victorialogs-grafana
git lfs pull
git lfs ls-files
~~~

packages/ 目录应包含：

~~~text
packages/
├── grafana_13.2.4_38252365904_linux_amd64.tar.gz
├── grafana_13.2.4_38252365904_linux_arm64.tar.gz
├── victoria-logs-linux-amd64-v1.53.0.tar.gz
├── victoria-logs-linux-arm64-v1.53.0.tar.gz
└── victoriametrics-logs-datasource-v0.33.1.tar.gz
~~~

如果构建包显示为几十字节的文本文件，说明 LFS 对象没有拉取完整。

当前镜像版本为 `1.1.0`。离线包的版本、文件名、官方下载地址、SHA256、大小、发布时间和代理策略统一维护在 `packages/package-manifest.yaml`；该文件是下载和构建所依据的唯一清单。

PowerShell 校验示例：

~~~powershell
Get-FileHash .\packages\<文件名> -Algorithm SHA256
~~~

也可以使用下载脚本。脚本会打印完整下载地址、代理状态和单行进度，支持基于临时 `.download` 文件的断点续传，完成后自动校验文件大小和 SHA256；只有校验成功并替换目标文件后，才会删除同一组件和架构下的旧包，下载或校验失败时会保留旧包。已存在且校验通过的包会直接跳过。

Windows 用户可以直接双击项目根目录的 `download-packages.cmd`，默认下载全部架构。也可以按架构执行：

~~~powershell
# 全部包
powershell -ExecutionPolicy Bypass -File .\scripts\download-packages.ps1 -Architecture all

# 只下载 amd64 或 arm64 包
powershell -ExecutionPolicy Bypass -File .\scripts\download-packages.ps1 -Architecture amd64
powershell -ExecutionPolicy Bypass -File .\scripts\download-packages.ps1 -Architecture arm64
~~~

代理开关和地址统一维护在 `packages/package-manifest.yaml` 的 `download.use_proxy` 和 `download.proxy` 字段中。全局代理地址为空时，脚本依次使用 `HTTPS_PROXY`、`HTTP_PROXY`，最后回退到 `http://127.0.0.1:7897`；Grafana 包当前按清单直连，VictoriaLogs 和数据源插件按清单走代理。

也可以在单个包记录中覆盖全局设置。例如在某个 `packages` 条目下增加 `use_proxy: false`，该下载链接会直连，其他包仍按全局配置执行：

~~~yaml
components:
  grafana:
    packages:
      amd64:
        use_proxy: false
~~~

单个包的 `use_proxy` 优先于全局设置；命令行 `-NoProxy` 优先级最高，会强制所有包直连。每次下载日志会打印该包实际使用的代理状态。

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\download-packages.ps1

# 临时指定本机代理地址；不会修改 YAML
powershell -ExecutionPolicy Bypass -File .\scripts\download-packages.ps1 -Proxy http://127.0.0.1:7897

# 临时强制所有包直连；不会修改 YAML
powershell -ExecutionPolicy Bypass -File .\scripts\download-packages.ps1 -NoProxy
~~~

### 缩减镜像构建

默认 `Dockerfile` 是完全离线构建版本，会把 Grafana 完整 tar 包放入镜像。需要缩减镜像时，可使用 `Dockerfile.slim`：它基于官方 `grafana/grafana:13.2.4-slim`，仍叠加项目内的 VictoriaLogs、数据源插件和 dashboard，但构建时需要访问 Docker Hub 拉取 Grafana 基础镜像。

本地构建示例：

~~~bash
docker build -f Dockerfile.slim --build-arg TARGETARCH=amd64 -t monitor-victorialogs-grafana:1.1.0 .
~~~

slim 模式不再使用 `packages/grafana_*.tar.gz`；离线环境继续使用默认 `Dockerfile`。

### Workflow 运行记录清理

每次 `Image Make` 完整成功后，`Clean old workflow runs` Job 会保留当前运行，并删除这个 Workflow 之前所有已完成的运行记录，包括成功、失败和取消的记录。排队中或进行中的运行不会删除；GitHub Release 和 Release 附件不受影响。清理 Job 使用独立的 `actions: write` 权限，清理失败不会改变已经完成的构建和发布结果。

## 本地构建

前置条件：

- Docker
- Docker Buildx
- Git LFS
- 当前主机架构与目标镜像架构一致，或使用可用的跨架构构建环境

构建 amd64：

~~~bash
./build.sh -a amd64
~~~

构建 arm64：

~~~bash
./build.sh -a arm64
~~~

禁用缓存构建：

~~~bash
./build.sh -a amd64 -n
~~~

清理 dangling 镜像和 BuildKit 缓存后构建：

~~~bash
./build.sh -a amd64 -cn
~~~

本地脚本生成的镜像名：

~~~text
registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-monitor-victorialogs-grafana-amd64:1.1.0
registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-monitor-victorialogs-grafana-arm64:1.1.0
~~~

镜像名带有阿里云 Registry 前缀不代表已经推送到阿里云；本地构建只会创建本地镜像。

## 使用 Docker Compose

精简配置使用 `docker-compose.yaml`；需要查看全部可覆盖变量时，参考 `docker-compose.example.yaml`。示例文件仅用于参考，不会被 Dockerfile 复制进镜像。

~~~bash
docker compose up -d
docker compose ps
docker compose logs -f hap-monitor-logs
~~~

访问：

- Grafana：http://<服务器地址>:3000/
- VictoriaLogs API：http://<服务器地址>:9428/

当前 Compose 示例使用以下测试账号：

- Grafana：admin / admin@123456
- VictoriaLogs：myuser / mypassword

生产环境必须修改 `MONITOR_AUTH_USERNAME` 和 `MONITOR_AUTH_PASSWORD`。未配置或值为空时，启动脚本使用默认值 `myuser` / `mypassword`，并将这套认证同时应用到 VictoriaLogs、Alloy 写入认证和 Grafana 数据源。对外只保留这一组认证变量。

### Compose 变量修改说明

`docker-compose.yaml` 中的变量按以下规则处理：

| 变量 | Compose 状态 | 默认值 | 说明 | 支持版本 |
|---|---|---|---|---|
| `MONITOR_AUTH_USERNAME` / `MONITOR_AUTH_PASSWORD` | 保留，生产环境必改 | `myuser` / `mypassword` | 唯一对外认证变量；同时用于 VictoriaLogs、Alloy 和 Grafana 数据源 | `1.1.0+` |
| `MONITOR_SERVICES` | Compose 已省略 | `all` | `all` 启动 VictoriaLogs 和 Grafana；`victorialogs` 或 `grafana` 可单独启动；未配置或为空时为 `all` | `1.1.0+` |
| `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` | 保留，必须修改 | `admin` / `admin@123456` | Grafana 管理员账号密码 | `1.0.0+` |
| `GRAFANA_SERVER_ROOT_URL` | 保留，按部署方式修改 | `%(protocol)s://%(domain)s:%(http_port)s/privatedeploy/mdy/monitor/victorialogs-grafana/` | 使用反向代理或子路径时填写外部访问地址 | `1.0.0+` |
| `GRAFANA_SERVER_SERVE_FROM_SUB_PATH` | 保留，需与 `ROOT_URL` 联动 | `true` | `GRAFANA_SERVER_ROOT_URL` 含子路径时为 `true`，根路径访问时为 `false` | `1.0.0+` |
| `GRAFANA_ALLOW_UNSIGNED_PLUGINS` | Compose 已省略 | `victoriametrics-logs-datasource` | 启动脚本默认允许当前插件加载；通常无需修改，插件名称变化时再覆盖 | `1.0.0+` |
| `TZ` | Compose 已省略 | `Asia/Shanghai` | 由启动脚本设置；需要时可通过 Compose 覆盖 | `1.0.0+` |
| `GOMEMLIMIT` | Compose 已省略 | `2GiB` | 由启动脚本设置；建议不超过 `mem_limit` | `1.0.0+` |
| `VL_STORAGE_DATA_PATH` | Compose 已省略 | `/data/victorialogs` | 修改目录时需同时修改 volumes | `1.0.0+` |
| `VL_HTTP_LISTEN_ADDR` | Compose 已省略 | `:9428` | 修改端口时需同步 ports 和 Alloy 写入地址 | `1.0.0+` |
| `GRAFANA_VL_DATASOURCE_URL` | Compose 已省略 | `http://127.0.0.1:9428` | 同一容器内 VictoriaLogs 地址 | `1.0.0+` |
| `VL_RETENTION_*`、并发、超时、日志级别 | Compose 已省略 | 见 `scripts/entrypoint.sh` | 按需通过 Compose environment 覆盖 | `1.0.0+` |

服务模式说明：使用 `MONITOR_SERVICES=grafana` 时，必须将 `GRAFANA_VL_DATASOURCE_URL` 改为外部 VictoriaLogs 地址；`MONITOR_SERVICES=victorialogs` 时只启动 VictoriaLogs，不启动 Grafana。

Compose 已省略的 VictoriaLogs 默认值固定如下；需要调整时再在 `environment` 中增加对应变量覆盖：

~~~text
VL_RETENTION_PERIOD=30d
VL_RETENTION_DISK_USAGE=50GiB
VL_MEMORY_ALLOWED_PERCENT=2
VL_MAX_CONCURRENT_INSERTS=4
VL_MAX_CONCURRENT_REQUESTS=2
VL_SEARCH_MAX_QUERY_DURATION=30s
VL_SEARCH_MAX_QUERY_TIMERANGE=24h
VL_SEARCH_MAX_QUEUE_DURATION=5s
VL_SEARCH_LOG_SLOW_QUERY_DURATION=3s
VL_INSERT_MAX_LINE_SIZE_BYTES=262144
VL_INSERT_MAX_FIELDS_PER_LINE=300
VL_SYSLOG_EXTRA_FIELDS_TCP={"job":"rsyslog"}
VL_LOGGER_LEVEL=INFO
~~~

`1.1.0` 没有新增 Docker Compose 必填环境变量；`1.1.0+` 的变化主要是面向 Alloy 的采集字段约定和 Dashboard 配置。Alloy 的采集配置不写入本镜像的 Compose 环境变量中，应在 Alloy 侧配置并将日志写入 VictoriaLogs。

持久化目录：

~~~text
/data/victorialogs  -> /data/victorialogs
/data/grafana       -> /usr/local/grafana/data
~~~

## 修改 Grafana 管理员账号

首次启动前修改 `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` 即可。已有 `/data/grafana` 数据时，环境变量不会覆盖已创建的账号。

修改当前登录用户密码：登录 Grafana，点击右上角用户图标，选择 `Change password`，输入原密码和新密码后确认。

忘记管理员密码时，在项目目录执行：

~~~bash
docker compose exec hap-monitor-logs /usr/local/grafana/bin/grafana cli --homepath=/usr/local/grafana admin reset-admin-password '<新密码>'
~~~

该命令仅重置密码，不删除 Dashboard 或其他 Grafana 数据。`GRAFANA_ADMIN_USER` 只用于首次创建管理员；已有实例需更换登录账号时，在 Grafana 中新建管理员账号并确认后再停用旧账号。不要删除 `/data/grafana`。

## 主要配置

运行参数在 docker-compose.yaml 的 environment 中配置。

VictoriaLogs 常用参数：

| 变量 | 作用 |
|---|---|
| VL_STORAGE_DATA_PATH | 数据目录 |
| VL_HTTP_LISTEN_ADDR | HTTP 监听地址 |
| MONITOR_AUTH_USERNAME / MONITOR_AUTH_PASSWORD | VictoriaLogs 和 Grafana 公共 Basic Auth |
| VL_RETENTION_PERIOD | 数据保留时间 |
| VL_RETENTION_DISK_USAGE | 最大磁盘占用 |
| VL_SEARCH_MAX_QUERY_DURATION | 查询超时 |
| VL_SEARCH_LOG_SLOW_QUERY_DURATION | 慢查询日志阈值 |
| VL_LOGGER_LEVEL | 日志级别 |

Grafana 常用参数：

| 变量 | 作用 |
|---|---|
| GRAFANA_SERVER_ROOT_URL | Grafana 根 URL |
| GRAFANA_SERVER_SERVE_FROM_SUB_PATH | 是否启用子路径 |
| GRAFANA_ADMIN_USER / GRAFANA_ADMIN_PASSWORD | 管理员账号 |
| GRAFANA_ALLOW_UNSIGNED_PLUGINS | 允许加载未签名插件 |
| GRAFANA_VL_DATASOURCE_URL | VictoriaLogs 地址 |
| MONITOR_AUTH_USERNAME / MONITOR_AUTH_PASSWORD | VictoriaLogs 和 Grafana 数据源认证 |

## GitHub Actions

Workflow 文件：

~~~text
.github/workflows/image-make.yml
~~~

Build Job 会启用 Git LFS，确保 packages/ 中的离线包是真实文件。其他 Job 不拉取 LFS，避免重复下载约 799 MB 的构建包。

### 自动 Push

提交到 master 后，workflow 读取 .image-build.env 中的：

~~~text
PUSH_OPERATION=auto
~~~

行为如下：

| 条件 | 实际操作 |
|---|---|
| 阿里云地址、账号密码完整 | 构建、推送阿里云、创建 GitHub Release |
| 阿里云配置不完整 | 构建、创建 GitHub Release，不推送阿里云 |

所以 build-release 成功不代表镜像已经推送到阿里云。

当前配置的阿里云镜像地址：

~~~text
registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-monitor-victorialogs-grafana-amd64:1.1.0
registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-monitor-victorialogs-grafana-arm64:1.1.0
~~~

推送成功后，可在部署主机验证：

~~~bash
docker login registry.cn-hangzhou.aliyuncs.com
docker pull registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-monitor-victorialogs-grafana-amd64:1.1.0
~~~

arm64 主机将镜像名中的 `amd64` 替换为 `arm64`。如果使用 `docker-compose.yaml`，还需按主机架构修改 `image`。

### 手动运行

在 GitHub Actions → Image Make → Run workflow 中选择：

| operation | 说明 |
|---|---|
| build-release | 构建镜像并创建 GitHub Release，不推送阿里云 |
| build-push-release | 构建镜像、推送阿里云并创建 GitHub Release |
| pull-release | 拉取已有阿里云镜像并创建 GitHub Release |

架构可选择 amd64、arm64 或 all。

手动推送阿里云时选择 `build-push-release`；仅构建并创建 Release 选择 `build-release`。`pull-release` 不重新构建，而是拉取已有的阿里云镜像并生成 Release 附件。

### GitHub 仓库配置

位置：`Settings` → `Secrets and variables` → `Actions`。

仓库 Variables：

| 名称 | 推荐值 | 说明 |
|---|---|---|
| `ALIYUN_REGISTRY` | `registry.cn-hangzhou.aliyuncs.com` | 阿里云 Registry 地址 |
| `ALIYUN_IMAGE_AMD64` | `registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-monitor-victorialogs-grafana-amd64:1.1.0` | amd64 推送地址 |
| `ALIYUN_IMAGE_ARM64` | `registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-monitor-victorialogs-grafana-arm64:1.1.0` | arm64 推送地址 |
| `PUSH_OPERATION` | `auto` | master push 时自动判断是否推送 |
| `ENABLE_ALIYUN_PUSH` | `true` | 允许推送阿里云 |

仓库 Secrets：

| 名称 | 说明 |
|---|---|
| `ALIYUN_REGISTRY_USERNAME` | 阿里云 Registry 用户名 |
| `ALIYUN_REGISTRY_PASSWORD` | 阿里云 Registry 密码或访问令牌 |

也兼容 `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`。账号必须具备目标命名空间 `hap-mdy` 的推送权限。Workflow 会在 Build Job 中登录仓库并执行 `docker push`；以构建日志和云仓库标签为准确认推送结果。

也兼容：

~~~text
REGISTRY_USERNAME
REGISTRY_PASSWORD
~~~

可选的 HAP 通知配置：

~~~text
HAP_WEBHOOK_URL
HAP_WEBHOOK_APP_KEY
HAP_WEBHOOK_SIGN
~~~

HAP Webhook 只在 GitHub Release 成功后发送。

### 构建产物

Build Job 会生成每个架构的镜像压缩包并上传为 GitHub Actions Artifact。Release Job 会将其汇总到 GitHub Release，并生成 SHA256 和 release-manifest.json。

## 常见问题

### tar: invalid magic 或 tar: short read

通常是 Git LFS 包没有被拉取。

本地执行：

~~~bash
git lfs install
git lfs pull
git lfs ls-files
~~~

GitHub Actions 的 Build Job 必须保留：

~~~yaml
- uses: actions/checkout@...
  with:
    lfs: true
~~~

### 构建成功但阿里云没有镜像

检查：

1. 是否选择了 build-push-release
2. 是否配置 ALIYUN_REGISTRY_USERNAME
3. 是否配置 ALIYUN_REGISTRY_PASSWORD
4. Build 日志中是否出现 docker push
5. Config Summary 中 Aliyun image 是否为 ready

仅看到 registry.cn-hangzhou.aliyuncs.com/hap-mdy/... 这样的本地镜像标签，不能证明已推送。

### Grafana 启动失败

确认镜像内使用的是：

~~~text
/usr/local/grafana/bin/grafana server
~~~

而不是旧命令 grafana-server web。

### workflow 提示 checkout action 找不到版本

workflow 固定使用有效的 actions/checkout commit。修改 action 版本后，先确认对应 tag 在官方仓库存在。

## 本地检查

不需要 Docker 也可以执行：

~~~bash
python .github/image-make/test_release.py
bash -n .github/image-make/build.sh
bash -n .github/image-make/package.sh
bash -n scripts/entrypoint.sh
~~~

实际镜像构建仍需要 Docker：

~~~bash
./build.sh -a amd64
~~~
