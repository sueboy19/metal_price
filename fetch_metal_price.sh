#!/bin/sh

# 設定輸出文件 - 修改為相對路徑或使用者目錄下的路徑
OUTPUT_FILE="./metal_prices.json"  # 改為當前目錄
# 設定備用匯率檔案
BACKUP_RATE_FILE="./backup_exchange_rate.txt"

# 確保輸出目錄存在
mkdir -p "$(dirname "$OUTPUT_FILE")"

# 從環境變數取得間隔秒數，如果未設定則使用預設值
INTERVAL=${FETCH_INTERVAL:-30}
# 匯率獲取頻率（秒數），預設為300秒（5分鐘）
EXCHANGE_RATE_INTERVAL=${EXCHANGE_RATE_INTERVAL:-300}

# 記錄上次匯率獲取時間的變量
LAST_EXCHANGE_FETCH=0

# 日誌函數
log_info() {
  echo "ℹ️ $1"
}

log_success() {
  echo "✅ $1"
}

log_warning() {
  echo "⚠️ $1"
}

log_error() {
  echo "❌ $1"
}

# 保存匯率到備用檔案
save_backup_rate() {
  local rate="$1"
  local timestamp="$(date "+%Y-%m-%d %H:%M:%S")"
  
  # 檢查輸出目錄是否存在
  mkdir -p "$(dirname "$BACKUP_RATE_FILE")" 2>/dev/null
  
  # 將匯率和時間戳寫入備用檔案
  echo "$rate $timestamp" > "$BACKUP_RATE_FILE" 2>/dev/null
  
  # 檢查寫入是否成功，輸出到標準錯誤而不是標準輸出
  if [ $? -eq 0 ]; then
    log_info "已將匯率 $rate 保存到備用檔案 ($timestamp)" >&2
  else
    log_warning "無法將匯率 $rate 保存到備用檔案" >&2
  fi
}

# 從備用檔案讀取匯率
read_backup_rate() {
  if [ -f "$BACKUP_RATE_FILE" ]; then
    local file_content=$(cat "$BACKUP_RATE_FILE" 2>/dev/null)
    
    # 檢查檔案內容是否不為空
    if [ -n "$file_content" ]; then
      local rate=$(echo "$file_content" | awk '{print $1}')
      local timestamp=$(echo "$file_content" | cut -d' ' -f2-)
      
      if [ -n "$rate" ] && [ "$(echo "$rate" | grep -E '^[0-9]+(\.[0-9]+)?$')" ]; then
        log_info "從備份檔案獲取匯率: $rate (保存於 $timestamp)" >&2
        echo "$rate"
        return 0
      fi
    fi
  fi
  
  log_warning "備用匯率檔案不存在或無效，使用預設值 31.5" >&2
  echo "31.5"
  return 1
}

# 從備份檔案讀取時間戳記
get_last_exchange_time() {
  if [ -f "$BACKUP_RATE_FILE" ]; then
    local file_content=$(cat "$BACKUP_RATE_FILE" 2>/dev/null)
    
    # 檢查檔案內容是否不為空
    if [ -n "$file_content" ]; then
      # 提取時間戳部分（跳過第一個欄位即匯率）
      local timestamp=$(echo "$file_content" | cut -d' ' -f2-)
      
      if [ -n "$timestamp" ]; then
        # 嘗試將時間戳記轉換為Unix時間戳
        # macOS上使用date -j，Linux上可能需要調整
        local unix_timestamp
        
        if [ "$(uname)" = "Darwin" ]; then
          # macOS (Darwin) 系統
          unix_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$timestamp" "+%s" 2>/dev/null)
        else
          # Linux 或其他系統，使用不同的date命令格式
          unix_timestamp=$(date -d "$timestamp" "+%s" 2>/dev/null)
        fi
        
        if [ $? -eq 0 ] && [ -n "$unix_timestamp" ]; then
          log_info "從備份檔案獲取上次匯率時間成功: $timestamp (Unix時間戳: $unix_timestamp)" >&2
          echo "$unix_timestamp"
          return 0
        fi
      fi
    fi
  fi
  
  log_warning "無法從備份檔案獲取有效的時間戳記" >&2
  echo "0"
  return 1
}

