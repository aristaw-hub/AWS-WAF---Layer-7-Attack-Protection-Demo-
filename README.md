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

