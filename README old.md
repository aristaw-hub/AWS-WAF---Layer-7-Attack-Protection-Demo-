# AWS-WAF---Layer-7-Attack-Protection-Demo-

AWS WAF - Layer 7 Attack Protection Demo with Terraform

PPT slides https://docs.google.com/presentation/d/13pjRqFctW0EzOL-BICDJOyjmQxLEc8boTEqTEq5QIl8/edit?usp=sharing

A complete, ready-to-deploy Terraform project that demonstrates **AWS Web Application Firewall (WAF) v2** protection against common **Layer 7 (Application Layer) attacks**.

This stack deploys a self-contained environment including:

- VPC with public subnets
- Application Load Balancer (ALB)
- EC2 instance running a simple Nginx demo login page
- AWS WAF Web ACL with managed rules + custom rate-based rule
- Full logging to S3

## Features

- **SQL Injection** protection (`' OR 1=1 --`, UNION SELECT, etc.)
- **Cross-Site Scripting (XSS)** protection (`<script>alert(1)</script>`, etc.)
- **Brute Force / Credential Stuffing** protection (rate limiting **only on `/login`** path)
- **Bot Traffic** protection (scrapers, spam tools, bad User-Agents)
- Custom rule overrides to **COUNT** mode for safe testing
- Automatic WAF logging to S3 bucket
- CloudWatch metrics for every rule

## Architecture

![Architecture Diagram](docs/architecture.png)  
_(Add your diagram image here after uploading it to the `docs/` folder)_

**Traffic Flow**:  
Internet → **AWS WAF** → **Application Load Balancer** → **EC2 (Nginx Demo)**

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform ≥ 1.5
- An AWS account (recommended to use a non-production account)

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/aristaw-hub/AWS-WAF---Layer-7-Attack-Protection-Demo-.git
cd AWS-WAF---Layer-7-Attack-Protection-Demo-
```

### 2. Deploy the stack

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

After deployment, Terraform will output:

- `alb_dns_name` → Use this to test attacks
- `s3_log_bucket` → Where WAF logs are stored

### 3. Run Attack Tests

Make the test script executable and run it:

```bash
chmod +x waf_attack_test.sh
./waf_attack_test.sh <your-alb-dns-name>
```

Example:

```bash
./waf_attack_test.sh waf-demo-alb-1234567890.ap-southeast-1.elb.amazonaws.com
```

## What Gets Deployed

- VPC + 2 Public Subnets
- Internet Gateway + Route Table
- Security Groups (ALB + EC2)
- EC2 instance with Nginx demo login page
- Application Load Balancer (ALB)
- WAF Web ACL with 4 rules:
  1. SQLInjectionProtection (with COUNT overrides for testing)
  2. XSSAndCommonOWASPProtection (with COUNT overrides)
  3. BruteForceRateLimit_LoginOnly (BLOCK mode)
  4. BotControlProtection (BLOCK mode)
- S3 bucket for WAF logs with correct bucket policy

## Testing the Protections

| Attack Type          | Expected Behavior                | Verification Location          |
| -------------------- | -------------------------------- | ------------------------------ |
| SQL Injection        | COUNT or BLOCK                   | WAF Sampled Requests + S3 logs |
| XSS                  | COUNT or BLOCK                   | WAF Sampled Requests           |
| Brute Force (/login) | BLOCK after 100 requests / 5 min | Brute force test script        |
| Bot Traffic          | BLOCK                            | BotControlProtection rule      |

**Tip**: While learning, keep SQLi and XSS rules in **COUNT** mode (already configured in Terraform). Switch to **BLOCK** when ready for production-like behavior.

## Monitoring & Logs

- **Real-time**: AWS Console → WAF & Shield → Web ACLs → `demo-layer7-full-stack` → **Sampled requests**
- **Detailed logs**: S3 bucket (`aws-waf-logs-demo-layer7-...`)
- **Metrics**: CloudWatch → Metrics → `AWS/WAFV2`

## Cleanup

To avoid unnecessary costs, destroy the resources when finished:

```bash
terraform destroy -auto-approve
```

## Project Structure

```
.
├── main.tf                 # Main Terraform configuration
├── variables.tf            # (if any)
├── outputs.tf
├── waf_attack_test.sh      # Improved attack testing script
├── README.md
└── docs/
    └── architecture.png    # (add your diagram here)