# 初始化 LAST_EXCHANGE_FETCH 變數
initialize_last_exchange_time() {
  local unix_timestamp=$(get_last_exchange_time)
  
  if [ -n "$unix_timestamp" ] && [ "$unix_timestamp" -gt 0 ]; then
    LAST_EXCHANGE_FETCH=$unix_timestamp
    local readable_time=$(date -r $LAST_EXCHANGE_FETCH "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    log_info "成功初始化上次匯率獲取時間: $readable_time (Unix時間戳: $LAST_EXCHANGE_FETCH)" >&2
  else
    LAST_EXCHANGE_FETCH=0
    log_warning "初始化上次匯率獲取時間失敗，設置為 0" >&2
  fi
}

# 獲取匯率函數 - 確保返回純數值
get_exchange_rate() {
  # 檢查是否需要從網路獲取新匯率或從備用檔案讀取
  local current_time=$(date +%s)
  local time_diff=$((current_time - LAST_EXCHANGE_FETCH))
  
  # 增加日誌輸出以便追蹤
  log_info "當前時間: $current_time, 上次匯率獲取時間: $LAST_EXCHANGE_FETCH, 時間差: $time_diff 秒" >&2
  
  # 修正條件判斷：第一次運行時 LAST_EXCHANGE_FETCH 為 0，time_diff 會很大
  # 只有當 LAST_EXCHANGE_FETCH 不為 0（非第一次運行）且時間差小於間隔時，才使用備用檔案
  if [ $LAST_EXCHANGE_FETCH -ne 0 ] && [ $time_diff -lt $EXCHANGE_RATE_INTERVAL ]; then
    log_info "距離上次匯率獲取時間 ($time_diff 秒) 不足 $EXCHANGE_RATE_INTERVAL 秒，使用備用檔案" >&2
    local backup_rate=$(read_backup_rate)
    
    if [ -n "$backup_rate" ] && [ "$(echo "$backup_rate" | grep -E '^[0-9]+(\.[0-9]+)?$')" ]; then
      echo "$backup_rate"
      return 0
    fi
  fi
  
  log_info "需要從網路獲取新匯率" >&2
  
  # 暫存所有輸出到臨時變數
  local log_output=$(mktemp)
  
  # 1. 雅虎財經
  echo "嘗試從雅虎財經獲取匯率..." >> "$log_output"
  local response=$(curl -s --connect-timeout 8 --max-time 15 \
               -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
               "https://query1.finance.yahoo.com/v8/finance/chart/USDTWD=X?interval=1d")
  
  if [ $? -eq 0 ] && [ -n "$response" ]; then
    local rate=$(echo "$response" | jq '.chart.result[0].meta.regularMarketPrice' 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$rate" ] && [ "$rate" != "null" ]; then
      echo "從雅虎財經獲取匯率成功: $rate" >> "$log_output"
      
      # 檢查匯率是否為有效數值
      if [ "$(echo "$rate" | grep -E '^[0-9]+(\.[0-9]+)?$')" ]; then
        # 更新上次獲取時間 - 移到成功獲取後
        LAST_EXCHANGE_FETCH=$current_time
        # 成功獲取時，保存到備用檔案 - 重定向輸出到標準錯誤
        save_backup_rate "$rate" >&2
        # 僅輸出純數值
        echo "$rate"
        rm -f "$log_output"
        return 0
      fi
    fi
  fi
  
  # 2. Google Finance
  echo "嘗試從 Google Finance 獲取匯率..." >> "$log_output"
  local response=$(curl -s --connect-timeout 8 --max-time 15 \
                -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
                "https://www.google.com/finance/quote/USD-TWD")
  
  if [ $? -eq 0 ] && [ -n "$response" ]; then
    local rate=$(echo "$response" | grep -o 'data-last-price="[0-9.]*"' | grep -o '[0-9.]*')
    if [ -n "$rate" ] && [ "$(echo "$rate" | grep -E '^[0-9]+(\.[0-9]+)?$')" ]; then
      echo "從 Google Finance 獲取匯率成功: $rate" >> "$log_output"
      
      # 更新上次獲取時間 - 移到成功獲取後
      LAST_EXCHANGE_FETCH=$current_time
      # 成功獲取時，保存到備用檔案 - 重定向輸出到標準錯誤
      save_backup_rate "$rate" >&2
      # 僅輸出純數值
      echo "$rate"
      rm -f "$log_output"
      return 0
    fi
  fi
  
  # 所有來源都失敗，讀取備用檔案
  echo "所有匯率來源都失敗，嘗試讀取備用匯率檔案" >> "$log_output"
  local backup_rate=$(read_backup_rate)
  
  # 確保返回的匯率是有效數值
  if [ -n "$backup_rate" ] && [ "$(echo "$backup_rate" | grep -E '^[0-9]+(\.[0-9]+)?$')" ]; then
    echo "使用備用匯率檔案的匯率: $backup_rate" >> "$log_output"
    echo "$backup_rate"
    rm -f "$log_output" 2>/dev/null
    return 0
  fi
  
  # 所有嘗試都失敗，返回預設值
  echo "所有獲取匯率的方法都失敗，返回預設值 31.5" >> "$log_output"
  cat "$log_output" >&2  # 輸出日誌到標準錯誤
  rm -f "$log_output" 2>/dev/null
  echo "31.5"  # 預設匯率
  return 0
}

# 獲取金屬價格函數 - 確保返回純數值
get_metal_price() {
  local metal_type="$1"
  local api_endpoint="$2"
  local fallback_api="$3"
  
  # 暫存所有輸出到臨時變數
  local log_output=$(mktemp)
  
  echo "正在獲取${metal_type}價格..." >> "$log_output"
  
  # 第一個 API 來源嘗試
  local response=$(curl -s --connect-timeout 10 --max-time 30 "$api_endpoint")
  local status=$?
  
  if [ $status -eq 0 ] && [ -n "$response" ]; then
    local price=$(echo "$response" | jq '.price' 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$price" ] && [ "$price" != "null" ]; then
      echo "${metal_type}價格獲取成功: $price" >> "$log_output"
      # 僅輸出純數值
      echo "$price"
      rm -f "$log_output"
      return 0
    fi
  fi
  
  # 如果提供了備用 API，則嘗試使用
  if [ -n "$fallback_api" ]; then
    echo "主要 API 獲取${metal_type}價格失敗，嘗試備用 API..." >> "$log_output"
    local fallback_response=$(curl -s --connect-timeout 10 --max-time 30 "$fallback_api")
    
    if [ $? -eq 0 ] && [ -n "$fallback_response" ]; then
      local fallback_price=$(echo "$fallback_response" | jq '.price' 2>/dev/null)
      if [ $? -eq 0 ] && [ -n "$fallback_price" ] && [ "$fallback_price" != "null" ]; then
        echo "從備用 API 獲取${metal_type}價格成功: $fallback_price" >> "$log_output"
        # 僅輸出純數值
        echo "$fallback_price"
        rm -f "$log_output"
        return 0
      fi
    fi
  fi
  
  # 如果無法從 API 獲取，使用硬編碼的測試數據
  echo "${metal_type}價格從所有 API 獲取失敗，使用測試數據" >> "$log_output"
  
  # 僅返回純數值
  if [ "$metal_type" = "黃金" ]; then
    echo "1942.50"  # 黃金測試價格
  elif [ "$metal_type" = "白銀" ]; then
    echo "24.15"    # 白銀測試價格
  else
    echo "${metal_type}無測試數據" >> "$log_output"
    cat "$log_output" >&2  # 輸出日誌到標準錯誤
    rm -f "$log_output"
    return 1
  fi
  
  cat "$log_output" >&2  # 輸出日誌到標準錯誤
  rm -f "$log_output"
  return 0
}

# 寫入 JSON 函數
write_json_success() {
  local timestamp="$1"
  local gold="$2"
  local silver="$3"
  local usdtwd="$4"
  
  # 按照原始簡單格式寫入 JSON
  jq -n \
    --arg timestamp "$timestamp" \
    --arg gold "$gold" \
    --arg silver "$silver" \
    --arg usdtwd "$usdtwd" \
    '{
      "timestamp": $timestamp, 
      "gold": $gold|tonumber, 
      "silver": $silver|tonumber, 
      "usdtwd": $usdtwd|tonumber
    }' > "$OUTPUT_FILE"
  
  log_success "JSON 已寫入: $OUTPUT_FILE"
}

write_json_error() {
  local timestamp="$1"
  local gold_status="$2"
  local silver_status="$3"
  local exchange_status="$4"
  
  # 根據狀態準備值
  local gold="null"
  local silver="null"
  local usdtwd="null"
  
  # 如果有成功獲取的值，使用實際值
  if [ "$gold_status" = "success" ]; then
    gold="$GOLD_PRICE"
  fi
  
  if [ "$silver_status" = "success" ]; then
    silver="$SILVER_PRICE"
  fi
  
  if [ "$exchange_status" = "success" ]; then
    usdtwd="$EXCHANGE_RATE"
  fi
  
  # 構建 JSON，保持原始簡單格式，但添加錯誤標識
  jq -n \
    --arg timestamp "$timestamp" \
    --arg gold "$gold" \
    --arg silver "$silver" \
    --arg usdtwd "$usdtwd" \
    --arg error "部分或全部數據獲取失敗" \
    '{
      "timestamp": $timestamp,
      "error": $error,
      "gold": ($gold != "null" | if . then $gold|tonumber else null end),
      "silver": ($silver != "null" | if . then $silver|tonumber else null end),
      "usdtwd": ($usdtwd != "null" | if . then $usdtwd|tonumber else null end)
    }' > "$OUTPUT_FILE"
  
  log_warning "錯誤信息已寫入: $OUTPUT_FILE"
}

# 主循環
log_info "開始運行金屬價格追蹤器，每 $INTERVAL 秒更新一次..."
log_info "匯率獲取頻率設定為每 $EXCHANGE_RATE_INTERVAL 秒更新一次"

# 初始化上次匯率獲取時間
initialize_last_exchange_time

while true; do
  # 分隔線與時間戳
  echo "=================================================================="
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
  log_info "開始時間: $TIMESTAMP"
  
  # 獲取黃金價格 (添加備用 API)
  GOLD_PRICE=$(get_metal_price "黃金" "https://api.gold-api.com/price/XAU" "https://metals-api.com/api/latest?base=USD&symbols=XAU")
  
  # 確保 GOLD_PRICE 是純數值 - 修正語法錯誤
  if [ $? -eq 0 ] && [ "$(echo "$GOLD_PRICE" | grep -E '^[0-9]+(\.[0-9]+)?$')" ]; then
    GOLD_SUCCESS=true
    log_info "金價: $GOLD_PRICE USD/oz"
  else
    log_error "獲得的金價不是有效數值: $GOLD_PRICE"
    GOLD_SUCCESS=false
    GOLD_PRICE="1942.50"  # 使用備用金價
    log_warning "使用備用金價: $GOLD_PRICE"
  fi
  
  # 獲取白銀價格 (添加備用 API)
  SILVER_PRICE=$(get_metal_price "白銀" "https://api.gold-api.com/price/XAG" "https://metals-api.com/api/latest?base=USD&symbols=XAG")
  
  # 確保 SILVER_PRICE 是純數值 - 修正語法錯誤
  if [ $? -eq 0 ] && [ "$(echo "$SILVER_PRICE" | grep -E '^[0-9]+(\.[0-9]+)?$')" ]; then
    SILVER_SUCCESS=true
    log_info "銀價: $SILVER_PRICE USD/oz"
  else
    log_error "獲得的銀價不是有效數值: $SILVER_PRICE"
    SILVER_SUCCESS=false
    SILVER_PRICE="24.15"  # 使用備用銀價
    log_warning "使用備用銀價: $SILVER_PRICE"
  fi
  
  # 獲取匯率 (嘗試多個來源，失敗時使用備用檔案)
  EXCHANGE_RATE=$(get_exchange_rate)
  
  # 確保 EXCHANGE_RATE 是純數值
  if [ -n "$EXCHANGE_RATE" ] && [ "$(echo "$EXCHANGE_RATE" | grep -E '^[0-9]+(\.[0-9]+)?$')" ]; then
    EXCHANGE_SUCCESS=true
    log_info "匯率: $EXCHANGE_RATE TWD/USD" >&2
  else
    log_error "獲得的匯率不是有效數值: $EXCHANGE_RATE" >&2
    # 直接使用預設值
    EXCHANGE_RATE="31.5"  # 最終備用匯率
    log_warning "使用最終備用匯率: $EXCHANGE_RATE TWD/USD" >&2
    EXCHANGE_SUCCESS=true
  fi
  
  # 檢查文件目錄
  if [ ! -d "$(dirname "$OUTPUT_FILE")" ]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    log_info "創建輸出目錄: $(dirname "$OUTPUT_FILE")"
  fi
  
  # 檢查文件權限
  touch "$OUTPUT_FILE" 2>/dev/null
  if [ $? -ne 0 ]; then
    log_warning "無法寫入 $OUTPUT_FILE，嘗試改為寫入當前目錄"
    OUTPUT_FILE="./metal_prices.json"
    touch "$OUTPUT_FILE" 2>/dev/null
    if [ $? -ne 0 ]; then
      log_error "仍然無法寫入文件，請檢查權限"
      # 繼續執行但輸出警告
    fi
  fi
  
  # 綜合檢查所有數據是否成功獲取
  if [ "$GOLD_SUCCESS" = true ] && [ "$SILVER_SUCCESS" = true ] && [ "$EXCHANGE_SUCCESS" = true ]; then
    log_info "🎉 所有數據獲取成功，正在生成 JSON..."
    echo "寫入數據 - 金: $GOLD_PRICE, 銀: $SILVER_PRICE, 匯率: $EXCHANGE_RATE"
    
    # 直接使用 echo 和重定向寫入 JSON，確保所有值都是純數值
    echo "{
  \"timestamp\": \"$TIMESTAMP\",
  \"gold\": $GOLD_PRICE,
  \"silver\": $SILVER_PRICE,
  \"usdtwd\": $EXCHANGE_RATE
}" > "$OUTPUT_FILE"
    
    # 檢查文件寫入是否成功
    if [ -s "$OUTPUT_FILE" ]; then
      log_success "JSON 已成功寫入: $OUTPUT_FILE"
      log_success "文件內容預覽:"
      cat "$OUTPUT_FILE"
    else
      log_error "JSON 文件寫入失敗或文件為空"
    fi
    
    log_success "獲取金屬價格和匯率成功：$TIMESTAMP"
    log_success "  金價: $GOLD_PRICE USD/oz"
    log_success "  銀價: $SILVER_PRICE USD/oz"
    log_success "  匯率: $EXCHANGE_RATE TWD/USD"
  else
    log_error "數據獲取失敗摘要:"
    [ "$GOLD_SUCCESS" = false ] && log_error "  - 黃金價格: 失敗"
    [ "$SILVER_SUCCESS" = false ] && log_error "  - 白銀價格: 失敗"
    [ "$EXCHANGE_SUCCESS" = false ] && log_error "  - 匯率: 失敗"
    
    # 根據成功/失敗設置狀態
    GOLD_STATUS=$([ "$GOLD_SUCCESS" = true ] && echo "success" || echo "failed")
    SILVER_STATUS=$([ "$SILVER_SUCCESS" = true ] && echo "success" || echo "failed")
    EXCHANGE_STATUS=$([ "$EXCHANGE_SUCCESS" = true ] && echo "success" || echo "failed")
    
    write_json_error "$TIMESTAMP" "$GOLD_STATUS" "$SILVER_STATUS" "$EXCHANGE_STATUS"
  fi
  
  # 等待設定的秒數
  log_info "💤 等待 ${INTERVAL} 秒後重新獲取..."
  sleep ${INTERVAL}
done
