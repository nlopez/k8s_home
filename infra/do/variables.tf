variable "region" {
  description = "DigitalOcean region. nyc3 is closest to lga1."
  type        = string
  default     = "nyc3"
}

variable "cluster_name" {
  type    = string
  default = "bootstrap-do"
}

variable "kubernetes_minor" {
  description = "Kubernetes minor version prefix to track (e.g. 1.33.). Patch level is picked automatically."
  type        = string
  default     = "1.33."
}

variable "node_size" {
  type    = string
  default = "s-2vcpu-4gb"
}

variable "min_nodes" {
  type    = number
  default = 2
}

variable "max_nodes" {
  type    = number
  default = 3
}

# Address plan. Home (kubeadm-init.conf + tailnet policy) owns 10.43.0.0/16 and
# 192.168.221-223.0/24, so DO lives in 10.44.0.0/16. Keep these disjoint from
# every other range advertised on the tailnet.
variable "vpc_cidr" {
  type    = string
  default = "10.44.0.0/20"
}

variable "pod_cidr" {
  type    = string
  default = "10.44.16.0/20"
}

variable "service_cidr" {
  type    = string
  default = "10.44.32.0/20"
}
