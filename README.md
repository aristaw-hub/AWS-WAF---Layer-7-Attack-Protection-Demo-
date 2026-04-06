# AWS-WAF---Layer-7-Attack-Protection-Demo-
AWS WAF - Layer 7 Attack Protection Demo with Terraform



Here's a **complete, practical Test Plan** to verify that your AWS WAF (from the Terraform ALB + EC2 demo stack) correctly detects and **blocks** the four Layer 7 attacks.

### Prerequisites (Before Testing)
1. Run `terraform apply` and wait until the ALB is healthy (2–5 minutes).
2. Copy the **ALB DNS name** from the Terraform output (e.g., `waf-demo-alb-1234567890.ap-southeast-1.elb.amazonaws.com`).
3. Confirm WAF is associated with the ALB.
4. WAF logging to S3 is enabled (as in the Terraform code).
5. Open the AWS Console:
   - **WAF & Shield → Web ACLs → demo-layer7-full-stack → Sampled requests** tab
   - CloudWatch metrics for your rule names
   - S3 bucket for detailed logs

**Recommendation**: Initially set rules to **Count** mode (instead of Block) to observe matches without disrupting traffic. Then switch back to **Block** for final validation.

---

### Test Plan Overview

| Attack Type              | Rule Triggered                          | Expected HTTP Response | Verification Methods                  | Success Criteria                          |
|--------------------------|-----------------------------------------|------------------------|---------------------------------------|-------------------------------------------|
| SQL Injection            | SQLInjectionProtection                  | 403 Forbidden          | Sampled requests + S3 logs            | Request blocked, rule name appears        |
| Cross-Site Scripting (XSS) | XSSAndCommonOWASPProtection           | 403 Forbidden          | Sampled requests + S3 logs            | Request blocked, rule name appears        |
| Brute Force              | BruteForceRateLimit_LoginOnly           | 403 Forbidden          | Sampled requests + rate limit metric  | IP blocked after exceeding 100 req/5min   |
| Bot Traffic              | BotControlProtection                    | 403 Forbidden          | Sampled requests + Bot labels         | Request blocked with bot-related label    |

---

### 1. SQL Injection Test (`' OR 1=1 --`)

**Objective**: Verify WAF blocks classic SQLi payloads.

**Test Commands** (run from your terminal):

```bash
# Basic SQLi in POST body (most common)
curl -X POST "http://YOUR_ALB_DNS_NAME/login" \
  -d "username=admin' OR '1'='1" \
  -d "password=anything" -v

# More variations (test multiple)
curl -X POST "http://YOUR_ALB_DNS_NAME/login" \
  -d "username=admin' UNION SELECT 1,2--" -v

curl -X GET "http://YOUR_ALB_DNS_NAME/login?user=1' OR '1'='1" -v
```

**Expected Result**:
- HTTP/1.1 **403 Forbidden**
- In **WAF Console → Sampled requests**: Look for the request with **Rule**: `SQLInjectionProtection` (or sub-rule like `SQLi_BODY`, `SQLi_QUERY_STRING`)

**Verification**:
- Check S3 logs for the JSON record with `terminatingRule` or `nonTerminatingMatchingRules` showing the SQLi rule.
- CloudWatch metric `SQLInjectionProtection` should show Blocked/Counted requests.

---

### 2. Cross-Site Scripting (XSS) Test (`<script>alert(1)</script>`)

**Objective**: Verify WAF blocks XSS payloads.

**Test Commands**:

```bash
# Basic XSS in POST body
curl -X POST "http://YOUR_ALB_DNS_NAME/login" \
  -d "comment=<script>alert(1)</script>" -v

# Encoded / polyglot variations
curl -X POST "http://YOUR_ALB_DNS_NAME/login" \
  -d "input=<img src=x onerror=alert(1)>" -v

curl -X POST "http://YOUR_ALB_DNS_NAME/login" \
  -d "payload=javascript:alert(1)" -v
```

**Expected Result**:
- HTTP **403 Forbidden**
- In Sampled requests: Rule `XSSAndCommonOWASPProtection` (often sub-rule `XSS_BODY` or `XSS_QUERY_STRING`)

**Tip**: If you want to test bypass techniques (for advanced tuning), try base64-encoded payloads, but the managed rule set catches most common ones.

---

### 3. Brute Force / Credential Stuffing Test

**Objective**: Verify the **rate-based rule** triggers only on `/login` after 100+ requests in 5 minutes.

**Test Script** (run this loop):

