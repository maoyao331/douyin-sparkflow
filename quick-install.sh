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

valid_domain() {
  [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

get_public_ip() {
  local ip
  ip="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  if [[ -n "$ip" ]]; then
    printf '%s' "$ip"
    return 0
  fi
  hostname -I 2>/dev/null | awk '{print $1}'
}

configure_domain() {
  local domain public_ip
  read -r -p "请输入域名（回车使用服务器 IP 访问）：" domain
  domain="${domain,,}"
  public_ip="$(get_public_ip || true)"
  public_ip="${public_ip:-服务器IP}"

  if [[ -z "$domain" ]]; then
    ACCESS_URL="http://${public_ip}:${WEB_PORT_VALUE}"
    printf '\n将使用 IP 访问：%s\n' "$ACCESS_URL"
    return 0
  fi

  if ! valid_domain "$domain"; then
    printf '域名格式无效，请使用类似 spark.example.com 的完整域名。\n'
    return 1
  fi

  ACCESS_URL="http://${domain}:${WEB_PORT_VALUE}"
  printf '\n请在 Cloudflare DNS 中添加以下记录：\n'
  printf '类型：A\n名称：%s\nIPv4 地址：%s\n代理状态：请保持关闭小黄云，使用仅 DNS（灰云）。\n' "$domain" "$public_ip" "$WEB_PORT_VALUE"
  printf '\n域名访问地址：%s\n' "$ACCESS_URL"
  printf '提示：本脚本不会自动修改 Cloudflare DNS、申请证书或接管 443；访问格式为 http://域名:端口。\n'
  return 0
}

run_server_install() {
  local repo_url
  repo_url="${REPO_URL:-$REPO_URL_DEFAULT}"
  printf '\n开始执行服务器安装。此过程会安装 Docker 并构建镜像。\n'
  printf '现有 3x-ui/Xray 的 443 端口不会被本脚本占用。\n\n'
  WEB_PORT="$WEB_PORT_VALUE" REPO_URL="$repo_url" \
    bash "$SCRIPT_DIR/deploy/install-server.sh"
}

server_menu() {
  while true; do
    print_header
    printf '一、服务器安装\n'
    printf '1：添加端口（回车默认 8787）\n'
    printf '2：添加域名（回车默认 IP 访问）\n'
    printf '3：返回上一级\n\n'
    read -r -p '请选择：' choice
    case "$choice" in
      1)
        read_port
        printf '已选择 Web 端口：%s\n' "$WEB_PORT_VALUE"
        run_server_install
        pause
        ;;
      2)
        read_port
        if configure_domain; then
          run_server_install
        fi
        pause
        ;;
      3) return 0 ;;
      *) printf '选项无效。\n'; sleep 1 ;;
    esac
  done
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
    printf '2：添加域名（回车默认 IP 访问）\n'
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
        if configure_domain; then
          run_windows_install
        fi
        pause
        ;;
      3) return 0 ;;
      *) printf '选项无效。\n'; sleep 1 ;;
    esac
  done
}

main_menu() {
  while true; do
    print_header
    printf '1：服务器安装\n'
    printf '2：Windows 本地安装\n'
    printf '3：退出脚本\n\n'
    read -r -p '请选择：' choice
    case "$choice" in
      1) server_menu ;;
      2) windows_menu ;;
      3)
        printf '已退出。\n'
        return 0
        ;;
      *) printf '选项无效。\n'; sleep 1 ;;
    esac
  done
}

WEB_PORT_VALUE="$DEFAULT_PORT"
ACCESS_URL=""
main_menu
