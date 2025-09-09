#!/bin/bash

# DuckDNS + Home Assistant HTTPS Setup Script
# 適用於 GCP Debian VM

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日誌函數
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 檢查系統環境
check_system() {
    log_info "檢查系統環境..."

    # 檢查是否為 root 用戶
    if [[ $EUID -eq 0 ]]; then
        log_error "請不要使用 root 用戶運行此腳本"
        exit 1
    fi

    # 檢查是否為 Debian/Ubuntu
    if ! command -v apt &> /dev/null; then
        log_error "此腳本僅適用於 Debian/Ubuntu 系統"
        exit 1
    fi

    # 檢查網路連接
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "網路連接失敗，請檢查網路設定"
        exit 1
    fi

    # 檢查磁碟空間 (至少需要 5GB)
    local available_space=$(df / | tail -1 | awk '{print $4}')
    if [[ $available_space -lt 5242880 ]]; then  # 5GB in KB
        log_warning "可用磁碟空間少於 5GB，可能會影響安裝"
    fi

    # 檢查記憶體 (至少需要 1GB)
    local total_mem=$(free -m | grep '^Mem:' | awk '{print $2}')
    if [[ $total_mem -lt 1024 ]]; then
        log_warning "系統記憶體少於 1GB，Home Assistant 可能運行緩慢"
    fi

    log_success "系統環境檢查通過"
}

# 更新系統
update_system() {
    log_info "更新系統套件..."
    sudo apt update && sudo apt upgrade -y
}

# 安裝必要依賴
install_dependencies() {
    log_info "安裝必要依賴..."

    # 安裝基本工具
    sudo apt install -y curl wget jq ufw apt-transport-https ca-certificates gnupg lsb-release

    # 安裝 Docker
    log_info "安裝 Docker..."
    if ! command -v docker &> /dev/null; then
        # 添加 Docker 的官方 GPG 金鑰
        curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        # 添加 Docker 倉庫
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # 更新套件列表
        sudo apt update

        # 安裝 Docker
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
        log_info "Docker 已經安裝"
    fi

    # 啟動 Docker 服務
    sudo systemctl enable docker
    sudo systemctl start docker

    # 驗證 Docker 安裝
    if docker --version &> /dev/null; then
        log_success "Docker 安裝成功: $(docker --version)"
    else
        log_error "Docker 安裝失敗"
        exit 1
    fi

    # 安裝 Docker Compose
    log_info "安裝 Docker Compose..."

    # 檢查是否已安裝新版本的 docker compose
    if docker compose version &> /dev/null; then
        log_success "Docker Compose (新版本) 已安裝: $(docker compose version)"
    else
        log_info "安裝 Docker Compose (舊版本兼容)..."

        # 安裝舊版本的 docker-compose 以確保兼容性
        if ! command -v docker-compose &> /dev/null; then
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose

            # 驗證安裝
            if command -v docker-compose &> /dev/null; then
                log_success "Docker Compose 安裝成功: $(docker-compose --version)"
            else
                log_error "Docker Compose 安裝失敗"
                exit 1
            fi
        else
            log_success "Docker Compose 已安裝: $(docker-compose --version)"
        fi
    fi

    # 將當前用戶加入 docker 群組並修復權限
    if ! groups $USER | grep -q docker; then
        sudo usermod -aG docker $USER
        sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
        log_warning "用戶已加入 docker 群組，正在修復權限..."

        # 嘗試重新載入用戶會話
        if command -v newgrp &> /dev/null; then
            newgrp docker << EOF
echo "已切換到 docker 群組"
EOF
        fi
    else
        # 即使已經在群組中，也要確保 socket 權限正確
        if [[ -S /var/run/docker.sock ]]; then
            sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
        fi
    fi

    # 驗證 Docker 權限
    log_info "驗證 Docker 權限..."
    if docker ps &> /dev/null; then
        log_success "Docker 權限正常"
    else
        log_error "Docker 權限仍有問題"
        log_info "請嘗試以下命令之一："
        log_info "1. 重新登入終端機"
        log_info "2. 執行: newgrp docker"
        log_info "3. 或重新啟動系統"
        exit 1
    fi
}

