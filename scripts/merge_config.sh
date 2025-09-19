#!/bin/bash

# 配置文件合并脚本
# 参数: 芯片平台 分支名称 配置类型

set -euxo pipefail

# 获取脚本所在目录（相对于执行时的当前目录）
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
echo "脚本相对目录: $SCRIPT_DIR"

# 获取仓库根目录的绝对路径
if [[ "$SCRIPT_DIR" == "/"* ]]; then
    # 如果是绝对路径
    REPO_ROOT="$(dirname "$SCRIPT_DIR")"
else
    # 如果是相对路径
    REPO_ROOT="$(pwd)/$(dirname "$SCRIPT_DIR")"
    REPO_ROOT="$(dirname "$REPO_ROOT")"
fi

echo "脚本绝对目录: $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "仓库根目录: $REPO_ROOT"

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

# 芯片配置文件路径
CHIP_CONFIG="configs/${CHIP_PLATFORM}_base.config"

echo "芯片配置文件: $CHIP_CONFIG"
echo "分支配置文件: $BRANCH_CONFIG"
echo "软件包配置文件: $PACKAGE_CONFIG"

# 检查configs目录是否存在
if [ ! -d "configs" ]; then
    echo "错误: configs目录不存在"
    echo "当前目录: $(pwd)"
    echo "当前目录文件列表:"
    ls -la
    exit 1
fi

echo "configs目录文件列表:"
ls -la configs/

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
