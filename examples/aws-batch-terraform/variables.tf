variable "aws_region" {
  type        = string
  description = "AWS region containing the existing network"
}

variable "project_name" {
  type        = string
  description = "Short prefix for example resources"
  default     = "example-batch"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Existing private subnet IDs used by Batch workers"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Existing security groups used by Batch workers"
}

variable "max_vcpus" {
  type        = number
  description = "Hard development capacity guardrail"
  default     = 8
}

variable "instance_types" {
  type        = list(string)
  description = "Allowed x86 instance types for this example"
  default     = ["m7i.large", "m6i.large"]
}
