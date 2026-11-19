output "alb_dns_name" {
  description = "Nom DNS de l'ALB, cible du CNAME a creer chez le registrar"
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN de l'ALB"
  value       = aws_lb.this.arn
}

output "alb_zone_id" {
  description = "Zone hebergee de l'ALB (pour un enregistrement ALIAS)"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "ARN du target group"
  value       = aws_lb_target_group.this.arn
}

output "autoscaling_group_name" {
  description = "Nom de l'Auto Scaling Group"
  value       = aws_autoscaling_group.web.name
}

output "alb_security_group_id" {
  description = "ID du security group de l'ALB"
  value       = aws_security_group.alb.id
}

output "web_security_group_id" {
  description = "ID du security group des instances web"
  value       = aws_security_group.web.id
}

output "certificate_arn" {
  description = "ARN du certificat ACM"
  value       = aws_acm_certificate.this.arn
}

output "acm_validation_records" {
  description = "Enregistrements CNAME a creer chez le registrar pour valider le certificat ACM"
  value = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  }
}
