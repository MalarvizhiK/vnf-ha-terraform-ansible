data "ibm_is_region" "region" {
  name = var.region
}

data "ibm_is_zone" "zone" {
  name   = "us-south-1"
  region = data.ibm_is_region.region.name
}

# lookup SSH public keys by name
data "ibm_is_ssh_key" "ssh_key" {
  name = var.ssh_key
}

data "ibm_is_image" "custom_image" {
  name = "ibm-ubuntu-18-04-1-minimal-amd64-2"
}

##############################################################################
# Provider block - Alias initialized tointeract with VNFSVC account
##############################################################################
provider "ibm" {
  generation       = var.generation
  region           = var.region
  ibmcloud_timeout = 300
}

output "ssh_key_private" {
  value = var.private_ssh_key
} 

##############################################################################
# Read/validate Resource Group
##############################################################################
data "ibm_resource_group" "rg" {
  name = var.resource_group
}

resource "ibm_is_security_group" "ubuntu_vsi_sg" {
  name           = "ubuntu-vsi-sg"
  vpc            = var.vpc_id
  resource_group = data.ibm_resource_group.rg.id
}

//security group rule to allow ssh
resource "ibm_is_security_group_rule" "ubuntu_sg_allow_ssh" {
  group      = ibm_is_security_group.ubuntu_vsi_sg.id
  direction  = "inbound"
  remote     = "0.0.0.0/0"
  tcp {
    port_min = 22
    port_max = 22
  }
}

resource "ibm_is_security_group_rule" "ubuntu_sg_rule_tcp" {
    depends_on = [ibm_is_security_group_rule.ubuntu_sg_allow_ssh]
    group      = ibm_is_security_group.ubuntu_vsi_sg.id
    direction = "inbound"
    remote = var.f5_mgmt_ipv4_cidr_block
    // remote = "0.0.0.0/0"
    tcp  {
        port_min = 3000
        port_max = 3000
    }
 }

resource "ibm_is_security_group_rule" "ubuntu_sg_rule_out_icmp" {
  depends_on = [ibm_is_security_group_rule.ubuntu_sg_rule_tcp]
  group      = ibm_is_security_group.ubuntu_vsi_sg.id
  direction  = "outbound"
  remote     = "0.0.0.0/0"
  icmp {
    code = 0
    type = 8
  }
}

resource "ibm_is_security_group_rule" "ubuntu_sg_rule_all_out" {
  depends_on = [ibm_is_security_group_rule.ubuntu_sg_rule_out_icmp]
  group      = ibm_is_security_group.ubuntu_vsi_sg.id
  direction  = "outbound"
  remote     = "0.0.0.0/0"
}

//source vsi
resource "ibm_is_instance" "ubuntu_vsi" {
  depends_on = [ibm_is_security_group_rule.ubuntu_sg_rule_all_out]
  name           = "ubuntu-ha-vsi"
  image          = data.ibm_is_image.custom_image.id
  profile        = "bx2-2x8"
  resource_group = data.ibm_resource_group.rg.id

  primary_network_interface {
    subnet          = var.failover_function_subnet_id
    security_groups = [ibm_is_security_group.ubuntu_vsi_sg.id]
  }

  keys = [data.ibm_is_ssh_key.ssh_key.id]
  vpc  = var.vpc_id
  zone = var.zone
}

//floating ip for above VSI
resource "ibm_is_floating_ip" "ubuntu_vsi_fip" {
  name   = "ubuntu-vsi-fip"
  target = ibm_is_instance.ubuntu_vsi.primary_network_interface[0].id
}

# ---------------------------------------------------------------------------------------------------------------------
# Provision the server using remote-exec
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "ubuntu_provisioner" {
  triggers = {
    public_ip = ibm_is_floating_ip.ubuntu_vsi_fip.address
  }

  connection {
    type  = "ssh"
    host  = ibm_is_floating_ip.ubuntu_vsi_fip.address
    user  = "root"
    port  = 22
    agent = false
    private_key = var.private_ssh_key
  }

  // copy our example script to the server
  provisioner "file" {
    source      = "script/install.sh"
    destination = "/root/install.sh"
  }
  
  // copy our example script to the server
  provisioner "file" {
    source      = "script/update_script.sh"
    destination = "/root/update_script.sh"
  }

  // change permissions to executable and pipe its output into a new file
  provisioner "remote-exec" {
    inline = [
      "chmod +x /root/install.sh",
      "bash /root/install.sh ${var.apikey} ${var.vpc_id} ${var.rias_api_url} ${var.zone} ${var.mgmt_ip1} ${var.ext_ip1} ${var.mgmt_ip2} ${var.ext_ip2} ${ibm_is_instance.ubuntu_vsi.primary_network_interface[0].primary_ipv4_address} ${var.ha_password1} ${var.ha_password2}  > /root/install.log",
    ]
  }
  
  /*
    provisioner "local-exec" {
    # copy the log file back to CWD, which will be tested
    command = "scp -o StrictHostKeyChecking=no root@${ibm_is_floating_ip.ubuntu_vsi_fip.address}:/root/install.log ."
  }
    */
}
