variable "allowed_cidr" {
  type        = "list"
  default     = ["0.0.0.0/0"]
  description = "A list of CIDR Networks to allow ssh access to."
}

variable "allowed_ipv6_cidr" {
  type        = "list"
  default     = ["::/0"]
  description = "A list of IPv6 CIDR Networks to allow ssh access to."
}

variable "allowed_security_groups" {
  type        = "list"
  default     = []
  description = "A list of Security Group ID's to allow access to."
}


variable "elb_subnet_ids" {
  description = "The subnets in which the ELB will be placed (used for security group)"
  type        = "list"
}

variable "name" {
  default = "bastion"
}

variable "ami" {}

variable "instance_type" {
  default = "t2.micro"
}

variable "iam_instance_profile" {}

variable "user_data_file" {
  default = "user_data.sh"
}

variable "s3_bucket_name" {}

variable "s3_bucket_uri" {
  default = ""
}

variable "enable_monitoring" {
  default = true
}

variable "ssh_user" {
  default = "ubuntu"
}

variable "enable_hourly_cron_updates" {
  default = "false"
}

variable "keys_update_frequency" {
  default = ""
}

variable "additional_user_data_script" {
  default = ""
}

variable "region" {
  default = "eu-west-1"
}

variable "vpc_id" {}

variable "security_group_ids" {
  description = "Comma seperated list of security groups to apply to the bastion."
  default     = ""
}

variable "subnet_ids" {
  default     = []
  description = "A list of subnet ids"
}

variable "eip" {
  default = ""
}

variable "associate_public_ip_address" {
  default = false
}

variable "key_name" {
  default = ""
}

variable "ssh_port" {
  default     = "22"
  description = "Inbound ssh port"
}

variable "elb_idle_timeout" {
  default     = "600"
  description = "The time in seconds that the connection is allowed to be idle. Default: 600"
}