# 配置防火牆
configure_firewall() {
    log_info "配置防火牆..."
    sudo ufw --force enable
    sudo ufw allow ssh
    sudo ufw allow 80
    sudo ufw allow 443
    sudo ufw allow 5000
    sudo ufw allow 5244
    sudo ufw allow 51820
    sudo ufw allow 41641
    sudo ufw allow 8123
    log_success "防火牆已配置完成"
}

# 設置 DuckDNS
setup_duckdns() {
    log_info "設置 DuckDNS..."

    # 提示用戶輸入資訊
    read -p "請輸入您的 DuckDNS 域名 (不包含 .duckdns.org): " DUCKDNS_DOMAIN
    read -p "請輸入您的 DuckDNS Token: " DUCKDNS_TOKEN

    # 驗證輸入
    if [[ -z "$DUCKDNS_DOMAIN" || -z "$DUCKDNS_TOKEN" ]]; then
        log_error "域名和 Token 不能為空"
        exit 1
    fi

    # 創建 DuckDNS 日誌目錄
    mkdir -p "$HOME/.duckdns"

    # 創建 DuckDNS 更新腳本
    cat > duckdns_update.sh << EOF
#!/bin/bash
# DuckDNS 更新腳本

DOMAIN="$DUCKDNS_DOMAIN"
TOKEN="$DUCKDNS_TOKEN"
LOGDIR="$HOME/.duckdns"
LOGFILE="\$LOGDIR/duckdns.log"

# 確保日誌目錄存在
mkdir -p "\$LOGDIR"

# 獲取當前 IP
CURRENT_IP=\$(curl -s https://api.ipify.org)

# 更新 DuckDNS
RESPONSE=\$(curl -s "https://www.duckdns.org/update?domains=\$DOMAIN&token=\$TOKEN&ip=")

if [[ "\$RESPONSE" == "OK" ]]; then
    echo "\$(date): 更新成功 - IP: \$CURRENT_IP" >> "\$LOGFILE"
else
    echo "\$(date): 更新失敗 - \$RESPONSE" >> "\$LOGFILE"
fi
EOF

    # 設置執行權限
    chmod +x duckdns_update.sh

    # 立即執行一次
    ./duckdns_update.sh

    # 設置 cron 任務 (每5分鐘更新一次)
    (crontab -l ; echo "*/5 * * * * $(pwd)/duckdns_update.sh") | crontab -

    log_success "DuckDNS 配置完成"
}

# 安裝和配置 Home Assistant
setup_home_assistant() {
    log_info "安裝 Home Assistant..."

    # 創建 Home Assistant 目錄
    mkdir -p homeassistant/config

    # 創建現代化的 docker-compose.yml (移除過時的 version 字段)
    cat > homeassistant/docker-compose.yml << EOF
services:
  homeassistant:
    container_name: homeassistant
    image: "ghcr.io/home-assistant/home-assistant:stable"
    volumes:
      - ./config:/config
      - /etc/localtime:/etc/localtime:ro
      - /run/dbus:/run/dbus:ro
    restart: unless-stopped
    privileged: true
    network_mode: host
    environment:
      - TZ=Asia/Taipei
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8123"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF

    # 啟動 Home Assistant
    cd homeassistant

    # 確定使用的 Docker Compose 命令
    if docker compose version &> /dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        log_info "使用新版 Docker Compose: $(docker compose version)"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        log_info "使用舊版 Docker Compose: $(docker-compose --version)"
    else
        log_error "找不到 Docker Compose 命令"
        exit 1
    fi

    # 拉取鏡像
    log_info "下載 Home Assistant 鏡像..."
    $COMPOSE_CMD pull

    # 啟動服務
    log_info "啟動 Home Assistant..."
    $COMPOSE_CMD up -d

    # 等待服務啟動
    log_info "等待 Home Assistant 啟動..."
    sleep 30

    # 檢查服務狀態
    if $COMPOSE_CMD ps | grep -q "Up"; then
        log_success "Home Assistant 安裝並啟動成功"
    else
        log_error "Home Assistant 啟動失敗"
        log_info "檢查日誌: $COMPOSE_CMD logs"
        exit 1
    fi

    # 顯示訪問資訊
    local vm_ip=$(hostname -I | awk '{print $1}')
    log_info "Home Assistant 正在啟動中..."
    log_info "本地訪問地址: http://${vm_ip}:8123"
    log_info "請等待 5-10 分鐘讓 Home Assistant 完成初始化"
    log_info "首次訪問時需要進行初始配置"

    # 創建健康檢查腳本
    cat > check_health.sh << EOF
#!/bin/bash
# Home Assistant 健康檢查腳本

MAX_WAIT=600  # 最多等待10分鐘
WAIT_TIME=0

echo "檢查 Home Assistant 健康狀態..."

while [ \$WAIT_TIME -lt \$MAX_WAIT ]; do
    if curl -f http://localhost:8123 &>/dev/null; then
        echo "✅ Home Assistant 已準備就緒!"
        echo "訪問地址: http://localhost:8123"
        exit 0
    fi

    echo "等待中... (\$WAIT_TIME/\$MAX_WAIT 秒)"
    sleep 10
    WAIT_TIME=\$((WAIT_TIME + 10))
done

    echo "❌ Home Assistant 啟動超時"
echo "請檢查日誌: docker compose logs 或 docker-compose logs"
exit 1
EOF

    chmod +x check_health.sh
    log_info "健康檢查腳本已創建: ./check_health.sh"
}

# 安裝 Caddy 作為反向代理 (提供 HTTPS)
setup_caddy() {
    log_info "安裝 Caddy 反向代理..."

    # 安裝 Caddy
    if ! command -v caddy &> /dev/null; then
        log_info "下載並安裝 Caddy..."
        # 安裝 Caddy 使用官方安裝腳本
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
        sudo apt update
        sudo apt install -y caddy
    else
        log_info "Caddy 已經安裝"
    fi

    # 停止 Caddy 以進行配置
    sudo systemctl stop caddy

    # 創建更完善的 Caddy 配置
    sudo tee /etc/caddy/Caddyfile > /dev/null << EOF
# Home Assistant HTTPS 配置
$DUCKDNS_DOMAIN.duckdns.org {
    # 啟用自動 HTTPS
    tls {
        protocols tls1.2 tls1.3
    }

    # 反向代理到 Home Assistant
    reverse_proxy localhost:8123 {
        # 放寬健康檢查設定
        health_uri /
        health_interval 60s
        health_timeout 30s
        health_status 200-399

        # WebSocket 支持 (重要!)
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection {http.request.header.Connection}

        # 增加超時時間
        transport http {
            read_timeout 300s
            write_timeout 300s
        }
    }

    # 安全頭
    header {
        # 啟用 HSTS
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        # 防止點擊劫持
        X-Frame-Options "SAMEORIGIN"
        # 防止 MIME 類型嗅探
        X-Content-Type-Options "nosniff"
        # 防止 XSS 攻擊
        X-XSS-Protection "1; mode=block"
        # 隱藏 Caddy 版本
        -Server
    }

    # 日誌
    log {
        output file /var/log/caddy/access.log
        format json
    }
}
EOF

    # 創建日誌目錄
    sudo mkdir -p /var/log/caddy
    sudo chown caddy:caddy /var/log/caddy

    # 驗證配置
    log_info "驗證 Caddy 配置..."
    if sudo caddy validate --config /etc/caddy/Caddyfile; then
        log_success "Caddy 配置驗證通過"
    else
        log_warning "高級配置驗證失敗，嘗試使用簡化配置..."

        # 創建簡化的 Caddy 配置
        sudo tee /etc/caddy/Caddyfile > /dev/null << EOF
# Home Assistant 簡化 HTTPS 配置
$DUCKDNS_DOMAIN.duckdns.org {
    # 反向代理到 Home Assistant
    reverse_proxy localhost:8123 {
        # 放寬健康檢查
        health_uri /
        health_interval 60s
        health_timeout 30s
    }

    # 基本安全頭
    header X-Frame-Options "SAMEORIGIN"
    header X-Content-Type-Options "nosniff"
}
EOF

        # 再次驗證簡化配置
        if sudo caddy validate --config /etc/caddy/Caddyfile; then
            log_success "簡化 Caddy 配置驗證通過"
        else
            log_error "簡化 Caddy 配置仍有問題"
            exit 1
        fi
    fi

    # 等待 Home Assistant 完全啟動
    log_info "等待 Home Assistant 完全啟動..."
    local max_wait=120  # 最多等待2分鐘
    local wait_time=0

    while [ $wait_time -lt $max_wait ]; do
        if curl -f -s http://localhost:8123 > /dev/null 2>&1; then
            log_success "Home Assistant 已準備就緒"
            break
        fi
        echo "等待 Home Assistant 啟動... ($wait_time/$max_wait 秒)"
        sleep 10
        wait_time=$((wait_time + 10))
    done

    if [ $wait_time -ge $max_wait ]; then
        log_warning "Home Assistant 啟動較慢，但繼續啟動 Caddy"
    fi

    # 啟動 Caddy
    sudo systemctl enable caddy
    sudo systemctl start caddy

    # 等待 Caddy 啟動
    sleep 10

    # 檢查 Caddy 狀態
    if sudo systemctl is-active --quiet caddy; then
        log_success "Caddy HTTPS 反向代理配置完成"
        log_info "您的 Home Assistant 現在可以通過 https://$DUCKDNS_DOMAIN.duckdns.org 訪問"
    else
        log_error "Caddy 啟動失敗"
        log_info "檢查日誌: sudo journalctl -u caddy -f"

        # 嘗試重新啟動 Caddy
        log_info "嘗試重新啟動 Caddy..."
        sudo systemctl restart caddy
        sleep 5

        if sudo systemctl is-active --quiet caddy; then
            log_success "Caddy 重新啟動成功"
        else
            log_warning "Caddy 仍無法啟動，但配置已保存"
            log_info "您可以稍後手動啟動: sudo systemctl start caddy"
        fi
    fi
}

# 顯示完成資訊
show_completion_info() {
    log_success "🎉 所有設置已完成！"
    echo ""
    log_info "📋 重要資訊："

    local vm_ip=$(hostname -I | awk '{print $1}')
    echo "🌐 公網訪問: https://$DUCKDNS_DOMAIN.duckdns.org"
    echo "🏠 本地訪問: http://$vm_ip:8123"
    echo ""
    echo "📁 重要路徑："
    echo "  • Home Assistant 配置: $(pwd)/homeassistant/config"
    echo "  • DuckDNS 更新腳本: $(pwd)/duckdns_update.sh"
    echo "  • DuckDNS 日誌: $HOME/.duckdns/duckdns.log"
    echo "  • Caddy 日誌: /var/log/caddy/access.log"
    echo "  • Docker Compose 文件: $(pwd)/homeassistant/docker-compose.yml"
    echo ""
    echo "🔧 管理命令："
    echo "  • 檢查 Home Assistant: cd homeassistant && docker compose ps"
    echo "  • 查看 Home Assistant 日誌: cd homeassistant && docker compose logs -f"
    echo "  • 重啟 Home Assistant: cd homeassistant && docker compose restart"
    echo "  • (舊版兼容) docker-compose ps / logs / restart"
    echo "  • 檢查 Caddy 狀態: sudo systemctl status caddy"
    echo "  • 查看 Caddy 日誌: sudo journalctl -u caddy -f"
    echo "  • 檢查防火牆: sudo ufw status"
    echo ""
    log_warning "⚠️  重要提醒："
    echo "1. 首次訪問 Home Assistant 時需要進行初始配置"
    echo "2. 請等待 5-10 分鐘讓 Home Assistant 完全啟動"
    echo "3. DuckDNS 會每 5 分鐘自動更新 IP 地址"
    echo "4. 如果無法訪問，請檢查 GCP 防火牆規則允許 80/443 端口"
    echo ""
    echo "🩺 健康檢查："
    echo "  • Home Assistant: $(pwd)/homeassistant/check_health.sh"
    echo "  • 手動測試: curl -f https://$DUCKDNS_DOMAIN.duckdns.org"
    echo ""
    log_info "✨ 享受您的 Home Assistant 體驗！"
}

# 主函數
main() {
    echo ""
    echo "=========================================="
    echo "🚀 DuckDNS + Home Assistant HTTPS 設置腳本"
    echo "=========================================="
    echo ""

    log_info "開始設置 DuckDNS + Home Assistant HTTPS..."

    # 第一步：系統環境檢查
    check_system

    # 第二步：立即詢問用戶輸入 DuckDNS 資訊
    log_info "請先輸入您的 DuckDNS 資訊..."
    setup_duckdns

    # 第三步：系統準備
    update_system
    install_dependencies
    configure_firewall

    # 第四步：安裝主要服務
    setup_home_assistant
    setup_caddy
    show_completion_info

    echo ""
    echo "=========================================="
    log_success "🎉 所有設置已完成！請重新登入終端機以使用 Docker。"
    echo "=========================================="
}

# 運行主函數
main "$@"
