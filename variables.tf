variable "cluster_name" {
  description = "The name of the cluster"
  type        = string
}

variable "create_namespace" {
  description = "Whether a new namespace should be created"
  type        = bool
  default     = false
}

variable "karpenter_namespace" {
  description = "The K8s namespace to deploy Karpenter into. Recommended to be kube-system asof v0.33"
  type        = string
  default     = "kube-system"
}

variable "karpenter_version" {
  description = "Karpenter version to be deployed"
  type        = string
  default     = "v0.33.2"
}

variable "iam_role_name" {
  description = "Instance role name for Karpenter nodes to assume"
  type        = string
}

variable "availability_zones" {
  description = "The available AZs"
  type        = list(any)
}

variable "karpenter_nodepools" {
  description = "Set of paths to the Kaprenter NodePool configuration resources"
  type        = set(string)
  default     = []
}

variable "additional_nodepool_parameters" {
  description = "Additional parameters that some or all of the nodepools support"
  type        = map(string)
  default     = {}
}

variable "karpenter_replicas" {
  description = "Number of Karpenter replicas. Defaults to -1. -1 indicates number of replicas is delegated to Karpenter (2 asof v0.29.2)"
  type        = number
  default     = -1
}

variable "log_level" {
  description = "Global log level"
  type        = string
  default     = "info"
}
