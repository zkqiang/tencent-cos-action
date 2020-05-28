## 简介

该 [GitHub Action](https://help.github.com/cn/actions) 用于调用腾讯云
[coscmd](https://cloud.tencent.com/document/product/436/10976)
工具，实现对象存储的批量上传、下载、删除等操作。

## workflow 示例

在目标仓库中创建 `.github/workflows/xxx.yml` 即可，文件名任意，配置参考如下：

```yaml
name: CI

on:
  push:
    branches:
      - master

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout master
        uses: actions/checkout@v2
        with:
          ref: master

      - name: Setup node
        uses: actions/setup-node@v1
        with:
          node-version: "10.x"

      - name: Build project
        run: yarn && yarn build

      - name: Upload COS
        uses: zkqiang/tencent-cos-action@v0.1.0
        with:
          args: delete -r -f / && upload -r ./dist/ /
          secret_id: ${{ secrets.SECRET_ID }}
          secret_key: ${{ secrets.SECRET_KEY }}
          bucket: ${{ secrets.BUCKET }}
          region: ap-shanghai
```

其中 `${{ secrets.SECRET_XXX }}` 是调用 settings 配置的密钥，防止公开代码将权限密钥暴露，添加方式如下：

![](https://static.zkqiang.cn/images/20200118171056.png-slim)

## 相关参数

以下参数均可参见
[coscmd 官方文档](https://cloud.tencent.com/document/product/436/10976)

| 参数 | 是否必传 | 备注 |
| --- | --- | --- |
| args | 是 | coscmd 命令参数，参见官方文档，多个命令用 ` && ` 隔开<br>如 `delete -r -f / && upload -r ./dist/ /` |
| secret_id | 是 | 从 [控制台-API密钥管理](https://console.cloud.tencent.com/cam/capi) 获取 |
| secret_key | 是 | 同上 |
| bucket | 是 | 对象存储桶的名称，包含后边的数字 |
| region | 是 | 对象存储桶的地区，[参见文档](https://cloud.tencent.com/document/product/436/6224) |
