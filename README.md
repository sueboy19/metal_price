# 即時金屬價格追蹤器

一個基於 Docker 的即時金屬價格監控應用，可以顯示黃金和白銀的最新價格，並支持多種計量單位和幣別換算。

## 功能特點

- 自動獲取黃金和白銀的實時價格
- 支持多種單位顯示（盎司、克、兩、錢）
- 同時顯示美元和新台幣價格
- 自適應設計，適合各種裝置查看
- 實時獲取美元兌新台幣匯率
- 千分位格式化，提高數字可讀性

## 系統需求

- Docker
- Docker Compose

## 快速開始

1. 克隆此倉庫：

   ```bash
   git clone https://github.com/yourusername/metal-price
   cd metal-price
   ```

2. 啟動應用：

   ```bash
   docker compose up -d
   ```

3. 在瀏覽器中訪問：

   ```
   http://localhost:8088
   ```

4. 查看 log：
   ```bash
   docker compose logs -f
   ```

## Docker-Compose 設定說明

在 `docker-compose.yml` 文件中，您可以自定義多項設置，特別是數據更新頻率：

```yaml
services:
  metal-price-tracker:
    # ...existing code...
    environment:
      - FETCH_INTERVAL=30 # 設置獲取資料的間隔秒數，可以根據需求調整
      - EXCHANGE_RATE_INTERVAL=3600 # 設置獲取匯率的間隔秒數
```

### 參數說明

- **FETCH_INTERVAL**：控制系統獲取最新金屬價格的頻率（以秒為單位）

  - 預設值：30 秒
  - 建議值：
    - 開發測試環境：10-30 秒
    - 生產環境：60-300 秒（避免過於頻繁的 API 請求）

- **EXCHANGE_RATE_INTERVAL**：控制系統獲取匯率的頻率（以秒為單位）
  - 預設值：3600 秒（1 小時）
  - 建議值：
    - 開發測試環境：600-1800 秒
    - 生產環境：3600-86400 秒（匯率變化相對較慢）

注意：設置過短的間隔可能會導致 API 請求限制或 IP 被暫時封鎖。

## 文件結構

```
metal_price/
├── data/                 # 數據存儲目錄
│   └── metal_prices.json # 最新金屬價格數據
│   └── backup_exchange_rate.txt # 備用匯率檔案
├── public/               # 靜態文件
│   └── index.html        # 網頁前端
├── nginx/
│   └── nginx.conf        # Nginx 主要配置
│   └── rate_limit.conf   # Nginx 請求限制配置
├── Dockerfile            # Docker 映像配置
├── docker-compose.yml    # Docker Compose 配置
├── fetch_metal_price.sh  # 數據獲取腳本
└── README.md             # 本文檔
```

## 技術堆疊

- 後端：Shell 腳本 + jq
- 數據獲取：curl
- 前端：HTML + CSS + JavaScript
- 容器化：Docker + Docker Compose
- 網絡服務器：Nginx

## 感謝

本項目使用了以下開源資源和 API：

- [金屬價格 API](https://api.gold-api.com/) - 提供黃金、白銀等貴金屬的實時價格
- [Yahoo Finance API](https://finance.yahoo.com/) - 提供實時匯率數據
- [jq](https://stedolan.github.io/jq/) - 用於處理 JSON 數據的命令行工具
- [Docker](https://www.docker.com/) - 容器化平台
- [Nginx](https://nginx.org/) - 高性能網絡服務器

## 資料單位換算參考

- 1 盎司 (oz) = 31.1035 克 (g)
- 1 兩 = 37.5 克 (g)
- 1 錢 = 3.75 克 (g)

## 授權

本項目採用 MIT 授權。詳情請參閱 LICENSE 文件。

## 免責聲明

本應用僅供參考，不應作為投資決策的唯一依據。價格數據來源於第三方 API，無法保證其準確性或及時性。
