variable "cluster_name" {
  type        = string
  description = "The name of the cluster"
}

variable "create_namespace" {
  type    = bool
  default = true
}

variable "karpenter_namespace" {
  type        = string
  description = "The K8s namespace to deploy karpenter into"
  default     = "karpenter"
}

variable "karpenter_version" {
  type        = string
  description = "Karpenter version"
  default     = "0.13.2"
}

variable "karpenter_provisioner_files" {
  type        = list(string)
  description = "Path to the provisioner values templates"
  default     = []
}

variable "cluster_worker_iam_role_name" {
  type        = string
  description = "IAM role name"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs"
  default     = []
}

