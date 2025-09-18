#!/usr/bin/env bash
# 设置严格模式：任何命令失败时脚本立即退出
set -e
set -o errexit
# 设置错误追踪：显示完整的错误调用链
set -o errtrace
# 获取脚本所在目录
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
# 获取仓库根目录（脚本目录的上一级）
BASE_PATH=$(cd "$SCRIPT_DIR/.." && pwd)
# 定义错误处理函数
error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}
# 设置陷阱捕获ERR信号
trap 'error_handler' ERR
# 从命令行参数获取配置信息
REPO_URL=$1      # 代码仓库地址
REPO_BRANCH=$2   # 代码仓库分支
BUILD_DIR=$3     # 构建目录
COMMIT_HASH=$4   # 特定的代码提交版本号
# 定义一些固定的配置项
FEEDS_CONF="feeds.conf.default"    # 软件源配置文件名
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"  # Go语言包的仓库地址
GOLANG_BRANCH="25.x"              # Go语言包的分支版本
THEME_SET="argon"                  # 默认网页主题名称
LAN_ADDR="192.168.111.1"           # 路由器默认管理地址
# 定义克隆代码仓库的函数
clone_repo() {
    if [[ ! -d $BUILD_DIR ]]; then
        echo "克隆仓库: $REPO_URL 分支: $REPO_BRANCH"
        # 尝试克隆仓库
        if ! git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR; then
            echo "错误：克隆仓库 $REPO_URL 失败" >&2
            exit 1
        fi
    fi
}
# 定义清理构建环境的函数
clean_up() {
    cd $BUILD_DIR
    # 删除旧的配置文件
    if [[ -f $BUILD_DIR/.config ]]; then
        \rm -f $BUILD_DIR/.config
    fi
    # 删除临时目录
    if [[ -d $BUILD_DIR/tmp ]]; then
        \rm -rf $BUILD_DIR/tmp
    fi
    # 清空日志目录
    if [[ -d $BUILD_DIR/logs ]]; then
        \rm -rf $BUILD_DIR/logs/*
    fi
    # 创建新的临时目录
    mkdir -p $BUILD_DIR/tmp
    # 创建构建标记文件
    echo "1" >$BUILD_DIR/tmp/.build
}
# 定义重置代码仓库状态的函数
reset_feeds_conf() {
    # 将代码重置到远程分支的最新状态
    git reset --hard origin/$REPO_BRANCH
    # 清理所有未被跟踪的文件和目录
    git clean -f -d
    # 从远程仓库拉取最新代码
    git pull
    # 如果指定了特定的提交版本
    if [[ $COMMIT_HASH != "none" ]]; then
        # 切换到那个特定的版本
        git checkout $COMMIT_HASH
    fi
}
# 定义更新软件源的函数
update_feeds() {
    # 删除配置文件中的注释行
    sed -i '/^#/d' "$BUILD_DIR/$FEEDS_CONF"
    # 添加新的软件源，OpenWrt 的构建系统会根据 feeds.conf.default 中 src-git 条目的顺序来决定使用哪个 feed 中的软件包，顺序靠前的 feed 优先。
        # 确保文件以换行符结尾
        [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git tailscale https://github.com/tailscale/tailscale ;main" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git taskplan https://github.com/sirpdboy/luci-app-taskplan ;master" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git lucky https://github.com/gdy666/luci-app-lucky" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo.git ;main" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git OpenAppFilter https://github.com/destan19/OpenAppFilter.git ;master" >>"$BUILD_DIR/$FEEDS_CONF"
    # 检查并添加 small-package 源
    if ! grep -q "small-package" "$BUILD_DIR/$FEEDS_CONF"; then
        # 确保文件以换行符结尾
        [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git small8 https://github.com/kenzok8/small-package" >>"$BUILD_DIR/$FEEDS_CONF"
    fi
    # 添加bpf.mk文件解决更新报错
    if [ ! -f "$BUILD_DIR/include/bpf.mk" ]; then
        touch "$BUILD_DIR/include/bpf.mk"
    fi
    # 更新所有软件源
    ./scripts/feeds clean
    ./scripts/feeds update -a
}
# 定义移除不需要的软件包的函数
remove_unwanted_packages() {
    # 定义要移除的LuCI应用列表
    local luci_packages=(
        "luci-app-passwall" "luci-app-ddns-go" "luci-app-rclone" "luci-app-ssr-plus"
        "luci-app-vssr" "luci-app-daed" "luci-app-dae" "luci-app-alist" "luci-app-homeproxy"
        "luci-app-haproxy-tcp" "luci-app-openclash" "luci-app-mihomo" "luci-app-appfilter"
        "luci-app-msd_lite"
    )
    # 定义要移除的网络工具包列表
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria"
        "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs" "shadowsocksr-libev"
        "dae" "daed" "mihomo" "geoview" "tailscale" "open-app-filter" "msd_lite"
    )
    # 定义要移除的工具包列表
    local packages_utils=(
        "cups"
    )
    # 定义要移除的small8源软件包列表
    local small8_packages=(
        "ppp" "firewall" "dae" "daed" "daed-next" "libnftnl" "nftables" "dnsmasq" "luci-app-alist"
        "alist" "opkg" "smartdns" "luci-app-smartdns"
    )
    # 遍历并删除LuCI应用
    for pkg in "${luci_packages[@]}"; do
        if [[ -d ./feeds/luci/applications/$pkg ]]; then
            \rm -rf ./feeds/luci/applications/$pkg
        fi
        if [[ -d ./feeds/luci/themes/$pkg ]]; then
            \rm -rf ./feeds/luci/themes/$pkg
        fi
    done
    # 遍历并删除网络工具包
    for pkg in "${packages_net[@]}"; do
        if [[ -d ./feeds/packages/net/$pkg ]]; then
            \rm -rf ./feeds/packages/net/$pkg
        fi
    done
    # 遍历并删除工具包
    for pkg in "${packages_utils[@]}"; do
        if [[ -d ./feeds/packages/utils/$pkg ]]; then
            \rm -rf ./feeds/packages/utils/$pkg
        fi
    done
    # 遍历并删除small8源软件包
    for pkg in "${small8_packages[@]}"; do
        if [[ -d ./feeds/small8/$pkg ]]; then
            \rm -rf ./feeds/small8/$pkg
        fi
    done
    # 删除istore软件源
    if [[ -d ./package/istore ]]; then
        \rm -rf ./package/istore
    fi
    # 清理特定平台的初始化脚本
    if [ -d "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults" ]; then
        find "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults/" -type f -name "99*.sh" -exec rm -f {} +
    fi
}
# 定义更新Go语言支持包的函数
update_golang() {
    if [[ -d ./feeds/packages/lang/golang ]]; then
        echo "正在更新 golang 软件包..."
        \rm -rf ./feeds/packages/lang/golang
        # 克隆新的Go语言包
        if ! git clone --depth 1 -b $GOLANG_BRANCH $GOLANG_REPO ./feeds/packages/lang/golang; then
            echo "错误：克隆 golang 仓库 $GOLANG_REPO 失败" >&2
            exit 1
        fi
    fi
}
# 定义安装small8源软件包的函数
install_small8() {
    ./scripts/feeds install -p small8 -f xray-core xray-plugin dns2tcp dns2socks haproxy hysteria \
        naiveproxy shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-geoview v2ray-plugin \
        tuic-client chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev \
        luci-app-passwall v2dat mosdns luci-app-mosdns adguardhome luci-app-adguardhome ddns-go \
        luci-app-ddns-go taskd luci-lib-xterm luci-lib-taskd luci-app-store quickstart \
        luci-app-quickstart luci-app-istorex luci-app-cloudflarespeedtest netdata luci-app-netdata \
        lucky luci-app-lucky luci-app-openclash luci-app-homeproxy luci-app-amlogic nikki luci-app-nikki \
        tailscale luci-app-tailscale oaf open-app-filter luci-app-oaf easytier luci-app-easytier \
        msd_lite luci-app-msd_lite cups luci-app-cupsd
}
# 定义安装FullCone NAT支持包的函数
install_fullconenat() {
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat-nft ]; then
        ./scripts/feeds install -p small8 -f fullconenat-nft
    fi
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat ]; then
        ./scripts/feeds install -p small8 -f fullconenat
    fi
}
# 定义安装所有软件源的函数
install_feeds() {
    ./scripts/feeds update -i
    # 遍历所有软件源目录
    for dir in $BUILD_DIR/feeds/*; do
        # 检查是否为目录并且不以 .tmp 结尾，并且不是软链接
        if [ -d "$dir" ] && [[ ! "$dir" == *.tmp ]] && [ ! -L "$dir" ]; then
            if [[ $(basename "$dir") == "small8" ]]; then
                # 如果是small8源
                install_small8
                install_fullconenat
            else
                # 对于其他软件源
                ./scripts/feeds install -f -ap $(basename "$dir")
            fi
        fi
    done
}
# 定义修复默认设置的函数
fix_default_set() {
    # 修改默认主题
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi
    # 安装自定义设置脚本
    install -Dm755 "$BASE_PATH/patches/990_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/990_set_argon_primary"
    install -Dm755 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"
    # 修复温度显示脚本
    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/patches/tempinfo" ]; then
            \cp -f "$BASE_PATH/patches/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}
# 定义修复miniupnpd软件包的函数
fix_miniupnpd() {
    local miniupnpd_dir="$BUILD_DIR/feeds/packages/net/miniupnpd"
    local patch_file="999-chanage-default-leaseduration.patch"
    if [ -d "$miniupnpd_dir" ] && [ -f "$BASE_PATH/patches/$patch_file" ]; then
        install -Dm644 "$BASE_PATH/patches/$patch_file" "$miniupnpd_dir/patches/$patch_file"
    fi
}
# 定义将dnsmasq替换为dnsmasq-full的函数
change_dnsmasq2full() {
    if ! grep -q "dnsmasq-full" $BUILD_DIR/include/target.mk; then
        sed -i 's/dnsmasq/dnsmasq-full/g' ./include/target.mk
