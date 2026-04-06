# =====================================================
# COMPLETE READY-TO-DEPLOY AWS WAF v2 + ALB + EC2 DEMO STACK
# Demonstrates Layer 7 protections:
#   • SQL Injection (' OR 1=1 --)
#   • XSS (<script>alert(1)</script>)
#   • Brute Force (rate-limited login attempts on /login)
#   • Bot Traffic (scraping, spam, bad User-Agents)
#
# Features included:
#   • Full self-contained VPC + public ALB + EC2 (Nginx demo login page)
#   • WAF Web ACL attached directly to the ALB
#   • WAF Logging to S3 (bucket auto-created with correct policy)
#   • Custom rate limiting PER URI (/login only)
#   • Custom exclusions example (one SQLi rule set to COUNT for testing)
#   • Region: ap-southeast-1 (Singapore)
#
# After `terraform apply` you get:
#   • A live ALB DNS name you can attack immediately with curl
#   • Logs in S3 for every blocked request
#   • CloudWatch metrics for every rule
#
# Cost: ~$0.10–$0.30/hour (t3.micro + ALB). Destroy when done.
# =====================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

# -----------------------------------------------------
# 1. NETWORKING (VPC + Subnets + IGW)
# -----------------------------------------------------
resource "aws_vpc" "demo" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "waf-demo-vpc" }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "waf-demo-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags = { Name = "waf-demo-public-2" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.demo.id
  tags   = { Name = "waf-demo-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "waf-demo-public-rt" }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------
# 2. SECURITY GROUPS
# -----------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "waf-demo-alb-sg"
  description = "Allow HTTP to ALB"
  vpc_id      = aws_vpc.demo.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "waf-demo-alb-sg" }
}

resource "aws_security_group" "ec2" {
  name        = "waf-demo-ec2-sg"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.demo.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "waf-demo-ec2-sg" }
}

# -----------------------------------------------------
# 3. EC2 + NGINX DEMO APPLICATION
# -----------------------------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "demo_web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  user_data              = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx
    systemctl enable nginx
    systemctl start nginx

    cat > /usr/share/nginx/html/index.html << 'HTML'
    <!DOCTYPE html>
    <html><head><title>Demo Login - Layer 7 WAF Test</title></head>
    <body>
      <h1>Demo Login Page</h1>
      <form action="/login" method="post">
        Username: <input type="text" name="username"><br>
        Password: <input type="password" name="password"><br>
        <input type="submit" value="Login">
      </form>
      <p>Test SQLi, XSS, brute force, and bots here!</p>
    </body></html>
    HTML
  EOF

  tags = { Name = "waf-demo-web-server" }
}

# -----------------------------------------------------
# 4. ALB + TARGET GROUP
# -----------------------------------------------------
resource "aws_lb_target_group" "demo" {
  name     = "waf-demo-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.demo.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
}

resource "aws_lb" "demo" {
  name               = "waf-demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = { Name = "waf-demo-alb" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.demo.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo.arn
  }
}

resource "aws_lb_target_group_attachment" "demo" {
  target_group_arn = aws_lb_target_group.demo.arn
  target_id        = aws_instance.demo_web.id
  port             = 80
}

# -----------------------------------------------------
# 5. WAF LOGGING BUCKET + POLICY
# -----------------------------------------------------
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "waf_logs" {
  bucket = "aws-waf-logs-demo-layer7-${random_string.bucket_suffix.result}"

  tags = { Name = "waf-demo-logs" }
}

resource "aws_s3_bucket_ownership_controls" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "waf_logs_policy" {
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "${aws_s3_bucket.waf_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id
  policy = data.aws_iam_policy_document.waf_logs_policy.json
}

