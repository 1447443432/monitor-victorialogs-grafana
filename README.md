# VictoriaLogs + Grafana 监控镜像

将 VictoriaLogs、Grafana 和 VictoriaLogs Grafana 数据源插件打包为单容器镜像，用于 MongoDB 慢查询日志采集、存储和查询展示。

## 版本

| 组件 | 版本 |
|---|---|
| 基础镜像 | Alpine 3.23 |
| VictoriaLogs | v1.43.1 |
| Grafana | 13.1.1_29761037902 |
| VictoriaLogs Grafana 数据源插件 | v0.23.5 |
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
├── Dockerfile
├── docker-compose.yaml
├── .image-build.env             # 镜像 workflow 项目配置
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
├── grafana_13.1.1_29761037902_linux_amd64.tar.gz
├── grafana_13.1.1_29761037902_linux_arm64.tar.gz
├── victoria-logs-linux-amd64-v1.43.1.tar.gz
├── victoria-logs-linux-arm64-v1.43.1.tar.gz
└── victoriametrics-logs-datasource-v0.23.5.tar.gz
~~~

如果构建包显示为几十字节的文本文件，说明 LFS 对象没有拉取完整。

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
registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-monitor-victorialogs-grafana-amd64:1.0.0
registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-monitor-victorialogs-grafana-arm64:1.0.0
~~~

镜像名带有阿里云 Registry 前缀不代表已经推送到阿里云；本地构建只会创建本地镜像。

## 使用 Docker Compose

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

生产环境必须修改账号密码，并同步修改 Grafana 数据源认证配置。

持久化目录：

~~~text
/data/victorialogs  -> /data/victorialogs
/data/grafana       -> /usr/local/grafana/data
~~~

## 主要配置

运行参数在 docker-compose.yaml 的 environment 中配置。

VictoriaLogs 常用参数：

| 变量 | 作用 |
|---|---|
| VL_STORAGE_DATA_PATH | 数据目录 |
| VL_HTTP_LISTEN_ADDR | HTTP 监听地址 |
| VL_HTTP_AUTH_USERNAME / VL_HTTP_AUTH_PASSWORD | Basic Auth |
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
| GRAFANA_VL_BASIC_AUTH_USER / GRAFANA_VL_BASIC_AUTH_PASSWORD | 数据源认证 |

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

### 手动运行

在 GitHub Actions → Image Make → Run workflow 中选择：

| operation | 说明 |
|---|---|
| build-release | 构建镜像并创建 GitHub Release，不推送阿里云 |
| build-push-release | 构建镜像、推送阿里云并创建 GitHub Release |
| pull-release | 拉取已有阿里云镜像并创建 GitHub Release |

架构可选择 amd64、arm64 或 all。

### GitHub Secrets

如需推送阿里云，配置：

~~~text
ALIYUN_REGISTRY_USERNAME
ALIYUN_REGISTRY_PASSWORD
~~~

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

