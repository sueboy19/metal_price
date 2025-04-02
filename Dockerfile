FROM alpine:latest

# 安裝必要的工具
RUN apk add --no-cache curl jq tzdata

# 設置時區為亞洲/台北
RUN cp /usr/share/zoneinfo/Asia/Taipei /etc/localtime && \
    echo "Asia/Taipei" > /etc/timezone

# 創建數據目錄
RUN mkdir -p /data

# 複製腳本到容器
COPY fetch_metal_price.sh /usr/local/bin/fetch_metal_price.sh
RUN chmod +x /usr/local/bin/fetch_metal_price.sh

# 設置工作目錄
WORKDIR /data

# 執行腳本
CMD ["/usr/local/bin/fetch_metal_price.sh"]
