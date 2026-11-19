locals {
    name = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Certificat ACM (validation DNS chez le registrar, hors Route 53)
# ---------------------------------------------------------------------------
resource "aws_acm_certificate" "this" {
    domain_name       = var.domain_name
    validation_method = "DNS"

    tags = {
    Name = "${local.name}-cert"
    }

    lifecycle {
    create_before_destroy = true
    }
}

# Attend que le CNAME de validation soit cree chez le registrar.
# Ce CNAME est identique pour un meme domaine dans un meme compte AWS :
# une fois cree, il valide aussi les certificats recrees apres un destroy.
resource "aws_acm_certificate_validation" "this" {
    certificate_arn = aws_acm_certificate.this.arn
    timeouts {
    create = var.certificate_validation_timeout
    }
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
    name        = "${local.name}-alb-sg"
    description = "ALB ${local.name} - HTTP et HTTPS depuis Internet"
    vpc_id      = var.vpc_id

    tags = {
    Name = "${local.name}-alb-sg"
    }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
    security_group_id = aws_security_group.alb.id
    description       = "HTTPS depuis Internet"
    cidr_ipv4         = "0.0.0.0/0"
    ip_protocol       = "tcp"
    from_port         = 443
    to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
    #checkov:skip=CKV_AWS_260:Port 80 ouvert uniquement pour la redirection 301 vers HTTPS, aucun contenu servi en clair
    security_group_id = aws_security_group.alb.id
    description       = "HTTP depuis Internet (redirection vers HTTPS)"
    cidr_ipv4         = "0.0.0.0/0"
    ip_protocol       = "tcp"
    from_port         = 80
    to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_web" {
    security_group_id            = aws_security_group.alb.id
    description                  = "Vers les instances web en HTTP"
    referenced_security_group_id = aws_security_group.web.id
    ip_protocol                  = "tcp"
    from_port                    = 80
    to_port                      = 80
}

resource "aws_security_group" "web" {
    name        = "${local.name}-web-sg"
    description = "Instances web ${local.name} - HTTP depuis l ALB uniquement"
    vpc_id      = var.vpc_id

    tags = {
        Name = "${local.name}-web-sg"
    }
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
    #checkov:skip=CKV_AWS_260:Faux positif, la source est le security group de l ALB et non 0.0.0.0/0
    security_group_id            = aws_security_group.web.id
    description                  = "HTTP depuis l ALB uniquement"
    referenced_security_group_id = aws_security_group.alb.id
    ip_protocol                  = "tcp"
    from_port                    = 80
    to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "web_https" {
    security_group_id = aws_security_group.web.id
    description       = "HTTPS sortant (paquets, API SSM)"
    cidr_ipv4         = "0.0.0.0/0"
    ip_protocol       = "tcp"
    from_port         = 443
    to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "web_http" {
    security_group_id = aws_security_group.web.id
    description       = "HTTP sortant (depots Debian)"
    cidr_ipv4         = "0.0.0.0/0"
    ip_protocol       = "tcp"
    from_port         = 80
    to_port           = 80
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------
resource "aws_lb" "this" {
    #checkov:skip=CKV_AWS_91:Pas de logs d acces ALB (bucket S3 dedie hors perimetre, Learner Lab)
    #checkov:skip=CKV_AWS_150:Pas de protection contre la suppression, l infrastructure est detruite entre les sessions
    #checkov:skip=CKV2_AWS_28:Pas de WAF dans le perimetre du projet (cout, Learner Lab)
    name                       = "${local.name}-alb"
    load_balancer_type         = "application"
    internal                   = false
    security_groups            = [aws_security_group.alb.id]
    subnets                    = var.subnet_ids
    drop_invalid_header_fields = true

    tags = {
        Name = "${local.name}-alb"
    }
}

resource "aws_lb_target_group" "this" {
    #checkov:skip=CKV_AWS_378:TLS termine sur l ALB, trafic HTTP limite au VPC entre l ALB et les instances
    name     = "${local.name}-tg"
    port     = 80
    protocol = "HTTP"
    vpc_id   = var.vpc_id

    health_check {
        path                = "/"
        matcher             = "200"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 3
    }

    tags = {
        Name = "${local.name}-tg"
    }
}

resource "aws_lb_listener" "https" {
    load_balancer_arn = aws_lb.this.arn
    port              = 443
    protocol          = "HTTPS"
    ssl_policy        = var.ssl_policy
    certificate_arn   = aws_acm_certificate_validation.this.certificate_arn

    default_action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.this.arn
    }
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.this.arn
    port              = 80
    protocol          = "HTTP"

    default_action {
        type = "redirect"

        redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
        }
    }
}

# ---------------------------------------------------------------------------
# Instances web
# ---------------------------------------------------------------------------
resource "aws_launch_template" "web" {
    name_prefix   = "${local.name}-web-"
    image_id      = var.ami_id
    instance_type = var.instance_type

    vpc_security_group_ids = [aws_security_group.web.id]

    iam_instance_profile {
        name = var.instance_profile_name
    }

    # IMDSv2 obligatoire
    metadata_options {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
    }

    # Volume racine chiffre (Debian 12 : /dev/xvda)
    block_device_mappings {
        device_name = "/dev/xvda"

        ebs {
        volume_size           = 8
        volume_type           = "gp3"
        encrypted             = true
        delete_on_termination = true
        }
    }

    user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tftpl", {
        environment        = var.environment
        project_name       = var.project_name
        aws_region         = var.aws_region
        ssm_parameter_name = var.ssm_parameter_name
        domain_name        = var.domain_name
    }))

    tag_specifications {
        resource_type = "instance"

        tags = {
        Name = "${local.name}-web"
        }
    }

    tag_specifications {
        resource_type = "volume"

        tags = {
        Name = "${local.name}-web"
        }
    }

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_autoscaling_group" "web" {
    name                      = "${local.name}-web-asg"
    vpc_zone_identifier       = var.subnet_ids
    desired_capacity          = var.desired_capacity
    min_size                  = var.min_size
    max_size                  = var.max_size
    target_group_arns         = [aws_lb_target_group.this.arn]
    health_check_type         = "ELB"
    health_check_grace_period = 180

    launch_template {
        id      = aws_launch_template.web.id
        version = aws_launch_template.web.latest_version
    }

    # Remplacement progressif des instances quand le launch template change
    instance_refresh {
        strategy = "Rolling"

        preferences {
        min_healthy_percentage = 50
        }
    }

    tag {
        key                 = "Name"
        value               = "${local.name}-web"
        propagate_at_launch = true
    }
}
