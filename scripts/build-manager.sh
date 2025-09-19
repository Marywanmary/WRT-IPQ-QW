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
        
        # 1. 备份原始配置
        if [ -f "feeds.conf.default" ]; then
            cp feeds.conf.default feeds.conf.default.bak
        fi
        
        # 2. 添加第三方软件源到feeds.conf.default（不包含golang源）
        cat > feeds.conf.default << 'EOF'
src-link packages
src-link luci
src-git tailscale https://github.com/tailscale/tailscale
src-git taskplan https://github.com/sirpdboy/luci-app-taskplan
src-git lucky https://github.com/gdy666/luci-app-lucky
src-git momo https://github.com/nikkinikki-org/OpenWrt-momo
src-git small-package https://github.com/kenzok8/small-package
EOF
        
        echo "第三方软件源配置已添加到feeds.conf.default（不包含golang源）"
        
        # 3. 同步到feeds.conf
        echo "同步feeds.conf..."
        cp feeds.conf.default feeds.conf
        echo "✓ 已同步feeds.conf"
        
        # 4. 验证源配置
        echo "验证源配置..."
        echo "===== 当前feeds.conf内容 ====="
        cat feeds.conf
        echo "============================"
        
        # 5. 检查语法错误
        echo "检查feeds.conf语法..."
        if ./scripts/feeds list >/dev/null 2>&1; then
            echo "✓ feeds.conf语法正确"
        else
            echo "✗ feeds.conf语法错误，尝试使用最小配置..."
            
            # 尝试使用最小配置
            cat > feeds.conf.default << 'EOF'
src-link packages
src-link luci
EOF
            
            cp feeds.conf.default feeds.conf
            
            if ./scripts/feeds list >/dev/null 2>&1; then
                echo "✓ 最小配置语法正确，逐个添加其他源..."
                
                # 逐个添加源并测试
                SOURCES=(
                    "src-git tailscale https://github.com/tailscale/tailscale"
                    "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan"
                    "src-git lucky https://github.com/gdy666/luci-app-lucky"
                    "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo"
                    "src-git small-package https://github.com/kenzok8/small-package"
                )
                
                for source in "${SOURCES[@]}"; do
                    echo "添加源: $source"
                    echo "$source" >> feeds.conf.default
                    cp feeds.conf.default feeds.conf
                    
                    if ./scripts/feeds list >/dev/null 2>&1; then
                        echo "✓ 添加成功"
                    else
                        echo "✗ 添加失败，跳过此源"
                        # 回滚
                        sed -i '$d' feeds.conf.default
                        cp feeds.conf.default feeds.conf
                    fi
                done
            else
                echo "✗ 即使最小配置也有语法错误，可能是OpenWrt环境问题"
                exit 1
            fi
        fi
        
        # 6. 最终验证
        echo "最终验证feeds.conf..."
        echo "===== 最终feeds.conf内容 ====="
        cat feeds.conf
        echo "============================"
        
        if ./scripts/feeds list >/dev/null 2>&1; then
            echo "✓ feeds.conf语法正确，继续执行..."
        else
            echo "✗ feeds.conf语法错误，无法继续"
            exit 1
        fi
        
        # 7. 更新软件源
        echo "更新软件源..."
        ./scripts/feeds update -a
        
        # 8. 按照作者建议删除冲突插件
        echo "按照作者建议删除冲突插件..."
        CONFLICT_PACKAGES="base-files dnsmasq firewall* fullconenat libnftnl nftables ppp opkg ucl upx vsftpd* miniupnpd-iptables wireless-regdb"
        
        for pkg in $CONFLICT_PACKAGES; do
            if [ -d "feeds/small-package/$pkg" ]; then
                echo "删除冲突插件: feeds/small-package/$pkg"
                rm -rf "feeds/small-package/$pkg"
            fi
        done
        
        # 9. 清理软件源
        echo "清理软件源..."
        ./scripts/feeds clean
        
        # 10. 安装软件源
        echo "安装软件源..."
        ./scripts/feeds install -a
        
        # 11. 修复配置文件（如果存在）
        if [ -f ".config" ]; then
            echo "修复配置文件..."
            cp .config .config.backup
            
            # 重新生成配置
            make defconfig
            
            # 检查是否有语法错误
            if ! make defconfig >/dev/null 2>&1; then
                echo "⚠ 配置文件可能有语法错误，尝试修复..."
                # 如果仍有问题，可以在这里添加特定的修复逻辑
            fi
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
