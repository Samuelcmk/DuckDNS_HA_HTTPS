# 🚀 DuckDNS + Home Assistant 一鍵安裝腳本

一鍵在 GCP Debian VM 上安裝 Home Assistant，包含 DuckDNS 域名和自動 HTTPS 配置。

## ✨ 核心功能

- 🔍 **智能系統檢查** - 自動驗證環境要求
- 🐳 **Docker 完整安裝** - 官方 Docker CE + Docker Compose
- 🌐 **DuckDNS 自動更新** - 每5分鐘更新域名IP
- 🏠 **Home Assistant** - Docker 容器化安裝
- 🔒 **自動 HTTPS** - Caddy 反向代理 + Let's Encrypt SSL
- 🛡️ **安全配置** - 防火牆 + 安全頭配置

## 🚀 快速開始

### 前置要求
- GCP Debian/Ubuntu VM
- DuckDNS 帳號和 Token (免費註冊：https://duckdns.org)
- Root 或 sudo 權限

### 一鍵安裝

```bash
# 1. 下載腳本
wget https://raw.githubusercontent.com/your-repo/setup_duckdns_homeassistant.sh

# 2. 設置執行權限
chmod +x setup_duckdns_homeassistant.sh

# 3. 運行安裝（會立即詢問 DuckDNS 資訊）
./setup_duckdns_homeassistant.sh
```

### 安裝流程
1. 🔍 **系統檢查** - 驗證環境要求
2. 🌐 **DuckDNS 配置** - 輸入域名和 Token
3. 📦 **系統更新** - 安裝依賴和 Docker
4. 🏠 **Home Assistant** - Docker 容器安裝
5. 🔒 **HTTPS 配置** - Caddy 反向代理
6. ✅ **完成** - 顯示訪問地址

## 📋 訪問地址

安裝完成後，您可以通過以下地址訪問：

- 🌐 **公網訪問**: `https://yourdomain.duckdns.org`
- 🏠 **本地訪問**: `http://VM_IP:8123`
- 📁 **配置目錄**: `~/homeassistant/config`
- 📝 **DuckDNS 日誌**: `~/.duckdns/duckdns.log`

## ⚠️ 重要提醒

- 🚫 **不要使用 root 用戶**運行安裝腳本
- 🔄 **Docker 權限**: 安裝後重新登入或執行 `newgrp docker`
- ⏳ **首次訪問**: Home Assistant 需要 5-10 分鐘初始化
- 🛡️ **防火牆**: 確保 GCP 防火牆允許 80/443/8123 端口

## 🔧 故障排除

### 🚫 常見問題及解決方案

| 問題 | 症狀 | 解決方案 |
|------|------|----------|
| **Docker 權限錯誤** | `permission denied` | `newgrp docker` 或重新登入 |
| **Caddy HTTPS 失敗** | 無法訪問 HTTPS | `sudo systemctl status caddy` |
| **Home Assistant 未啟動** | 無法訪問本地端口 | `docker compose logs -f` |
| **DuckDNS 更新失敗** | 日誌顯示錯誤 | `tail -f ~/.duckdns/duckdns.log` |

### 🛠️ 常用命令

```bash
# 檢查服務狀態
sudo systemctl status caddy
docker compose ps

# 查看日誌
docker compose logs -f
sudo journalctl -u caddy -f
tail -f ~/.duckdns/duckdns.log

# 重啟服務
docker compose restart
sudo systemctl restart caddy

# 檢查防火牆
sudo ufw status
```

## 🛡️ 安全建議

- 🔄 **定期更新**: `sudo apt update && sudo apt upgrade`
- 🔑 **強密碼**: 設置複雜的系統密碼
- 🛡️ **防火牆**: 定期檢查 `sudo ufw status`
- 📝 **監控日誌**: 檢查 DuckDNS 更新日誌

## 📦 數據備份

Home Assistant 配置存儲在 `~/homeassistant/config/` 目錄中。如需備份：

```bash
# 備份配置目錄
cp -r ~/homeassistant/config ~/homeassistant_config_backup

# 查看配置大小
du -sh ~/homeassistant/config/
```

## 🆘 常見問題解決

### Docker 權限問題
如果遇到 `permission denied` 錯誤：

```bash
# 重新載入 Docker 群組
newgrp docker

# 或重新登入終端機
```

### Home Assistant 無法訪問
如果無法訪問本地端口：

```bash
# 檢查容器狀態
cd ~/homeassistant
docker compose ps

# 查看日誌
docker compose logs -f

# 重啟服務
docker compose restart
```

### HTTPS 證書問題
如果 HTTPS 無法正常工作：

```bash
# 檢查 Caddy 狀態
sudo systemctl status caddy

# 查看 Caddy 日誌
sudo journalctl -u caddy -f

# 重啟 Caddy
sudo systemctl restart caddy
```

## 📞 技術支援

遇到問題時，請檢查以下資訊：

### 系統資訊
- 錯誤信息和完整日誌
- 系統版本：`uname -a`
- Docker 版本：`docker --version`

### 服務狀態檢查
```bash
# 檢查所有服務狀態
docker compose ps
sudo systemctl status caddy

# 查看詳細日誌
docker compose logs -f
sudo journalctl -u caddy -f
tail -f ~/.duckdns/duckdns.log
```

### 網路連接測試
```bash
# 測試本地訪問
curl -f http://localhost:8123

# 測試 HTTPS 訪問
curl -f https://yourdomain.duckdns.org
```
