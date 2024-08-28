# Image Sync SWR

基于 GitHub Actions 的能力，将 Docker Hub 或其他公开仓库中的镜像同步至华为云容器镜像服务（SWR）。

## GitHub Actions 使用说明

请先在仓库的 Settings -> Security -> Secrets and variables -> Actions 中添加以下几个 Secrets：

- `HCLOUD_ACCESS_KEY`: 华为云 Access Key ID
- `HCLOUD_SECRET_KEY`: 华为云 Secret Access Key

### 手动同步镜像（`sync-images-manually.yml`）

手动触发同步镜像，触发时根据页面提示输入相关信息。
