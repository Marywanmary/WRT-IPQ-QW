#!/bin/bash

# OpenWrt配置管理脚本
# 功能：提取设备列表、合并配置文件、设置默认配置
# 用法: 
#   1. 提取设备列表: ./scripts/config-manager.sh get-devices <config_file>
#   2. 合并配置文件: ./scripts/config-manager.sh merge-configs <repo_short> <config_type> <device> <chip>
#   3. 设置默认配置: ./scripts/config-manager.sh set-default <openwrt_dir>

COMMAND=$1

case $COMMAND in
    "get-devices")
        # 从OpenWrt配置文件中提取设备名称列表
        # 输出格式：JSON数组，例如：["jdcloud_re-ss-01","jdcloud_re-cs-02"]
        
        CONFIG_FILE=$2
        
        # 检查配置文件是否存在
        if [ ! -f "$CONFIG_FILE" ]; then
            echo "Error: Config file $CONFIG_FILE not found!"
            echo "[]"  # 输出空JSON数组
            exit 1
        fi
        
        # 从配置文件中提取设备名称
        devices=$(grep "^CONFIG_TARGET_DEVICE_.*_DEVICE_.*=y$" "$CONFIG_FILE" | \
                  sed -E 's/^CONFIG_TARGET_DEVICE_[^_]+_[^_]+_DEVICE_([^=]+)=y$/\1/' | \
                  sort -u | tr '\n' ' ')
        
        # 去除末尾空格
        devices=$(echo "$devices" | sed 's/ *$//')
        
        # 检查是否找到设备
        if [ -z "$devices" ]; then
            echo "Warning: No devices found in config file $CONFIG_FILE"
            echo "[]"  # 输出空JSON数组
            exit 0
        fi
        
        # 将设备列表转换为JSON数组格式
        printf '["%s"]' $(echo "$devices" | sed 's/ /","/g')
        ;;
        
    "merge-configs")
        # 合并OpenWrt配置文件
        # 合并优先级：软件包配置 > 分支配置 > 芯片配置
        
        REPO_SHORT=$2
        CONFIG_TYPE=$3
        DEVICE=$4
        CHIP=$5
        
        # 使用绝对路径设置配置文件路径
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        BASE_CONFIG="$SCRIPT_DIR/../configs/${CHIP}_base.config"
        BRANCH_CONFIG="$SCRIPT_DIR/../configs/${REPO_SHORT}_base.config"
        PKG_CONFIG="$SCRIPT_DIR/../configs/${CONFIG_TYPE}.config"
        OUTPUT_CONFIG="$SCRIPT_DIR/../.config"
        
        echo "正在合并配置文件: $CHIP $REPO_SHORT $CONFIG_TYPE"
        
        # 检查基础配置文件是否存在
        if [ ! -f "$BASE_CONFIG" ]; then
            echo "Error: Base config file $BASE_CONFIG not found!"
            exit 1
        fi
        
        # 合并配置文件（优先级：软件包配置 > 分支配置 > 芯片配置）
        cat "$BASE_CONFIG" > "$OUTPUT_CONFIG"
        
        if [ -f "$BRANCH_CONFIG" ]; then
            cat "$BRANCH_CONFIG" >> "$OUTPUT_CONFIG"
            echo "已添加分支配置: $BRANCH_CONFIG"
        else
            echo "警告: 分支配置文件不存在: $BRANCH_CONFIG"
        fi
        
        if [ -f "$PKG_CONFIG" ]; then
            cat "$PKG_CONFIG" >> "$OUTPUT_CONFIG"
            echo "已添加软件包配置: $PKG_CONFIG"
        else
            echo "警告: 软件包配置文件不存在: $PKG_CONFIG"
        fi
        
        # 根据设备设置特定配置
        case $DEVICE in
            "jdcloud_re-ss-01")
                echo "CONFIG_TARGET_DEVICE_qualcommax_${CHIP}_DEVICE_jdcloud_re-ss-01=y" >> "$OUTPUT_CONFIG"
                echo "# CONFIG_TARGET_DEVICE_PACKAGES_qualcommax_${CHIP}_DEVICE_jdcloud_re-ss_01=\"\"" >> "$OUTPUT_CONFIG"
                ;;
            "jdcloud_re-cs-02")
                echo "CONFIG_TARGET_DEVICE_qualcommax_${CHIP}_DEVICE_jdcloud_re-cs-02=y" >> "$OUTPUT_CONFIG"
                echo "CONFIG_TARGET_DEVICE_PACKAGES_qualcommax_${CHIP}_DEVICE_jdcloud_re-cs-02=\"luci-app-athena-led luci-i18n-athena-led-zh-cn\"" >> "$OUTPUT_CONFIG"
                ;;
            *)
                echo "Error: Unknown device $DEVICE"
                exit 1
                ;;
        esac
        
        echo "Configuration merged for $REPO_SHORT-$CONFIG_TYPE-$DEVICE ($CHIP)"
        ;;
        
    "set-default")
        # 设置默认配置脚本
        
        OPENWRT_DIR=$2
        
        # 检查OpenWrt目录是否存在
        if [ ! -d "$OPENWRT_DIR" ]; then
            echo "Error: OpenWrt directory $OPENWRT_DIR not found!"
            exit 1
        fi
        
        # 设置默认LAN地址
        echo "设置默认管理地址为: 192.168.111.1"
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/192.168.111.1/g' "$OPENWRT_DIR/package/base-files/files/bin/config_generate"
        
        # 设置默认主机名
        echo "设置默认主机名为: WRT"
        sed -i "s/hostname='.*'/hostname='WRT'/g" "$OPENWRT_DIR/package/base-files/files/bin/config_generate"
        
        # 设置管理员密码为空
        echo "设置管理员密码为空"
        SHADOW_FILE="$OPENWRT_DIR/package/base-files/files/etc/shadow"
        if [ -f "$SHADOW_FILE" ]; then
            # 修改root密码为空（第二个字段为空表示无密码）
            sed -i 's/^root:[^:]*:/root::/' "$SHADOW_FILE"
        else
            # 如果shadow文件不存在，创建一个
            mkdir -p "$OPENWRT_DIR/package/base-files/files/etc"
            echo "root:::0:0:99999:7:::" > "$SHADOW_FILE"
        fi
        
        # 设置无线密码为空
        echo "设置无线密码为空"
        if [ -f "$OPENWRT_DIR/package/kernel/mac80211/files/lib/wifi/mac80211.sh" ]; then
            sed -i 's/encryption=psk.*/encryption=none/g' "$OPENWRT_DIR/package/kernel/mac80211/files/lib/wifi/mac80211.sh"
        fi
        
        echo "默认配置设置完成"
        ;;
        
    *)
        echo "用法:"
        echo "  提取设备列表: $0 get-devices <config_file>"
        echo "  合并配置文件: $0 merge-configs <repo_short> <config_type> <device> <chip>"
        echo "  设置默认配置: $0 set-default <openwrt_dir>"
        exit 1
        ;;
esac