# -----------------------------------------------------
# 6. WAF WEB ACL (with custom rate-limit per URI + exclusions)
# -----------------------------------------------------
resource "aws_wafv2_web_acl" "layer7_demo" {
  name        = "demo-layer7-full-stack"
  description = "Full Layer 7 protection demo (SQLi, XSS, Brute-Force per /login, Bots)"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # RULE 1: SQLi with custom exclusion (one rule set to COUNT for demo)
  rule {
    name     = "SQLInjectionProtection"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"

        # Custom exclusion example: set one specific SQLi rule to COUNT instead of BLOCK
        rule_action_override {
          name = "SQLi_BODY"   # Example rule name inside the group
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLInjectionProtection"
      sampled_requests_enabled   = true
    }
  }

  # RULE 2: XSS + OWASP Common
  rule {
    name     = "XSSAndCommonOWASPProtection"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "XSSAndCommonOWASPProtection"
      sampled_requests_enabled   = true
    }
  }

  # RULE 3: Brute Force – CUSTOM RATE LIMIT PER URI (/login only)
  rule {
    name     = "BruteForceRateLimit_LoginOnly"
    priority = 30

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100   # 100 requests in 5 minutes
        aggregate_key_type = "IP"

        # CUSTOM: Rate limit ONLY on /login path
        scope_down_statement {
          byte_match_statement {
            field_to_match {
              uri_path {}
            }
            positional_constraint = "CONTAINS"
            search_string         = "/login"
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BruteForceRateLimit_LoginOnly"
      sampled_requests_enabled   = true
    }
  }

  # RULE 4: Bot Control
  rule {
    name     = "BotControlProtection"
    priority = 40

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BotControlProtection"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "DemoLayer7FullStack"
    sampled_requests_enabled   = true
  }

  tags = { Name = "Layer7-Demo-Full-Stack" }
}

# -----------------------------------------------------
# 7. WAF LOGGING CONFIGURATION (S3)
# -----------------------------------------------------
resource "aws_wafv2_web_acl_logging_configuration" "demo" {
  resource_arn            = aws_wafv2_web_acl.layer7_demo.arn
  log_destination_configs = [aws_s3_bucket.waf_logs.arn]

  # Optional: redact sensitive fields (passwords, etc.)
  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

# -----------------------------------------------------
# 8. WAF ASSOCIATION WITH ALB
# -----------------------------------------------------
resource "aws_wafv2_web_acl_association" "demo" {
  resource_arn = aws_lb.demo.arn
  web_acl_arn  = aws_wafv2_web_acl.layer7_demo.arn
}

# -----------------------------------------------------
# OUTPUTS – COPY THESE AFTER APPLY
# -----------------------------------------------------
output "alb_dns_name" {
  value       = aws_lb.demo.dns_name
  description = "✅ Test your attacks here! e.g. curl http://<this-value>"
}

output "s3_log_bucket" {
  value       = aws_s3_bucket.waf_logs.bucket
  description = "WAF logs stored here (view in S3 console)"
}

output "web_acl_id" {
  value = aws_wafv2_web_acl.layer7_demo.id
}

output "test_commands" {
  value = <<EOT
# After terraform apply, run these:

# Normal traffic
curl -I http://${aws_lb.demo.dns_name}/

# SQL Injection test
curl -X POST "http://${aws_lb.demo.dns_name}/login" -d "username=admin' OR '1'='1"

# XSS test
curl -X POST "http://${aws_lb.demo.dns_name}/login" -d "comment=<script>alert(1)</script>"

# Brute force test (run in loop)
for i in {1..150}; do curl -X POST "http://${aws_lb.demo.dns_name}/login" -d "user=test&pass=guess$i" --silent --output /dev/null; done

# Bot traffic test
curl -I --user-agent "Mozilla/5.0 (compatible; BadBot/1.0)" http://${aws_lb.demo.dns_name}/

Check blocked requests in:
→ AWS Console → WAF & Shield → Web ACLs → demo-layer7-full-stack → Sampled requests
→ S3 bucket: ${aws_s3_bucket.waf_logs.bucket}
EOT
}

output "next_steps" {
  value = <<EOT
1. Run: terraform apply -auto-approve
2. Wait ~2 minutes for ALB + WAF association.
3. Copy the alb_dns_name and start testing with the commands above.
4. View logs: S3 console → your bucket → AWSLogs/<account-id>/
5. Monitor: WAF console → Rules / Sampled requests (real-time blocked attacks).
6. When finished: terraform destroy
EOT
}
