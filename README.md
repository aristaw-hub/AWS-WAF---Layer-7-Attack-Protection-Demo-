# AWS-WAF---Layer-7-Attack-Protection-Demo-
AWS WAF - Layer 7 Attack Protection Demo with Terraform

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
*(Add your diagram image here after uploading it to the `docs/` folder)*

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

| Attack Type              | Expected Behavior                  | Verification Location                  |
|--------------------------|------------------------------------|----------------------------------------|
| SQL Injection            | COUNT or BLOCK                     | WAF Sampled Requests + S3 logs         |
| XSS                      | COUNT or BLOCK                     | WAF Sampled Requests                   |
| Brute Force (/login)     | BLOCK after 100 requests / 5 min   | Brute force test script                |
| Bot Traffic              | BLOCK                              | BotControlProtection rule              |

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
