#!/bin/bash

# 发布包创建脚本
# 参数: 芯片平台

set -euxo pipefail

CHIP_PLATFORM=$1
ARTIFACTS_DIR="../../tmp/artifacts"
RELEASE_DIR="../../tmp/artifacts/release"

echo "创建发布包: $CHIP_PLATFORM"

# 创建发布目录
mkdir -p $RELEASE_DIR

# 打包固件文件
if [ -d "$ARTIFACTS_DIR/firmware" ] && [ -n "$(ls -A $ARTIFACTS_DIR/firmware)" ]; then
    echo "打包固件文件..."
    cd $ARTIFACTS_DIR/firmware
    tar -czf $RELEASE_DIR/${CHIP_PLATFORM}-firmware.tar.gz *
    echo "固件包创建完成"
fi

# 打包配置文件
if [ -d "$ARTIFACTS_DIR/config" ] && [ -n "$(ls -A $ARTIFACTS_DIR/config)" ]; then
    echo "打包配置文件..."
    cd $ARTIFACTS_DIR/config
    tar -czf $RELEASE_DIR/${CHIP_PLATFORM}-config.tar.gz *
    echo "配置包创建完成"
fi

# 打包日志文件
if [ -d "$ARTIFACTS_DIR/log" ] && [ -n "$(ls -A $ARTIFACTS_DIR/log)" ]; then
    echo "打包日志文件..."
    cd $ARTIFACTS_DIR/log
    tar -czf $RELEASE_DIR/${CHIP_PLATFORM}-log.tar.gz *
    echo "日志包创建完成"
fi

# 打包软件包
if [ -d "$ARTIFACTS_DIR/app/packages" ] && [ -n "$(ls -A $ARTIFACTS_DIR/app/packages)" ]; then
    echo "打包软件包..."
    cd $ARTIFACTS_DIR/app/packages
    tar -czf $RELEASE_DIR/${CHIP_PLATFORM}-app.tar.gz *
    echo "软件包创建完成"
fi

# 生成发布说明
cat > $RELEASE_DIR/README.md << EOF
# OpenWrt 固件发布

## 📦 固件信息
- 默认管理地址：192.168.111.1
- 默认用户：root  
- 默认密码：none
- 默认WIFI密码: 12345678

## 🖥️ 支持设备
- 京东云亚瑟 (jdcloud_re-ss-01)
- 京东云雅典娜 (jdcloud_re-cs-02)

## 📋 包含内容
- 各设备固件 (sysupgrade & factory)
- 配置文件 (.config)
- 构建信息 (.manifest, .config.buildinfo)
- 编译日志 (完整日志和错误日志)
- 软件包 (ipk文件)

## 👤 作者: Mary
- 发布时间: $(date +%Y-%m-%d)

## 🔧 第三方软件源
- tailscale: https://github.com/tailscale/tailscale
- sirpdboy: https://github.com/sirpdboy/luci-app-taskplan
- lucky: https://github.com/gdy666/luci-app-lucky
- momo: https://github.com/nikkinikki-org/OpenWrt-momo
- kenzok8: https://github.com/kenzok8/small-package (优先级最低)
EOF

echo "发布包创建完成"
