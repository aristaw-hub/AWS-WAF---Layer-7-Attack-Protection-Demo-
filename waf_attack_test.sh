#!/bin/bash
# =====================================================
# AWS WAF Layer 7 Attack Test Script
# Tests: SQLi, XSS, Brute Force (rate limit on /login), Bot Traffic
# Logs results to waf_test_results.log
# =====================================================

ALB_DNS="${1:-YOUR_ALB_DNS_HERE}"   # Pass ALB DNS as argument or edit below
LOGFILE="waf_test_results.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

if [ -z "$ALB_DNS" ] || [ "$ALB_DNS" = "YOUR_ALB_DNS_HERE" ]; then
  echo "Usage: $0 <your-alb-dns-name>"
  echo "Example: $0 waf-demo-alb-1234567890.ap-southeast-1.elb.amazonaws.com"
  exit 1
fi

echo "==================================================" | tee -a $LOGFILE
echo "WAF Attack Test Started at: $TIMESTAMP" | tee -a $LOGFILE
echo "Target ALB: http://$ALB_DNS" | tee -a $LOGFILE
echo "==================================================" | tee -a $LOGFILE

# Function to run test and log
run_test() {
  local name=$1
  local cmd=$2
  echo -e "\n[$name]" | tee -a $LOGFILE
  echo "Command: $cmd" | tee -a $LOGFILE
  eval "$cmd" | tee -a $LOGFILE
  echo "----------------------------------------" | tee -a $LOGFILE
}

echo "1. SQL Injection Test (' OR 1=1 --)" | tee -a $LOGFILE
run_test "SQLi Basic" "curl -X POST \"http://$ALB_DNS/login\" -d \"username=admin' OR '1'='1\" -d \"password=anything\" -v -s"
run_test "SQLi UNION" "curl -X POST \"http://$ALB_DNS/login\" -d \"username=admin' UNION SELECT 1,2--\" -v -s"

echo "2. Cross-Site Scripting (XSS) Test" | tee -a $LOGFILE
run_test "XSS Script Tag" "curl -X POST \"http://$ALB_DNS/login\" -d \"comment=<script>alert(1)</script>\" -v -s"
run_test "XSS onerror" "curl -X POST \"http://$ALB_DNS/login\" -d \"input=<img src=x onerror=alert(1)>\" -v -s"

echo "3. Brute Force / Credential Stuffing Test (on /login only)" | tee -a $LOGFILE
echo "Sending 150 rapid login attempts..." | tee -a $LOGFILE
for i in {1..150}; do
  curl -X POST "http://$ALB_DNS/login" \
    -d "username=testuser&password=guess$i" \
    --silent --output /dev/null --write-out "%{http_code} "
done | tee -a $LOGFILE
echo -e "\nBrute force test completed. Check if you start getting 403 after ~100 requests." | tee -a $LOGFILE

echo "4. Bot Traffic Test" | tee -a $LOGFILE
run_test "Bad Bot User-Agent" "curl -I --user-agent \"BadBot/1.0; +http://evil.example.com\" \"http://$ALB_DNS/\" -v -s"
run_test "Scrapy Bot" "curl -I --user-agent \"Mozilla/5.0 (compatible; Scrapy/2.0)\" \"http://$ALB_DNS/\" -v -s"
run_test "Python Urllib Bot" "curl -I --user-agent \"Python-urllib/3.9\" \"http://$ALB_DNS/\" -v -s"

echo -e "\nTest completed at $(date '+%Y-%m-%d %H:%M:%S')" | tee -a $LOGFILE
echo "Results saved to: $LOGFILE" | tee -a $LOGFILE
echo "Next: Check AWS WAF Console → Sampled requests and your S3 log bucket"