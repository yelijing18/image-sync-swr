#!/bin/bash

# 显示帮助信息
show_help() {
    echo "用法：$0 [功能] [选项]... [镜像]..."
    echo
    echo "功能："
    echo "  sync                        同步镜像到华为云 SWR"
    echo "  import-docker               将镜像从华为云 SWR 导入 docker 并还原名称（参数需与 sync 保持一致）"
    echo "  import-containerd           将镜像从华为云 SWR 导入 containerd 并还原名称（参数需与 sync 保持一致）"
    echo
    echo "选项："
    echo "  --region <region>           必须，指定华为云区域，未指定时取环境变量 SWR_REGION"
    echo "  --organization <name>       必须，指定华为云 SWR 组织名称，未指定时取环境变量 SWR_ORGANIZATION"
    echo "  --remove-prefix             可选，推送到 SWR 时去除前缀，即最后一个‘/’前的部分"
    echo "  --dry-run                   可选，仅打印命令而不执行"
    echo "  -h, --help                  显示帮助信息并退出"
    echo
    echo "镜像："
    echo "  指定一个或多个要处理的镜像，格式为 [repo/]name[:IMAGE_TAG] 没有 IMAGE_TAG 时默认为 latest"
    echo
    echo "示例："
    echo "  同步 nginx 和 mysql 镜像"
    echo "  $0 sync --region cn-east-3 --organization yelijing18-mirrors nginx:alpine mysql"
    echo "  同步 minio/minio 镜像并去除其 minio/ 前缀"
    echo "  $0 sync --region cn-east-3 --organization yelijing18-mirrors --remove-prefix minio/minio:latest"
    echo "  将 nginx 镜像从华为云 SWR 导入 docker 并还原名称"
    echo "  $0 import-docker --region cn-east-3 --organization yelijing18-mirrors nginx:alpine"
    echo "  输出将 minio 镜像从华为云 SWR 导入 containerd 并还原名称的命令"
    echo "  $0 import-containerd --region cn-east-3 --organization yelijing18-mirrors --remove-prefix --dry-run minio/minio:latest"
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                REGION=$2
                shift 2
                ;;
            --organization)
                ORGANIZATION=$2
                shift 2
                ;;
            --remove-prefix)
                REMOVE_PREFIX_FLAG="--remove-prefix"
                shift
                ;;
            --dry-run)
                DRY_RUN_FLAG="--dry-run"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            sync|import-docker|import-containerd)
                ACTION=$1
                shift
                ;;
            *)
                IMAGES+=("$1")
                shift
                ;;
        esac
    done
}

