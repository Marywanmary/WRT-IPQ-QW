#!/bin/bash

# 配置文件合并脚本
# 参数: 芯片平台 分支名称 配置类型

set -euxo pipefail

CHIP_PLATFORM=$1
BRANCH=$2
CONFIG_TYPE=$3

echo "正在合并配置文件: $CHIP_PLATFORM $BRANCH $CONFIG_TYPE"

# 获取仓库根目录路径
REPO_ROOT="../../../"

# 根据分支确定基础配置文件
case $BRANCH in
    "immwrt")
        BRANCH_CONFIG="${REPO_ROOT}configs/imm_base.config"
        ;;
    "openwrt")
        BRANCH_CONFIG="${REPO_ROOT}configs/op_base.config"
        ;;
    "libwrt")
        BRANCH_CONFIG="${REPO_ROOT}configs/lib_base.config"
        ;;
    *)
        echo "错误: 未知分支 $BRANCH"
        exit 1
        ;;
esac

# 根据配置类型确定软件包配置文件
case $CONFIG_TYPE in
    "Pro")
        PACKAGE_CONFIG="${REPO_ROOT}configs/Pro.config"
        ;;
    "Max")
        PACKAGE_CONFIG="${REPO_ROOT}configs/Max.config"
        ;;
    "Ultra")
        PACKAGE_CONFIG="${REPO_ROOT}configs/Ultra.config"
        ;;
    *)
        echo "错误: 未知配置类型 $CONFIG_TYPE"
        exit 1
        ;;
esac

# 芯片配置文件路径
CHIP_CONFIG="${REPO_ROOT}configs/${CHIP_PLATFORM}_base.config"

echo "芯片配置文件: $CHIP_CONFIG"
echo "分支配置文件: $BRANCH_CONFIG"
echo "软件包配置文件: $PACKAGE_CONFIG"

# 检查仓库根目录
echo "仓库根目录文件列表:"
ls -la $REPO_ROOT

# 检查配置文件目录是否存在
if [ ! -d "${REPO_ROOT}configs" ]; then
    echo "错误: configs目录不存在"
    exit 1
fi

echo "配置目录文件列表:"
ls -la ${REPO_ROOT}configs/

# 检查配置文件是否存在
if [ ! -f "$CHIP_CONFIG" ]; then
    echo "错误: 芯片配置文件 $CHIP_CONFIG 不存在"
    exit 1
fi

if [ ! -f "$BRANCH_CONFIG" ]; then
    echo "警告: 分支配置文件 $BRANCH_CONFIG 不存在，将创建空文件"
    touch "$BRANCH_CONFIG"
fi

if [ ! -f "$PACKAGE_CONFIG" ]; then
    echo "错误: 软件包配置文件 $PACKAGE_CONFIG 不存在"
    exit 1
fi

# 按优先级合并配置文件：芯片配置 + 分支配置 + 软件包配置
# 后面的配置会覆盖前面的同名配置项
cat "$CHIP_CONFIG" "$BRANCH_CONFIG" "$PACKAGE_CONFIG" > .config

echo "配置文件合并完成"
echo "生成的配置文件大小: $(wc -l .config | cut -d' ' -f1) 行"