```bash
# Brute force simulation on /login (should trigger after ~100 requests)
for i in {1..150}; do
  curl -X POST "http://YOUR_ALB_DNS_NAME/login" \
    -d "username=testuser&password=guess$i" \
    --silent --output /dev/null --write-out "%{http_code}\n"
  sleep 0.2   # Optional: slow it down a bit
done
```

**Alternative one-liner**:
```bash
for i in {1..150}; do curl -X POST "http://YOUR_ALB_DNS_NAME/login" -d "user=test&pass=$i" --silent --output /dev/null; done
```

**Expected Result**:
- First ~100 requests → **200 OK** (or 403 from app if login fails)
- After threshold → **403 Forbidden** from WAF
- Only `/login` path is rate-limited (test `/` or other paths — they should not be affected)

**Verification**:
- WAF Sampled requests shows rule `BruteForceRateLimit_LoginOnly`
- CloudWatch metric for this rule spikes

---

### 4. Bot Traffic Test (Scraping, Spam, Bad User-Agents)

**Objective**: Verify Bot Control rule blocks malicious/scraping bots.

**Test Commands**:

```bash
# Bad User-Agent (common scraper/spam)
curl -I --user-agent "BadBot/1.0; +http://evil.example.com" "http://YOUR_ALB_DNS_NAME/"

# Common scraper User-Agents
curl -I --user-agent "Mozilla/5.0 (compatible; Scrapy/2.0; +http://scrapy.org)" "http://YOUR_ALB_DNS_NAME/"

# High-volume scraping simulation (run multiple times quickly)
for i in {1..30}; do
  curl -I --user-agent "Python-urllib/3.9" "http://YOUR_ALB_DNS_NAME/" --silent --output /dev/null
done
```

**Expected Result**:
- **403 Forbidden** with Bot Control rule triggered
- In logs: You will see labels like `awswaf:managed:aws:bot-control:signal:non_browser_user_agent` or similar bot labels

**Verification**:
- Sampled requests shows `BotControlProtection`
- Look for **Bot-related labels** in the detailed request JSON in S3 logs

---

### Post-Test Verification Steps (For All Attacks)

1. **AWS WAF Console**:
   - Go to your Web ACL → **Sampled requests** tab
   - Filter by time or rule name
   - Click on blocked requests to see full details (headers, body snippet, terminating rule)

2. **S3 Logs**:
   - Navigate to your log bucket → `AWSLogs/<account-id>/WAFLogs/...`
   - Search for the ALB DNS or timestamp of your test
   - Look for `"action": "BLOCK"` and the rule name

3. **CloudWatch Metrics**:
   - Check metrics for each rule name (Blocked, Counted, Allowed)

4. **ALB Access Logs** (optional):
   - If enabled, look for `waf` in the `actions_executed` field and 403 status.

---

### Best Practices & Tips During Testing
- Start with **Count** mode for new rules to avoid accidental blocking of legitimate traffic.
- Use tools like **OWASP ZAP**, **sqlmap**, or **Burp Suite** for more comprehensive testing.
- Record timestamps of your tests to easily correlate with logs.
- Test from different IPs if possible (rate-based rules are IP-based).
- After successful blocking, you can switch rules back to **Block** mode.
- Document false positives (if any) and use rule action overrides or exclusions.



Here's everything you requested for your **AWS WAF v2 + ALB + EC2 demo stack**.
https://grok.com/share/c2hhcmQtMi1jb3B5_42022cbe-03b7-4007-83f0-bb504bbaec09
### 1. Ready-to-Run Bash Test Script

Save this as `waf_attack_test.sh`, make it executable (`chmod +x waf_attack_test.sh`), and run it.

```bash
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
```

**How to run:**
```bash
./waf_attack_test.sh waf-demo-alb-1234567890.ap-southeast-1.elb.amazonaws.com
```

### 2. Commands to Switch Rules to COUNT Mode (via AWS CLI)

Use these commands to safely test (Count instead of Block). Replace placeholders with your actual values.

#### First, get your Web ACL details
```bash
aws wafv2 list-web-acls --scope REGIONAL
```

#### Update the entire Web ACL to override specific rules to COUNT

The easiest way is to download the current Web ACL JSON, modify the `ruleActionOverrides`, then update it.

**Step-by-step:**

1. Get current Web ACL JSON:
```bash
aws wafv2 get-web-acl \
  --name demo-layer7-full-stack \
  --scope REGIONAL \
  --id YOUR_WEB_ACL_ID_HERE > webacl.json
```

