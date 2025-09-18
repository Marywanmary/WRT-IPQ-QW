#!/usr/bin/env bash
set -e
# 获取脚本所在目录
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
# 获取仓库根目录（脚本目录的上一级）
BASE_PATH=$(cd "$SCRIPT_DIR/.." && pwd)
# 获取运行脚本时传入的第一个参数（设备名称）
Dev=$1
# 获取运行脚本时传入的第二个参数（构建模式）
Build_Mod=$2
# 定义配置文件的完整路径
CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
# 定义INI配置文件的完整路径
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"
# 创建日志目录
LOG_DIR="$BASE_PATH/temp_firmware/$Dev/logs"
mkdir -p "$LOG_DIR"
# 定义日志文件路径
FULL_LOG="$LOG_DIR/build_full.log"
ERROR_LOG="$LOG_DIR/build_errors.log"
WARNING_LOG="$LOG_DIR/build_warnings.log"
# 创建空日志文件
touch "$FULL_LOG" "$ERROR_LOG" "$WARNING_LOG"
# 记录开始时间
echo "Build started at $(date)" | tee "$FULL_LOG"
# 检查配置文件是否存在
if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE" | tee -a "$FULL_LOG" "$ERROR_LOG"
    exit 1
fi
# 检查INI文件是否存在
if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE" | tee -a "$FULL_LOG" "$ERROR_LOG"
    exit 1
fi
# 定义从INI文件中读取指定键值的函数
read_ini_by_key() {
    local key=$1
    # 移除了未使用的局部变量 value
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}
# 定义移除uhttpd依赖的函数
remove_uhttpd_dependency() {
    local config_path="$BASE_PATH/$BUILD_DIR/.config"
    local luci_makefile_path="$BASE_PATH/$BUILD_DIR/feeds/luci/collections/luci/Makefile"
    # 检查是否启用了quickfile插件
    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path"; then
        if [ -f "$luci_makefile_path" ]; then
            # 删除包含luci-light的行
            sed -i '/luci-light/d' "$luci_makefile_path"
            echo "Removed uhttpd (luci-light) dependency as luci-app-quickfile (nginx) is enabled." | tee -a "$FULL_LOG"
        fi
    fi
}
# 定义应用配置文件的函数
apply_config() {
    # 复制配置文件到构建目录
    \cp -f "$CONFIG_FILE" "$BASE_PATH/$BUILD_DIR/.config"
    echo "Applied config from $CONFIG_FILE" | tee -a "$FULL_LOG"
}
# --- 修改从这里开始 ---
# 从INI文件中读取仓库地址
REPO_URL=$(read_ini_by_key "REPO_URL")
# 从INI文件中读取仓库分支
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
# 如果分支为空则设置为默认值main
REPO_BRANCH=${REPO_BRANCH:-main}
# 从INI文件中读取提交哈希值
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
# 如果哈希值为空则设置为默认值none
COMMIT_HASH=${COMMIT_HASH:-none}

# --- 关键修改：统一 BUILD_DIR 为 action_build ---
# 检查是否存在action_build目录（由 pre_clone_action.sh 创建），存在则强制使用该目录作为构建目录
# 忽略 .ini 文件中的 BUILD_DIR 设置，以保证与 pre_clone_action.sh 一致
if [[ -d "$BASE_PATH/action_build" ]]; then
    BUILD_DIR="action_build"
    echo "Detected action_build directory, using it as BUILD_DIR." | tee -a "$FULL_LOG"
else
    # 如果 action_build 不存在（理论上不应该发生，因为 pre_clone_action.sh 应该创建它）
    # 为了健壮性，可以 fallback 到 .ini 的设置，但这可能仍会出错
    # INI_BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
    # BUILD_DIR=${INI_BUILD_DIR:-action_build} # 默认还是 action_build
    # 更安全的做法是报错
    echo "Error: Expected 'action_build' directory not found. pre_clone_action.sh might have failed or used a different directory." | tee -a "$FULL_LOG" "$ERROR_LOG"
    exit 1
fi
# --- 修改到此结束 ---

echo "Using repository: $REPO_URL" | tee -a "$FULL_LOG"
echo "Using branch: $REPO_BRANCH" | tee -a "$FULL_LOG"
echo "Using build directory: $BUILD_DIR" | tee -a "$FULL_LOG" # 这行现在会打印 "action_build"
echo "Using commit hash: $COMMIT_HASH" | tee -a "$FULL_LOG"
# 执行更新脚本，传入仓库地址、分支、构建目录和提交哈希值
echo "Running update script..." | tee -a "$FULL_LOG"
"$SCRIPT_DIR/update.sh" "$REPO_URL" "$REPO_BRANCH" "$BASE_PATH/$BUILD_DIR" "$COMMIT_HASH" 2>&1 | tee -a "$FULL_LOG"
# 应用配置文件
apply_config
# 移除uhttpd依赖
remove_uhttpd_dependency
# 切换到构建目录
cd "$BASE_PATH/$BUILD_DIR"
# 执行make defconfig命令生成默认配置
echo "Running make defconfig..." | tee -a "$FULL_LOG"
make defconfig 2>&1 | tee -a "$FULL_LOG"
# 检查是否是x86_64平台
if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
    # 定义软件源配置文件路径
    DISTFEEDS_PATH="$BASE_PATH/$BUILD_DIR/package/emortal/default-settings/files/99-distfeeds.conf"
    # 检查软件源配置文件是否存在
    if [ -d "${DISTFEEDS_PATH%/*}" ] && [ -f "$DISTFEEDS_PATH" ]; then
        # 替换架构名称从ARM到x86_64
        sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
        echo "Updated architecture to x86_64 in distfeeds.conf" | tee -a "$FULL_LOG"
    fi
