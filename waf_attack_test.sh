#!/bin/bash
# =====================================================
# Improved AWS WAF Layer 7 Attack Test Script
# Better payloads to reliably trigger SQLi, XSS, Brute Force, and Bot rules
# =====================================================

ALB_DNS="${1:-YOUR_ALB_DNS_HERE}"
LOGFILE="waf_test_results_improved.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

if [ -z "$ALB_DNS" ] || [ "$ALB_DNS" = "YOUR_ALB_DNS_HERE" ]; then
  echo "Usage: $0 <your-alb-dns-name>"
  exit 1
fi

echo "==================================================" | tee -a $LOGFILE
echo "Improved WAF Attack Test Started at: $TIMESTAMP" | tee -a $LOGFILE
echo "Target: http://$ALB_DNS" | tee -a $LOGFILE
echo "==================================================" | tee -a $LOGFILE

run_test() {
  local name=$1
  local cmd=$2
  echo -e "\n=== $name ===" | tee -a $LOGFILE
  echo "Command: $cmd" | tee -a $LOGFILE
  eval "$cmd" 2>&1 | tee -a $LOGFILE
  echo "----------------------------------------" | tee -a $LOGFILE
}

# 1. SQL Injection - Stronger payloads (target BODY and QUERY)
echo "1. SQL Injection Tests" | tee -a $LOGFILE
run_test "SQLi - Classic Boolean" 'curl -X POST "http://'$ALB_DNS'/login" -d "username=admin'\'' OR '\''1'\''='\''1" -d "password=anything" -v -s'
run_test "SQLi - UNION" 'curl -X POST "http://'$ALB_DNS'/login" -d "username=admin'\'' UNION SELECT NULL,version()--" -v -s'
run_test "SQLi - Query String" 'curl -X GET "http://'$ALB_DNS'/login?user=1'\'' OR '\''1'\''='\''1&pass=1" -v -s'

# 2. XSS - Stronger and varied payloads
echo "2. Cross-Site Scripting (XSS) Tests" | tee -a $LOGFILE
run_test "XSS - Script Tag" 'curl -X POST "http://'$ALB_DNS'/login" -d "comment=<script>alert(1)</script>" -v -s'
run_test "XSS - onerror" 'curl -X POST "http://'$ALB_DNS'/login" -d "input=<img src=x onerror=alert(document.cookie)>" -v -s'
run_test "XSS - JavaScript URI" 'curl -X POST "http://'$ALB_DNS'/login" -d "payload=javascript:alert(1)" -v -s'
run_test "XSS - SVG" 'curl -X POST "http://'$ALB_DNS'/login" -d "comment=<svg/onload=alert(1)>" -v -s'

# 3. Brute Force (unchanged - this already works well)
echo "3. Brute Force / Credential Stuffing (150 attempts on /login)" | tee -a $LOGFILE
echo "Sending 150 requests..." | tee -a $LOGFILE
for i in {1..150}; do
  curl -X POST "http://$ALB_DNS/login" \
    -d "username=testuser&password=guess$i" \
    --silent --output /dev/null --write-out "%{http_code} "
done | tee -a $LOGFILE
echo -e "\nBrute force completed - expect 403 after ~100 requests" | tee -a $LOGFILE

# 4. Bot Traffic - Stronger signals
echo "4. Bot Traffic Tests" | tee -a $LOGFILE
run_test "Bot - Scanner-like UA" 'curl -I --user-agent "sqlmap/1.8.3" "http://'$ALB_DNS'/" -v -s'
run_test "Bot - Nmap Scanner" 'curl -I --user-agent "Nmap Scripting Engine" "http://'$ALB_DNS'/" -v -s'
run_test "Bot - Python Requests (common scraper)" 'curl -I --user-agent "python-requests/2.32" "http://'$ALB_DNS'/" -v -s'
run_test "Bot - No User-Agent" 'curl -I --user-agent "" "http://'$ALB_DNS'/" -v -s'
run_test "Bot - Bad Bot Signature" 'curl -I --user-agent "Mozilla/5.0 (compatible; BadBot/2.0; +http://evil.com)" "http://'$ALB_DNS'/" -v -s'

echo -e "\n✅ Improved test completed at $(date '+%Y-%m-%d %H:%M:%S')" | tee -a $LOGFILE
echo "Results saved to: $LOGFILE" | tee -a $LOGFILE
echo "Now check:"
echo "   • WAF Console → Sampled requests (filter by rule name)"
echo "   • S3 log bucket for detailed JSON logs"