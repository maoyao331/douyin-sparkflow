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
  DOMAIN_VALUE=""

  if [[ -z "$domain" ]]; then
    ACCESS_URL="http://${public_ip}:${WEB_PORT_VALUE}"
    printf '\n将使用 IP 访问：%s\n' "$ACCESS_URL"
    return 0
  fi

  if ! valid_domain "$domain"; then
    printf '域名格式无效，请使用类似 spark.example.com 的完整域名。\n'
    return 1
  fi

  DOMAIN_VALUE="$domain"
  ACCESS_URL="http://${domain}"
  printf '\n请在 Cloudflare DNS 中添加以下记录：\n'
  printf '类型：A\n名称：%s\nIPv4 地址：%s\n代理状态：可按需开启或关闭小黄云。\n' "$domain" "$public_ip"
  printf '\n域名访问地址：%s\n' "$ACCESS_URL"
  printf '本脚本将在服务器安装 Nginx，并让 Nginx 使用 80 端口转发到 SparkFlow。不会接管或修改 443。\n'
  return 0
}

install_domain_proxy() {
  local domain="$1"
  if ss -ltn 2>/dev/null | grep -Eq ':[[:space:]]*80[[:space:]]'; then
    printf '检测到 80 端口已被占用，无法自动配置域名入口；SparkFlow 已完成安装，请手动配置反向代理。\n' >&2
    return 1
  fi
  if ! command -v nginx >/dev/null 2>&1; then
    apt-get update
    apt-get install -y nginx
  fi
  cat > "/etc/nginx/sites-available/douyin-sparkflow-${domain}" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    location / {
        proxy_pass http://127.0.0.1:${WEB_PORT_VALUE};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600;
    }
}
NGINX
  ln -sfn "/etc/nginx/sites-available/douyin-sparkflow-${domain}" "/etc/nginx/sites-enabled/douyin-sparkflow-${domain}"
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
  printf 'Nginx 域名入口已配置：%s\n' "http://${domain}"
}

run_server_install() {
  local repo_url
  repo_url="${REPO_URL:-$REPO_URL_DEFAULT}"
  printf '\n开始执行服务器安装。此过程会安装 Docker 并构建镜像。\n'
  printf '现有 3x-ui/Xray 的 443 端口不会被本脚本占用。\n\n'
  if [[ -n "${DOMAIN_VALUE:-}" ]]; then
    WEB_PORT="$WEB_PORT_VALUE" WEB_BIND_ADDRESS="127.0.0.1" REPO_URL="$repo_url" \
      bash "$SCRIPT_DIR/deploy/install-server.sh"
    install_domain_proxy "$DOMAIN_VALUE"
  else
    WEB_PORT="$WEB_PORT_VALUE" WEB_BIND_ADDRESS="0.0.0.0" REPO_URL="$repo_url" \
      bash "$SCRIPT_DIR/deploy/install-server.sh"
  fi
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
DOMAIN_VALUE=""
main_menu