fi
# 如果是调试模式则直接退出
if [[ $Build_Mod == "debug" ]]; then
    echo "Debug mode enabled, exiting..." | tee -a "$FULL_LOG"
    exit 0
fi
# 定义目标文件目录路径
TARGET_DIR="$BASE_PATH/$BUILD_DIR/bin/targets"
# 如果目标目录存在，则删除旧的编译产物
if [[ -d $TARGET_DIR ]]; then
    echo "Cleaning old build artifacts..." | tee -a "$FULL_LOG"
    find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" -o -name ".config" -o -name "config.buildinfo" -o -name "Packages.manifest" \) -exec rm -f {} +
fi
# 下载编译所需的源代码包 (如果 dl 目录为空或不存在)
if [ ! -d "$BASE_PATH/$BUILD_DIR/dl" ] || [ -z "$(ls -A "$BASE_PATH/$BUILD_DIR/dl")" ]; then
    echo "Downloading sources..." | tee -a "$FULL_LOG"
    make download -j$(($(nproc) * 2)) 2>&1 | tee -a "$FULL_LOG"
else
    echo "dl directory already populated, skipping download." | tee -a "$FULL_LOG"
fi
# 开始编译固件
echo "Starting firmware build..." | tee -a "$FULL_LOG"
make -j$(($(nproc) + 1)) 2>&1 | tee -a "$FULL_LOG" || {
    echo "Build failed, trying with verbose output..." | tee -a "$FULL_LOG" "$ERROR_LOG"
    make -j1 V=s 2>&1 | tee -a "$FULL_LOG" "$ERROR_LOG"
    echo "Build completed with errors" | tee -a "$FULL_LOG" "$ERROR_LOG"
    exit 1
}
# 创建临时目录用于存放所有产出物
TEMP_DIR="$BASE_PATH/temp_firmware"
\rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
# 创建总的ipk和apk目录
mkdir -p "$TEMP_DIR/ipk"
mkdir -p "$TEMP_DIR/apk"
# 创建设备专属目录
DEVICE_TEMP_DIR="$TEMP_DIR/$Dev"
mkdir -p "$DEVICE_TEMP_DIR"
# 创建日志目录（确保存在）
mkdir -p "$LOG_DIR"
# 复制.config文件
if [[ -f "$BASE_PATH/$BUILD_DIR/.config" ]]; then
    \cp -f "$BASE_PATH/$BUILD_DIR/.config" "$DEVICE_TEMP_DIR/"
    echo "Copied .config file" | tee -a "$FULL_LOG"
fi
# 复制编译产物文件
echo "Copying build artifacts..." | tee -a "$FULL_LOG"
find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" -o -name ".config" -o -name "config.buildinfo" -o -name "Packages.manifest" \) -exec cp -f {} "$DEVICE_TEMP_DIR/" \;
# 复制ipk文件
IPK_DIR="$BASE_PATH/$BUILD_DIR/bin/packages"
if [[ -d "$IPK_DIR" ]]; then
    find "$IPK_DIR" -name "*.ipk" -type f -exec cp -f {} "$TEMP_DIR/ipk/" 2>/dev/null || true
    echo "Copied ipk files for $Dev" | tee -a "$FULL_LOG"
fi
# 复制apk文件
APK_DIR="$BASE_PATH/$BUILD_DIR/bin/package" # 注意：原脚本是 bin/package，通常为 bin/packages，但按原样保留
if [[ -d "$APK_DIR" ]]; then
    find "$APK_DIR" -name "*.apk" -type f -exec cp -f {} "$TEMP_DIR/apk/" 2>/dev/null || true
    echo "Copied apk files for $Dev" | tee -a "$FULL_LOG"
fi
# === 优化后的固件和配置文件重命名部分 ===