```

## Security Notes

- This is a **demo environment** — do not use in production without further hardening.
- The EC2 instance and ALB are intentionally public for easy testing.
- Always review costs (ALB + EC2 + WAF) in the AWS Billing console.

## License

MIT License – feel free to use and modify for learning purposes.

## Author

Created by Arista

---

**Repository**: https://github.com/aristaw-hub/AWS-WAF---Layer-7-Attack-Protection-Demo-.git


Sample terraform apply Output from previous development


aws_lb.demo: Creation complete after 2m49s [id=arn:aws:elasticloadbalancing:ap-southeast-1:255945442255:loadbalancer/app/waf-demo-alb/3b0dd4c8370d9b72]
aws_lb_listener.http: Creating...
aws_wafv2_web_acl_association.demo: Creating...
aws_lb_listener.http: Creation complete after 0s [id=arn:aws:elasticloadbalancing:ap-southeast-1:255945442255:listener/app/waf-demo-alb/3b0dd4c8370d9b72/6610f0ceb934889c]
aws_wafv2_web_acl_association.demo: Creation complete after 2s [id=arn:aws:wafv2:ap-southeast-1:255945442255:regional/webacl/demo-layer7-full-stack/4e49476e-4d0f-4406-90a1-c56769734a03,arn:aws:elasticloadbalancing:ap-southeast-1:255945442255:loadbalancer/app/waf-demo-alb/3b0dd4c8370d9b72]

Apply complete! Resources: 21 added, 0 changed, 0 destroyed.

Outputs:

alb_dns_name = "waf-demo-alb-1800449406.ap-southeast-1.elb.amazonaws.com"
next_steps = <<EOT
1. Run: terraform apply -auto-approve
2. Wait ~2 minutes for ALB + WAF association.
3. Copy the alb_dns_name and start testing with the commands above.
4. View logs: S3 console → your bucket → AWSLogs/<account-id>/
5. Monitor: WAF console → Rules / Sampled requests (real-time blocked attacks).
6. When finished: terraform destroy

EOT
s3_log_bucket = "aws-waf-logs-demo-layer7-8b9yt1pv"
test_commands = <<EOT
# After terraform apply, run these:

# Normal traffic
curl -I http://waf-demo-alb-1800449406.ap-southeast-1.elb.amazonaws.com/

# SQL Injection test
curl -X POST "http://waf-demo-alb-1800449406.ap-southeast-1.elb.amazonaws.com/login" -d "username=admin' OR '1'='1"

# XSS test
curl -X POST "http://waf-demo-alb-1800449406.ap-southeast-1.elb.amazonaws.com/login" -d "comment=<script>alert(1)</script>"

# Brute force test (run in loop)
for i in {1..150}; do curl -X POST "http://waf-demo-alb-1800449406.ap-southeast-1.elb.amazonaws.com/login" -d "user=test&pass=guess$i" --silent --output /dev/null; done

# Bot traffic test
curl -I --user-agent "Mozilla/5.0 (compatible; BadBot/1.0)" http://waf-demo-alb-1800449406.ap-southeast-1.elb.amazonaws.com/

Check blocked requests in:
→ AWS Console → WAF & Shield → Web ACLs → demo-layer7-full-stack → Sampled requests
→ S3 bucket: aws-waf-logs-demo-layer7-8b9yt1pv

EOT
web_acl_id = "4e49476e-4d0f-4406-90a1-c56769734a03"
sus@Vivobook-X409UA:~/AWS-WAF---Layer-7-Attack-Protection-Demo-$
