# AWS WAF – Layer 7 Attack Protection Demo

![Terraform](https://img.shields.io/badge/Terraform-1.5+-623CE4?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-WAF-orange)
![License](https://img.shields.io/badge/License-MIT-green)

A complete end-to-end Terraform project demonstrating how **AWS WAF v2** protects web applications against common **Layer 7 (Application Layer)** attacks.

The project provisions a realistic AWS environment consisting of an Application Load Balancer, EC2 web server, AWS WAF Web ACL, logging, monitoring, and attack simulation scripts.

This repository is designed for:

- AWS learners
- Security engineers
- Cloud engineers
- DevOps engineers
- Students preparing for AWS Security Specialty
- Anyone wanting hands-on experience with AWS WAF

---

## Presentation

Project presentation slides:

https://docs.google.com/presentation/d/13pjRqFctW0EzOL-BICDJOyjmQxLEc8boTEqTEq5QIl8/edit?usp=sharing

---

## Demo Overview

This project demonstrates AWS WAF protection against:

- ✅ SQL Injection (SQLi)
- ✅ Cross-Site Scripting (XSS)
- ✅ Common OWASP web application attacks
- ✅ Brute Force login attempts (rate limiting on `/login`)
- ✅ Credential Stuffing mitigation through request rate limiting
- ✅ Bot Traffic using AWS Bot Control
- ✅ Basic Layer 7 HTTP flood mitigation using rate-based rules and bot detection

These protections are implemented using four AWS WAF rules:

1. **SQLInjectionProtection**
2. **XSSAndCommonOWASPProtection**
3. **BruteForceRateLimit_LoginOnly**
4. **BotControlProtection**

All infrastructure is deployed automatically using Terraform.

---

# Architecture

## Architecture

```text
                                     Internet
                                         │
                                         ▼
                              +--------------------+
                              |   AWS WAF v2       |
                              |--------------------|
                              | • SQL Injection    |
                              | • XSS Protection   |
                              | • Bot Control      |
                              | • Rate Limiting    |
                              +--------------------+
                                         │
                                         ▼
                     +--------------------------------------+
                     | Application Load Balancer (ALB)      |
                     +--------------------------------------+
                                         │
                                         ▼
                     +--------------------------------------+
                     | Amazon EC2 (Amazon Linux 2023)       |
                     |--------------------------------------|
                     | Nginx Demo Login Application         |
                     +--------------------------------------+
                                         │
                    ┌────────────────────┴────────────────────┐
                    ▼                                         ▼
        +---------------------------+             +---------------------------+
        | Amazon CloudWatch         |             | Amazon S3                |
        |---------------------------|             |---------------------------|
        | • WAF Metrics             |             | • WAF Logs               |
        | • Rule Statistics         |             | • Full Request Logs      |
        +---------------------------+             +---------------------------+

Terraform provisions and configures all AWS resources automatically.
```

### Traffic Flow

```
Internet
   │
   ▼
AWS WAF
   │
   ▼
Application Load Balancer
   │
   ▼
EC2 Instance (Nginx Demo Login Page)
```

### Components

| Component | Purpose |
|----------|---------|
| **AWS WAF v2** | Protects the application from Layer 7 attacks using AWS Managed Rules and custom rules. |
| **Application Load Balancer** | Receives HTTP traffic and forwards requests to the EC2 instance. |
| **Amazon EC2** | Hosts a simple Nginx demo login page used for attack testing. |
| **Amazon S3** | Stores detailed AWS WAF logs for forensic analysis. |
| **Amazon CloudWatch** | Provides metrics and monitoring for WAF rules and requests. |
| **Terraform** | Deploys and manages the entire infrastructure as code. |


# Infrastructure

Terraform deploys:

- VPC
- 2 Public Subnets
- Internet Gateway
- Route Tables
- Security Groups
- EC2 Instance
- Nginx Demo Login Page
- Application Load Balancer
- AWS WAF Web ACL
- WAF Logging
- Amazon S3 Bucket
- CloudWatch Metrics

Total Resources

Approximately **21 AWS resources**

---

# WAF Protection Rules

## 1. SQL Injection Protection

AWS Managed Rule Group

Examples

```
' OR 1=1 --

UNION SELECT

admin'--

```

Default Mode

COUNT

Purpose

Safely verify detection before switching to BLOCK.

---

## 2. Cross Site Scripting (XSS)

Examples

```html
<script>alert(1)</script>

<img src=x onerror=alert(1)>
```

Mode

COUNT

---

## 3. Brute Force Protection

Custom Rate-Based Rule

Only protects

```
/login
```

Threshold

100 requests

within

5 minutes

Action

BLOCK

---

## 4. Bot Control

Protects against

- Scrapers
- Bad Bots
- Known Automation
- Suspicious User Agents

Action

BLOCK

---

# Logging

Every request can be inspected using

- AWS WAF Sampled Requests
- CloudWatch Metrics
- S3 WAF Logs

---

# Prerequisites

- AWS CLI
- Terraform 1.5+
- AWS Account
- IAM User with Administrator permissions

Configure AWS credentials

```
aws configure
```

---

# Deployment

Clone repository

```bash
git clone https://github.com/aristaw-hub/AWS-WAF---Layer-7-Attack-Protection-Demo-.git

cd AWS-WAF---Layer-7-Attack-Protection-Demo-
```

Initialize Terraform

```bash
terraform init
```

Review the plan

```bash
terraform plan
```

Deploy

```bash
terraform apply -auto-approve
```

Deployment takes approximately

5–8 minutes

---

# Outputs

Terraform returns

```
alb_dns_name

s3_log_bucket

web_acl_id

test_commands

next_steps
```

Example

```
alb_dns_name

waf-demo-alb-xxxxxxxx.ap-southeast-1.elb.amazonaws.com
```

---

# Attack Testing

Normal Request

```bash
curl http://<ALB>
```

SQL Injection

```bash
curl -X POST http://<ALB>/login \
-d "username=admin' OR '1'='1"
```

XSS

```bash
curl -X POST http://<ALB>/login \
-d "comment=<script>alert(1)</script>"
```

Bot Test

```bash
curl -I \
--user-agent "BadBot/1.0" \
http://<ALB>
```

Brute Force

```bash
for i in {1..150}; do

curl -X POST http://<ALB>/login \
-d "user=test&pass=test$i"

done
```

Or simply run

```bash
chmod +x waf_attack_test.sh

./waf_attack_test.sh <ALB DNS>
```

---

# Monitoring

AWS Console

WAF & Shield

↓

Web ACL

↓

demo-layer7-full-stack

↓

Sampled Requests

CloudWatch

```
AWS/WAFV2
```

S3

```
AWSLogs/
```

---

# Expected Results

| Attack | Expected Result |
|----------|----------------|
| SQL Injection | COUNT / BLOCK |
| XSS | COUNT / BLOCK |
| Brute Force | BLOCK |
| Bot Traffic | BLOCK |
| Normal Request | ALLOW |

---

# Project Structure

```
.
├── docs
│   └── architecture.png
│
├── main.tf
├── outputs.tf
├── variables.tf
├── providers.tf
├── versions.tf
│
├── waf_attack_test.sh
│
├── README.md
```

---

# Cleanup

Destroy all resources

```bash
terraform destroy -auto-approve
```

---

# Learning Objectives

After completing this project you will understand:

- AWS WAF Architecture
- Web ACLs
- Managed Rule Groups
- Rate-Based Rules
- ALB Integration
- WAF Logging
- CloudWatch Metrics
- Terraform Infrastructure as Code
- Layer 7 Attack Mitigation

---

# Security Notice

This repository is intended for learning purposes only.

The EC2 instance and ALB are intentionally public to simplify testing.

Do not deploy directly into a production environment without additional hardening.

---

# License

MIT License

---

# Author

**Arista**

GitHub

[https://github.com/aristaw-hub](https://github.com/aristaw-hub/)

Github repository readme
[https://github.com/aristaw-hub/AWS-WAF---Layer-7-Attack-Protection-Demo-/edit/main/README.md](https://github.com/aristaw-hub/AWS-WAF---Layer-7-Attack-Protection-Demo-/edit/main/README.md) 

Happy Learning!
