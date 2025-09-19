#!/bin/bash

# OpenWrt构建管理脚本
# 功能：管理第三方软件源、重命名固件文件并准备构建产物
# 用法: 
#   1. 管理软件源: ./scripts/build-manager.sh manage-feeds <openwrt_dir>
#   2. 准备构建产物: ./scripts/build-manager.sh prepare-artifacts <repo_short> <config_type> <device> <chip>

COMMAND=$1

case $COMMAND in
    "manage-feeds")
        # 统一管理第三方软件源
        
        OPENWRT_DIR=$2
        
        # 检查OpenWrt目录是否存在
        if [ ! -d "$OPENWRT_DIR" ]; then
            echo "Error: OpenWrt directory $OPENWRT_DIR not found!"
            exit 1
        fi
        
        cd "$OPENWRT_DIR"
        
        echo "===== 管理第三方软件源 ====="
        
        # 定义 feeds.conf 文件路径
        FEEDS_CONF="feeds.conf.default"
        
        # 备份原始配置
        if [ -f "$FEEDS_CONF" ]; then
            cp "$FEEDS_CONF" "$FEEDS_CONF.bak"
            echo "已备份原始配置文件: $FEEDS_CONF.bak"
        fi
        
        # 清空或创建新的 feeds.conf.default 文件
        echo "src-link packages" > "$FEEDS_CONF"
        echo "src-link luci" >> "$FEEDS_CONF"
        
        # 添加第三方软件源
        echo "添加 tailscale 软件源..."
        echo "src-git tailscale https://github.com/tailscale/tailscale" >> "$FEEDS_CONF"
        
        echo "添加 taskplan 软件源..."
        echo "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan" >> "$FEEDS_CONF"
        
        echo "添加 lucky 软件源..."
        echo "src-git lucky https://github.com/gdy666/luci-app-lucky" >> "$FEEDS_CONF"
        
        echo "添加 momo 软件源..."
        echo "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo" >> "$FEEDS_CONF"
        
        echo "添加 small-package 软件源..."
        echo "src-git small-package https://github.com/kenzok8/small-package" >> "$FEEDS_CONF"
        
        # 同步到 feeds.conf
        echo "同步到 feeds.conf..."
        cp "$FEEDS_CONF" "feeds.conf"
        
        # 显示当前 feeds.conf 内容
        echo "===== 当前 feeds.conf 内容 ====="
        cat "$FEEDS_CONF"
        echo "=============================="
        
        # 更新软件源
        echo "更新软件源..."
        ./scripts/feeds update -a
        
        # 安装软件源
        echo "安装软件源..."
        ./scripts/feeds install -a
        
        # 修复配置文件（如果存在）
        if [ -f ".config" ]; then
            echo "修复配置文件..."
            cp .config .config.backup
            
            # 重新生成配置
            make defconfig
        fi
        
        echo "===== 软件源管理完成 ====="
        ;;
        
    "prepare-artifacts")
        # 重命名固件文件并准备构建产物
        
        REPO_SHORT=$2
        CONFIG_TYPE=$3
        DEVICE=$4
        CHIP=$5
        
        # 创建临时目录
        mkdir -p artifacts/${CHIP}-config
        mkdir -p artifacts/${CHIP}-log
        mkdir -p artifacts/${CHIP}-app
        mkdir -p artifacts/firmware
        
        # 固件重命名和复制
        for file in openwrt/bin/targets/qualcommax/${CHIP}/*.bin; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                # 提取固件类型（factory或sysupgrade）
                if [[ "$filename" == *"factory"* ]]; then
                    fw_type="factory"
                elif [[ "$filename" == *"sysupgrade"* ]]; then
                    fw_type="sysupgrade"
                else
                    continue
                fi
                
                # 新文件名：分支缩写-芯片变量-设备名称-固件类型-设备配置.bin
                new_filename="${REPO_SHORT}-${CHIP}-${DEVICE}-${fw_type}-${CONFIG_TYPE}.bin"
                cp "$file" "artifacts/firmware/$new_filename"
            fi
        done
        
        # 配置文件重命名和复制
        if [ -f "openwrt/.config" ]; then
            cp "openwrt/.config" "artifacts/${CHIP}-config/${REPO_SHORT}-${CHIP}-${DEVICE}-${CONFIG_TYPE}.config"
        fi
        
        if [ -f "openwrt/.config.manifest" ]; then
            cp "openwrt/.config.manifest" "artifacts/${CHIP}-config/${REPO_SHORT}-${CHIP}-${DEVICE}-${CONFIG_TYPE}.manifest"
        fi
        
        if [ -f "openwrt/.config.buildinfo" ]; then
            cp "openwrt/.config.buildinfo" "artifacts/${CHIP}-config/${REPO_SHORT}-${CHIP}-${DEVICE}-${CONFIG_TYPE}.config.buildinfo"
        fi
        
        # 日志文件复制
        if [ -f "openwrt/build.log" ]; then
            cp "openwrt/build.log" "artifacts/${CHIP}-log/${REPO_SHORT}-${CHIP}-${DEVICE}-${CONFIG_TYPE}-build.log"
        fi
        
        if [ -f "build-error.log" ]; then
            cp "build-error.log" "artifacts/${CHIP}-log/${REPO_SHORT}-${CHIP}-${DEVICE}-${CONFIG_TYPE}-error.log"
        fi
        
        # 软件包复制
        for pkg_dir in openwrt/bin/packages/*/ openwrt/bin/targets/qualcommax/${CHIP}/packages/; do
            if [ -d "$pkg_dir" ]; then
                find "$pkg_dir" -name "*.ipk" -exec cp {} artifacts/${CHIP}-app/ \;
            fi
        done
        
        echo "Artifacts prepared for $REPO_SHORT-$CONFIG_TYPE-$DEVICE ($CHIP)"
        ;;
        
    *)
        echo "用法:"
        echo "  管理软件源: $0 manage-feeds <openwrt_dir>"
        echo "  准备构建产物: $0 prepare-artifacts <repo_short> <config_type> <device> <chip>"
        exit 1
        ;;
esac