2. Edit `webacl.json` and add/update `ruleActionOverrides` under the managed rule groups (example below for SQLi and Common rules):

```json
"ruleActionOverrides": [
  {
    "name": "SQLi_BODY",           // or the exact rule name inside the group
    "actionToUse": { "count": {} }
  },
  {
    "name": "XSS_BODY",
    "actionToUse": { "count": {} }
  }
]
```

For the whole rule group to COUNT (simpler for testing):
```bash
# Override entire SQLi rule group to COUNT
aws wafv2 update-web-acl \
  --name demo-layer7-full-stack \
  --scope REGIONAL \
  --id YOUR_WEB_ACL_ID_HERE \
  --lock-token YOUR_LOCK_TOKEN_HERE \
  --default-action Allow={} \
  --rules '[
    {
      "name": "SQLInjectionProtection",
      "priority": 10,
      "overrideAction": {"none": {}},
      "statement": {
        "managedRuleGroupStatement": {
          "vendorName": "AWS",
          "name": "AWSManagedRulesSQLiRuleSet",
          "ruleActionOverrides": [
            {"name": "SQLi_BODY", "actionToUse": {"count": {}}}
          ]
        }
      },
      "visibilityConfig": {"sampledRequestsEnabled": true, "cloudWatchMetricsEnabled": true, "metricName": "SQLInjectionProtection"}
    }
    // ... include other rules similarly
  ]'
```

**Tip**: For quick testing, use the AWS Console first (Web ACL → Rules → Edit rule group → Override rule actions to Count). Then use CLI for automation.

### 3. How to Interpret Specific Fields in WAF Logs

WAF logs are written as JSON to your S3 bucket (`AWSLogs/<account-id>/WAFLogs/...`).

**Key Fields to Look For:**

- **`action`**: `"BLOCK"`, `"ALLOW"`, `"COUNT"` — what WAF finally did with the request.
- **`terminatingRuleId`**: Name/ID of the rule that stopped processing (e.g., `SQLInjectionProtection`, `BruteForceRateLimit_LoginOnly`).
- **`terminatingRuleType`**: `REGULAR`, `RATE_BASED`, `MANAGED_RULE_GROUP`, etc.
- **`terminatingRule`** (object): Contains `action` and `ruleId` of the terminating rule.
- **`ruleGroupList`**: Array showing which rule groups matched.
  - `ruleGroupId`: e.g., `AWS#AWSManagedRulesSQLiRuleSet`
  - `terminatingRule`: The specific rule inside the group that triggered (e.g., `SQLi_BODY` or `XSS_QUERY_STRING`)
- **`nonTerminatingMatchingRules`**: Rules that matched but did not terminate (usually because they are in COUNT mode).
- **`httpRequest`**: Full details — `clientIp`, `uri`, `method`, `headers`, `body` (if inspected).
- **`labels`**: Bot Control adds labels like `awswaf:managed:aws:bot-control:signal:non_browser_user_agent`.
- **`timestamp`**: Unix timestamp (convert with `date -d @timestamp`).

**Example Blocked SQLi Log Snippet:**
```json
{
  "action": "BLOCK",
  "terminatingRuleId": "SQLInjectionProtection",
  "terminatingRuleType": "MANAGED_RULE_GROUP",
  "httpRequest": {
    "clientIp": "203.0.113.1",
    "uri": "/login",
    "headers": [ ... ]
  },
  "ruleGroupList": [
    {
      "ruleGroupId": "AWS#AWSManagedRulesSQLiRuleSet",
      "terminatingRule": { "ruleId": "SQLi_BODY", "action": "BLOCK" }
    }
  ]
}
```

**Brute Force Example:**
- `terminatingRuleType`: `"RATE_BASED"`
- `terminatingRuleId`: `"BruteForceRateLimit_LoginOnly"`

**Bot Example:**
- Look for bot labels in the `labels` array or `ruleGroupList` with `AWS#AWSManagedRulesBotControlRuleSet`.

**Where to view easily**:
- AWS Console → WAF & Shield → Your Web ACL → **Sampled requests** (best for quick checks)
- S3 bucket → download JSON logs and open in a JSON viewer
- Use Amazon Athena to query logs for deeper analysis

Would you like me to:
- Provide a ready `webacl.json` template with COUNT overrides?
- Add a script to automatically switch between Block and Count mode?
- Show how to query WAF logs with Athena?

Let me know how else I can help you validate the demo!