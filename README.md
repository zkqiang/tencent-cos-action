## 简介

该 [GitHub Action](https://help.github.com/cn/actions) 用于调用腾讯云
[coscli](https://cloud.tencent.com/document/product/436/63142)
工具，实现对象存储的批量上传、下载、删除等操作。

## workflow 示例

在目标仓库中创建 `.github/workflows/xxx.yml` 即可，文件名任意，配置参考如下：

```yaml
name: Upload to COS

on:
  push:
    branches:
      - master

jobs:
  upload:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Upload build artifacts to COS
        uses: zkqiang/tencent-cos-action@v1
        with:
          commands: |  # 使用 `|` 表示依次执行多条命令
            rm -r -f cos://${{ secrets.COS_BUCKET }}/
            cp -r ./dist/ cos://${{ secrets.COS_BUCKET }}/
          secret_id: ${{ secrets.COS_SECRET_ID }}
          secret_key: ${{ secrets.COS_SECRET_KEY }}
          bucket: ${{ secrets.COS_BUCKET }}
          region: ${{ secrets.COS_REGION }}
```

其中 `${{ secrets.COS_SECRET_XXX }}` 是调用 settings 配置的密钥，防止公开代码将权限密钥暴露，添加方式：  
`Settings → Secrets and variables → Actions → New repository secret`

## 相关参数

| 参数 | 是否必传 | 备注 |
| --- | --- | --- |
| commands | 是 | coscli 命令列表，每行一条，按顺序执行，参见 [官方文档](https://cloud.tencent.com/document/product/436/63143) |
| secret_id | 是 | 从 [控制台-API密钥管理](https://console.cloud.tencent.com/cam/capi) 获取 |
| secret_key | 是 | 同上 |
| bucket | 是 | 对象存储桶的名称，包含后边的数字 |
| region | 是 | 对象存储桶的地区，[参见文档](https://cloud.tencent.com/document/product/436/6224) |
| coscli_version | 否 | coscli 版本号，如 `v1.0.8`。不指定时自动下载最新版本 |
