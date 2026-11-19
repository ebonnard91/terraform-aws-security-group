variable "project_name" {
  description = "Nom du projet, utilise comme prefixe des ressources"
  type        = string
}

variable "environment" {
  description = "Environnement de deploiement (dev ou prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment doit valoir dev ou prod."
  }
}

variable "aws_region" {
  description = "Region AWS, utilisee par l'instance pour lire Parameter Store"
  type        = string
}

variable "vpc_id" {
  description = "ID du VPC"
  type        = string
}

variable "subnet_ids" {
  description = "Sous-reseaux de l'ALB et des instances (au moins deux AZ)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Un ALB exige au moins deux sous-reseaux dans deux AZ differentes."
  }
}

variable "ami_id" {
  description = "AMI des instances web (Debian 12)"
  type        = string
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t3.micro"
}

variable "instance_profile_name" {
  description = "Profil d'instance IAM (Learner Lab : LabInstanceProfile)"
  type        = string
}

variable "ssm_parameter_name" {
  description = "Nom du parametre SSM SecureString lu par l'instance au demarrage"
  type        = string
}

variable "desired_capacity" {
  description = "Nombre d'instances souhaite dans l'Auto Scaling Group"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Taille minimale de l'Auto Scaling Group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Taille maximale de l'Auto Scaling Group"
  type        = number
  default     = 4
}

variable "domain_name" {
  description = "Nom de domaine public de l'application (ex: dev.aero-nex.fr). Le DNS est gere hors AWS."
  type        = string
}

variable "ssl_policy" {
  description = "Politique TLS du listener HTTPS"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "certificate_validation_timeout" {
  description = "Duree d'attente maximale de la validation DNS du certificat ACM"
  type        = string
  default     = "45m"
}
