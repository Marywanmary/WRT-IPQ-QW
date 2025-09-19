#!/bin/bash

# 构建产物处理脚本
# 参数: 芯片平台 分支名称 配置类型

set -euxo pipefail

CHIP_PLATFORM=$1
BRANCH=$2
CONFIG_TYPE=$3

echo "开始处理构建产物: $CHIP_PLATFORM $BRANCH $CONFIG_TYPE"

# 创建产物目录结构
mkdir -p /tmp/artifacts/{firmware,config,log,app/packages}

# 进入OpenWrt源码目录
cd openwrt

# 从配置文件中自动检测目标设备
DEVICE_NAMES=()
while IFS= read -r line; do
    if [[ $line =~ CONFIG_TARGET_DEVICE_qualcommax_${CHIP_PLATFORM}_DEVICE_(.+)=y ]]; then
        DEVICE_NAMES+=("${BASH_REMATCH[1]}")
    fi
done < .config

echo "检测到的目标设备: ${DEVICE_NAMES[@]}"

# 为每个检测到的设备处理相关产物
for DEVICE in "${DEVICE_NAMES[@]}"; do
    echo "处理设备 $DEVICE 的产物..."
    
    # 处理固件文件
    for firmware in bin/targets/qualcommax/${CHIP_PLATFORM}/*${DEVICE}*.bin; do
        if [ -f "$firmware" ]; then
            filename=$(basename "$firmware")
            echo "处理固件: $filename"
            
            # 根据固件类型重命名
            if [[ $filename == *sysupgrade* ]]; then
                new_name="${BRANCH}-${CHIP_PLATFORM}-${DEVICE}-sysupgrade-${CONFIG_TYPE}.bin"
            elif [[ $filename == *factory* ]]; then
                new_name="${BRANCH}-${CHIP_PLATFORM}-${DEVICE}-factory-${CONFIG_TYPE}.bin"
            else
                new_name="${BRANCH}-${CHIP_PLATFORM}-${DEVICE}-${CONFIG_TYPE}.bin"
            fi
            
            cp "$firmware" "/tmp/artifacts/firmware/$new_name"
            echo "固件已复制: $new_name"
        fi
    done
    
    # 处理配置文件
    if [ -f ".config" ]; then
        cp .config "/tmp/artifacts/config/${BRANCH}-${CHIP_PLATFORM}-${DEVICE}-${CONFIG_TYPE}.config"
        echo "配置文件已复制"
    fi
    
    # 处理manifest文件
    for manifest in bin/targets/qualcommax/${CHIP_PLATFORM}/*${DEVICE}*.manifest; do
        if [ -f "$manifest" ]; then
            cp "$manifest" "/tmp/artifacts/config/${BRANCH}-${CHIP_PLATFORM}-${DEVICE}-${CONFIG_TYPE}.manifest"
            echo "Manifest文件已复制"
        fi
    done
    
    # 处理buildinfo文件
    for buildinfo in bin/targets/qualcommax/${CHIP_PLATFORM}/*${DEVICE}*.buildinfo; do
        if [ -f "$buildinfo" ]; then
            cp "$buildinfo" "/tmp/artifacts/config/${BRANCH}-${CHIP_PLATFORM}-${DEVICE}-${CONFIG_TYPE}.config.buildinfo"
            echo "Buildinfo文件已复制"
        fi
    done
done

# 处理软件包文件
echo "处理软件包文件..."
for ipk in bin/packages/*/*/*.ipk; do
    if [ -f "$ipk" ]; then
        # 允许覆盖同名文件（后续构建的包会覆盖之前的）
        cp "$ipk" "/tmp/artifacts/app/packages/" 2>/dev/null || true
    fi
done

echo "构建产物处理完成"
