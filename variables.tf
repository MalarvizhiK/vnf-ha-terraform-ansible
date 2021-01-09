variable "TF_VERSION" {
 default = "0.12"
 description = "terraform engine version to be used in schematics"
}

variable "region" {
  default     = "us-south"
  description = "The VPC Region that you want your VPC, networks and the F5 virtual server to be provisioned in. To list available regions, run `ibmcloud is regions`."
}

variable "generation" {
  default     = 2
  description = "The VPC Generation to target. Valid values are 2 or 1."
}

variable "zone" {
  default     = "us-south-1"
  description = "The zone to use. If unspecified, the us-south-1 is used."
}

variable "resource_group" {
  default     = "Default"
  description = "The resource group to use. If unspecified, the account's default resource group is used."
}

variable "vpc_id" {
  default     = ""
  description = "The vpc id to use." 
}

variable "rias_api_url" {
  default     = "https://us-south.iaas.cloud.ibm.com"
  description = "The public RIAS endpoint url of VPC."
}

variable "apikey" {
  default     = ""
  description = "The apikey of IBM Cloud account."
}

variable "ssh_key" {
  default     = ""
  description = "The ssh key to use. If unspecified, 'my-ssh-key' is used."
}

variable "private_ssh_key" {
  default     = "--BEGIN--"
  description = "The private ssh key to use."
}

variable "failover_function_subnet_id" {
  default     = ""
  description = "subnet1 ipv4 cidr block."
}

variable "mgmt_ip1" {
  default     = ""
  description = "The management IP 1 of VNF."
}

variable "ext_ip1" {
  default     = ""
  description = "The external IP 1 of VNF."
}

variable "mgmt_ip2" {
  default     = ""
  description = "The management IP 2 of VNF."
}

variable "ext_ip2" {
  default     = ""
  description = "The external IP 2 of VNF."
}

variable "f5_mgmt_ipv4_cidr_block" {
  default     = ""
  description = "F5 Management subnet ipv4 cidr block."
}

variable "ha_password1" {
  default     = ""
  description = "HA instance1 Password."
}

variable "ha_password2" {
  default     = ""
  description = "HA instance2 Password."
}
