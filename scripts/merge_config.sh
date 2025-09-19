#!/bin/bash

# 配置文件合并脚本
# 参数: 芯片平台 分支名称 配置类型

set -euxo pipefail

CHIP_PLATFORM=$1
BRANCH=$2
CONFIG_TYPE=$3

echo "正在合并配置文件: $CHIP_PLATFORM $BRANCH $CONFIG_TYPE"

# 根据分支确定基础配置文件
case $BRANCH in
    "immwrt")
        BRANCH_CONFIG="configs/imm_base.config"
        ;;
    "openwrt")
        BRANCH_CONFIG="configs/op_base.config"
        ;;
    "libwrt")
        BRANCH_CONFIG="configs/lib_base.config"
        ;;
    *)
        echo "错误: 未知分支 $BRANCH"
        exit 1
        ;;
esac

# 根据配置类型确定软件包配置文件
case $CONFIG_TYPE in
    "Pro")
        PACKAGE_CONFIG="configs/Pro.config"
        ;;
    "Max")
        PACKAGE_CONFIG="configs/Max.config"
        ;;
    "Ultra")
        PACKAGE_CONFIG="configs/Ultra.config"
        ;;
    *)
        echo "错误: 未知配置类型 $CONFIG_TYPE"
        exit 1
        ;;
esac

# 按优先级合并配置文件：芯片配置 + 分支配置 + 软件包配置
# 后面的配置会覆盖前面的同名配置项
cat configs/${CHIP_PLATFORM}_base.config $BRANCH_CONFIG $PACKAGE_CONFIG > .config

echo "配置文件合并完成"