# 检查必要参数
check_parameters() {
    if [[ -z "$REGION" ]]; then
        echo "错误：缺少地域信息。请通过命令行参数 --region 提供或设置环境变量 SWR_REGION。"
        show_help
        exit 1
    fi

    if [[ -z "$ORGANIZATION" ]]; then
        echo "错误：缺少组织信息。请通过命令行参数 --organization 提供或设置环境变量 SWR_ORGANIZATION。"
        show_help
        exit 1
    fi

    if [[ ${#IMAGES[@]} -eq 0 ]]; then
        echo "错误：请至少指定一个镜像。"
        show_help
        exit 1
    fi
}

# 通用的执行或打印命令函数
run_or_print() {
    local cmd=$1
    if [[ "$DRY_RUN_FLAG" != "--dry-run" ]]; then
        echo "Execute: $cmd"
        if ! eval "$cmd"; then
            echo "错误：执行命令失败：$cmd"
            exit 1
        fi
        echo
    else
        echo "$cmd"
    fi
}

# 解析镜像名称和标签
parse_image() {
    local full_image=$1
    # 如果镜像中有冒号，则切分镜像名称和标签，否则使用 latest 作为标签
    # 注意：该代码无法处理镜像信息错误的情况，如 full_image 中包含多个冒号或冒号前后为空，这将导致最后生成的命令出错
    if [[ "$full_image" == *":"* ]]; then
        IMAGE_NAME=$(echo "$full_image" | cut -d':' -f1)
        IMAGE_TAG=$(echo "$full_image" | cut -d':' -f2)
    else
        IMAGE_NAME="$full_image"
        IMAGE_TAG="$DEFAULT_IMAGE_TAG"
    fi

    # 如果有 --remove-prefix 选项，则根据最后一个'/'切分待移除前缀和镜像名称
    REMOVED_PREFIX=""
    if [[ "$REMOVE_PREFIX_FLAG" == "--remove-prefix" ]]; then
        if [[ "$IMAGE_NAME" == *"/"* ]]; then
            REMOVED_PREFIX="$(echo $IMAGE_NAME | sed 's/\/[^/]*$//')/"
            IMAGE_NAME=$(echo "$IMAGE_NAME" | sed 's/.*\///')
        fi
    fi
}

# 将镜像同步到华为云，若有条件还将设置镜像为公开
sync() {
    for FULL_IMAGE in "${IMAGES[@]}"; do
        parse_image "$FULL_IMAGE"
        echo "# Sync ${REMOVED_PREFIX}${IMAGE_NAME}:${IMAGE_TAG} to ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "docker pull ${REMOVED_PREFIX}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "docker tag ${REMOVED_PREFIX}${IMAGE_NAME}:${IMAGE_TAG} ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "docker push ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "docker rmi ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "docker rmi ${REMOVED_PREFIX}${IMAGE_NAME}:${IMAGE_TAG}"
        if [[ "$DRY_RUN_FLAG" != "--dry-run" && $(command -v hcloud) ]]; then
            echo "通过华为云 KooCLI 设置镜像可见性为公开"
            CLI_IMAGE_NAME=$(echo "$IMAGE_NAME" | sed 's/\//\$/g')
            CLI_RESULT=$(hcloud SWR ShowRepository --cli-region="$REGION" --Content-Type="application/json" --namespace="$ORGANIZATION" --repository="$CLI_IMAGE_NAME" --cli-query="is_public")
            if [[ "$CLI_RESULT" != "true" ]]; then
                hcloud SWR UpdateRepo --cli-region=$REGION --Content-Type=application/json --namespace=$ORGANIZATION --repository=$CLI_IMAGE_NAME --is_public=true > /dev/null
                echo "成功将镜像 ${NEW_REPO}${IMAGE_NAME} 设置为公开"
            else
                echo "镜像 ${NEW_REPO}${IMAGE_NAME} 已经是公开的，跳过"
            fi
        fi
        echo
    done
}

# 将镜像从华为云 SWR 导入 docker 并还原名称
import_docker() {
    for FULL_IMAGE in "${IMAGES[@]}"; do
        parse_image "$FULL_IMAGE"
        echo "# Import ${REMOVED_PREFIX}${IMAGE_NAME}:${IMAGE_TAG} from ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "docker pull ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "docker tag ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG} ${REMOVED_PREFIX}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "docker rmi ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG}"
        echo
    done
}

# 将镜像从华为云 SWR 导入 containerd 并还原名称
import_containerd() {
    for FULL_IMAGE in "${IMAGES[@]}"; do
        parse_image "$FULL_IMAGE"
        echo "# Import ${REMOVED_PREFIX}${IMAGE_NAME}:${IMAGE_TAG} from ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "ctr i pull ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "ctr i tag ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG} ${REMOVED_PREFIX}${IMAGE_NAME}:${IMAGE_TAG}"
        run_or_print "ctr i del ${NEW_REPO}${IMAGE_NAME}:${IMAGE_TAG}"
        echo
    done
}

# 主程序入口
main() {
    DEFAULT_IMAGE_TAG="latest"
    REGION=${SWR_REGION:-}
    ORGANIZATION=${SWR_ORGANIZATION:-}
    REMOVE_PREFIX_FLAG=""
    DRY_RUN_FLAG=""
    IMAGES=()

    parse_arguments "$@"
    check_parameters

    NEW_REPO="swr.$REGION.myhuaweicloud.com/$ORGANIZATION/"

    # 执行指定功能
    case $ACTION in
        sync)
            sync
            ;;
        import-docker)
            import_docker
            ;;
        import-containerd)
            import_containerd
            ;;
        *)
            echo "错误：未知功能 '$ACTION'"
            show_help
            exit 1
            ;;
    esac
}

# 调用主程序
main "$@"