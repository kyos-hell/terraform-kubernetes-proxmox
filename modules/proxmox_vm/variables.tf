variable "name" {
  type = string
}
variable "fqdn" {
  type = string
}
variable "ip" {
  type = string
}
variable "cpu" {
  type = number
}
variable "memory" {
  type = number
}
variable "role" {
  type = string
}
variable "template_vm" {
  type = number
}
variable "node_name" {
  type = string
}
variable "network_bridge" {
  type = string
}
variable "system_disk" {
  type = object({
    storage = string
    size    = number
  })
}
variable "cloud_user_file_id" {}
variable "cloud_meta_file_id" {}
variable "network_prefix" {
  type = number
}
variable "gateway_ipv4" {
  type = string
}
variable "additionnal_disks" {
  type    = list(object({ storage = string, size = number }))
  default = []
}
variable "tags" {
  type    = list(string)
  default = ["ubuntu"]
}