# 解析设备名称，检查是否符合三段式结构
if [[ $Dev =~ ^([^_]+)_([^_]+)_([^_]+)$ ]]; then
    CHIP="${BASH_REMATCH[1]}"      # 芯片部分
    BRANCH_ABBR="${BASH_REMATCH[2]}" # 分支缩写
    CONFIG="${BASH_REMATCH[3]}"     # 配置部分
    echo "Device name parsed: CHIP=$CHIP, BRANCH_ABBR=$BRANCH_ABBR, CONFIG=$CONFIG" | tee -a "$FULL_LOG"

    # --- 固件重命名 ---
    for firmware in "$DEVICE_TEMP_DIR"/*.bin; do
        if [[ -f "$firmware" ]]; then # 确保文件存在
            filename=$(basename "$firmware")
            # 匹配包含 squashfs 和 factory/sysupgrade 的文件
            if [[ $filename =~ .*squashfs-(factory|sysupgrade)\.bin$ ]]; then
                 MODE="${BASH_REMATCH[1]}" # 提取 factory 或 sysupgrade
                 # 从文件名中提取型号：假设格式为 ...-<型号>-squashfs-...
                 # 更健壮地从 squashfs 前的部分提取最后一个 -
                 MODEL_PART="${filename%%-squashfs-*}"
                 MODEL="${MODEL_PART##*-}" # 获取最后一个 - 之后的部分作为型号

                 # 根据分支缩写确定前缀
                 PREFIX=""
                 if [[ "$BRANCH_ABBR" == "immwrt" ]]; then
                     PREFIX="immwrt"
                 elif [[ "$BRANCH_ABBR" == "libwrt" ]]; then
                     PREFIX="libwrt"
                 else
                     PREFIX="$BRANCH_ABBR" # 默认使用缩写
                 fi

                 # 构建新文件名: 前缀-型号-模式-配置.bin
                 new_filename="${PREFIX}-${MODEL}-${MODE}-${CONFIG}.bin"

                 mv "$firmware" "$DEVICE_TEMP_DIR/$new_filename"
                 echo "Renamed firmware $filename to $new_filename" | tee -a "$FULL_LOG"
            else
                echo "Skipping firmware $filename - does not match expected pattern" | tee -a "$FULL_LOG"
            fi
        fi
    done

    # --- 配置文件和其他文件重命名 ---
    # .config, config.buildinfo, Packages.manifest
    declare -A config_files
    config_files[".config"]=".config"
    config_files["config.buildinfo"]="config.buildinfo"
    config_files["Packages.manifest"]="Packages.manifest"

    for original_name in "${!config_files[@]}"; do
        full_original_path="$DEVICE_TEMP_DIR/$original_name"
        if [[ -f "$full_original_path" ]]; then
            # 构建新文件名: 设备名.扩展名 (对于.config) 或 设备名.文件名 (对于其他)
            if [[ "$original_name" == "config.buildinfo" || "$original_name" == "Packages.manifest" ]]; then
                 new_name="${Dev}.${original_name}"
            else # .config
                 new_name="${Dev}${original_name}" # 例如 ipq60xx_immwrt_Pro.config
            fi
            mv "$full_original_path" "$DEVICE_TEMP_DIR/$new_name"
            echo "Renamed config file $original_name to $new_name" | tee -a "$FULL_LOG"
        else
            echo "Warning: Config file not found: $original_name" | tee -a "$FULL_LOG" "$WARNING_LOG"
        fi
    done

    # --- manifest 文件重命名 (如果它不是上面处理的 Packages.manifest) ---
    # 如果 .manifest 是单独的文件 (不是 Packages.manifest)，则重命名
    for manifest_file in "$DEVICE_TEMP_DIR"/*.manifest; do
        if [[ -f "$manifest_file" ]]; then
            filename=$(basename "$manifest_file")
            # 检查是否是 Packages.manifest (已被处理)
            if [[ "$filename" != "${Dev}.Packages.manifest" ]]; then
                # 假设这是主 .manifest 文件，按要求重命名
                new_filename="${Dev}.manifest"
                mv "$manifest_file" "$DEVICE_TEMP_DIR/$new_filename"
                echo "Renamed manifest file $filename to $new_filename" | tee -a "$FULL_LOG"
            fi
        fi
    done


else
    echo "Device name '$Dev' does not follow the three-part structure, skipping renaming." | tee -a "$FULL_LOG" "$WARNING_LOG"
fi

# 如果存在action_build目录，则执行清理命令 (可选，但通常在 job 结束时由系统处理)
# if [[ -d $BASE_PATH/action_build ]]; then
#     echo "Cleaning build directory..." | tee -a "$FULL_LOG"
#     make clean 2>&1 | tee -a "$FULL_LOG"
# fi

# 从完整日志中提取错误信息
echo "=== 错误日志 ===" > "$ERROR_LOG"
grep -i "error\|failed\|failure" "$FULL_LOG" | grep -v "make.*error.*required" >> "$ERROR_LOG" || echo "未发现错误信息" >> "$ERROR_LOG"
# 从完整日志中提取警告信息
echo "=== 警告日志 ===" > "$WARNING_LOG"
grep -i "warning\|warn" "$FULL_LOG" >> "$WARNING_LOG" || echo "未发现警告信息" >> "$WARNING_LOG"
# 记录完成时间
echo "Build completed at $(date)" | tee -a "$FULL_LOG"
echo "Build completed for $Dev. All artifacts are in $DEVICE_TEMP_DIR" | tee -a "$FULL_LOG"
