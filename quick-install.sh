#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PORT=8787
REPO_URL_DEFAULT="https://github.com/maoyao331/douyin-sparkflow.git"

print_header() {
  clear 2>/dev/null || true
  printf '\n========================================\n'
  printf '       DouYin SparkFlow 快捷安装脚本\n'
  printf '========================================\n\n'
}

pause() {
  printf '\n按 Enter 返回菜单...'
  read -r _ || true
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 ))
}

read_port() {
  local value
  while true; do
    read -r -p "请输入 Web 端口（回车默认 ${DEFAULT_PORT}）：" value
    value="${value:-$DEFAULT_PORT}"
    if valid_port "$value"; then
      WEB_PORT_VALUE=$((10#$value))
      return 0
    fi
    printf '端口无效，请输入 1-65535 之间的数字。\n'
  done
}

ensure_project_source() {
  local installer_url installer_path
  INSTALLER_PATH="$SCRIPT_DIR/deploy/install-server.sh"
  if [[ -f "$INSTALLER_PATH" ]]; then
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update
      apt-get install -y curl
    else
      printf '未找到 curl，无法下载官方安装脚本。\n' >&2
      return 1
    fi
  fi
  installer_url="https://raw.githubusercontent.com/halfwaystudent/douyin-sparkflow/main/deploy/install-server.sh"
  installer_path="$(mktemp /tmp/douyin-sparkflow-installer.XXXXXX.sh)"
  printf '\n当前为独立快捷脚本，正在下载官方服务器安装脚本...\n'
  curl -fL "$installer_url" -o "$installer_path"
  chmod 700 "$installer_path"
  INSTALLER_PATH="$installer_path"
}

run_server_install() {
  local repo_url
  repo_url="${REPO_URL:-$REPO_URL_DEFAULT}"
  ensure_project_source
  printf '\n开始执行服务器安装。此过程会安装 Docker 并构建镜像。\n'
  printf '安装完成后使用 http://服务器IP:%s 访问。\n' "$WEB_PORT_VALUE"
  printf '现有 3x-ui/Xray 的 443 端口不会被本脚本占用。\n\n'
  WEB_PORT="$WEB_PORT_VALUE" WEB_BIND_ADDRESS="0.0.0.0" REPO_URL="$repo_url" \
    bash "$INSTALLER_PATH"
}

server_menu() {
  while true; do
    print_header
    printf '一、服务器安装\n'
    printf '1：添加端口（回车默认 8787）\n'
    printf '2：返回上一级\n\n'
    read -r -p '请选择：' choice
    case "$choice" in
      1)
        read_port
        printf '已选择 Web 端口：%s\n' "$WEB_PORT_VALUE"
        run_server_install
        pause
        ;;
      2) return 0 ;;
      *) printf '选项无效。\n'; sleep 1 ;;
    esac
  done
}

get_lan_ip() {
  hostname -I 2>/dev/null | tr ' ' '\n' | awk '/^[0-9]+\./ && $1 != "127.0.0.1" {print; exit}'
}

show_windows_access() {
  local lan_ip
  lan_ip="$(get_lan_ip || true)"
  lan_ip="${lan_ip:-本机局域网IP}"
  printf '\nWindows 本地部署使用局域网 IP 加端口访问：\n'
  printf 'http://%s:%s\n' "$lan_ip" "$WEB_PORT_VALUE"
  printf '请确保访问设备与 Windows 电脑在同一局域网，并允许该端口通过 Windows 防火墙。\n'
}

run_windows_install() {
  if [[ ! -f "$SCRIPT_DIR/deploy/install-local.ps1" ]]; then
    printf '未找到 deploy/install-local.ps1。请在项目根目录运行此脚本。\n'
    return 1
  fi
  printf '\n请在 Windows PowerShell 中执行：\n'
  printf 'Set-ExecutionPolicy -Scope Process Bypass\n'
  printf '.\\deploy\\install-local.ps1\n'
  printf '\n当前端口会保存到项目 .env 的 WEB_PORT=%s。\n' "$WEB_PORT_VALUE"
  printf '请确保 Docker Desktop 已启动。\n'
}

windows_menu() {
  while true; do
    print_header
    printf '二、Windows 本地安装\n'
    printf '1：添加端口（回车默认 8787）\n'
    printf '2：局域网 IP 加端口访问\n'
    printf '3：返回上一级\n\n'
    read -r -p '请选择：' choice
    case "$choice" in
      1)
        read_port
        run_windows_install
        pause
        ;;
      2)
        read_port
        show_windows_access
        run_windows_install
        pause
        ;;
      3) return 0 ;;
      *) printf '选项无效。\n'; sleep 1 ;;
    esac
  done
}

uninstall_server() {
  local confirm compose_root
  printf '\n此操作将删除 SparkFlow 容器、镜像、项目目录、运行状态、日志、代理配置和本脚本。\n'
  printf '如果使用本脚本配置过域名，也会删除 douyin-sparkflow-* 的 Nginx 配置。\n'
  printf '不会删除 Docker、Nginx 软件本身，也不会修改 3x-ui/Xray 或 443。\n\n'
  read -r -p '请输入 DELETE 确认卸载：' confirm
  if [[ "$confirm" != "DELETE" ]]; then
    printf '未输入 DELETE，已取消卸载。\n'
    return 0
  fi

  compose_root="/opt/douyin-sparkflow"
  if [[ -f "$compose_root/docker-compose.yml" ]] && command -v docker >/dev/null 2>&1; then
    docker compose -f "$compose_root/docker-compose.yml" down --remove-orphans --volumes || true
  fi
  for container in mihomo douyin-web login-desktop douyin-scheduler douyin-task; do
    docker rm -f "$container" >/dev/null 2>&1 || true
  done
  docker image rm -f douyin-sparkflow:local >/dev/null 2>&1 || true
  docker network rm douyin-sparkflow_default >/dev/null 2>&1 || true

  if [[ -d /etc/nginx/sites-enabled ]] && compgen -G '/etc/nginx/sites-enabled/douyin-sparkflow-*' >/dev/null; then
    rm -f /etc/nginx/sites-enabled/douyin-sparkflow-* /etc/nginx/sites-available/douyin-sparkflow-*
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  fi
  rm -rf -- "$compose_root"
  rm -f -- "$SCRIPT_DIR/quick-install.sh"
  printf '\nSparkFlow 卸载完成；8787、8788、7890、9090 容器端口已释放。\n'
  printf 'Docker、Nginx、3x-ui/Xray 和 443 未被删除或修改。\n'
  exit 0
}

main_menu() {
  while true; do
    print_header
    printf '一：服务器安装\n'
    printf '二：Windows 本地安装\n'
    printf '三：退出脚本\n'
    printf '四：卸载脚本\n\n'
    read -r -p '请选择：' choice
    case "$choice" in
      1) server_menu ;;
      2) windows_menu ;;
      3)
        printf '已退出。\n'
        return 0
        ;;
      4) uninstall_server ;;
      *) printf '选项无效。\n'; sleep 1 ;;
    esac
  done
}

WEB_PORT_VALUE="$DEFAULT_PORT"
ACCESS_URL=""
DOMAIN_VALUE=""
INSTALLER_PATH=""
main_menu
