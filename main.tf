data "ibm_is_region" "region" {
  name = var.region
}

# create VSI in the subnet of HA pair
data "ibm_is_subnet" "vnf_subnet"{
   identifier = "${var.failover_function_subnet_id}"
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

##############################################################################
# Read/validate Resource Group
##############################################################################

resource "ibm_is_security_group" "ubuntu_vsi_sg" {
  name           = "ubuntu-vsi-sg"
  vpc            = data.ibm_is_subnet.vnf_subnet.vpc
  resource_group = data.ibm_is_subnet.vnf_subnet.resource_group
}

//security group rule to allow ssh
resource "ibm_is_security_group_rule" "ubuntu_sg_allow_ssh" {
  group     = ibm_is_security_group.ubuntu_vsi_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  tcp {
    port_min = 22
    port_max = 22
  }
}

resource "ibm_is_security_group_rule" "ubuntu_sg_rule_tcp" {
  depends_on = [ibm_is_security_group_rule.ubuntu_sg_allow_ssh]
  group      = ibm_is_security_group.ubuntu_vsi_sg.id
  direction  = "inbound"
  remote     = var.vnf_mgmt_ipv4_cidr_block
  // remote = "0.0.0.0/0"
  tcp {
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
  depends_on     = [ibm_is_security_group_rule.ubuntu_sg_rule_all_out]
  name           = "ubuntu-ha-vsi"
  image          = data.ibm_is_image.custom_image.id
  profile        = "bx2-2x8"
  resource_group = data.ibm_is_subnet.vnf_subnet.resource_group

  primary_network_interface {
    subnet          = var.failover_function_subnet_id
    security_groups = [ibm_is_security_group.ubuntu_vsi_sg.id]
  }

  keys = [data.ibm_is_ssh_key.ssh_key.id]
  vpc  = data.ibm_is_subnet.vnf_subnet.vpc
  zone = data.ibm_is_subnet.vnf_subnet.zone
}

//floating ip for above VSI
resource "ibm_is_floating_ip" "ubuntu_vsi_fip" {
  name   = "ubuntu-vsi-fip"
  target = ibm_is_instance.ubuntu_vsi.primary_network_interface[0].id
}

# ---------------------------------------------------------------------------------------------------------------------
# Provision the server using ansible-provisioner
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "ubuntu_ansible_provisioner" {
  depends_on = [ibm_is_floating_ip.ubuntu_vsi_fip]

  triggers = {
    public_ip = ibm_is_floating_ip.ubuntu_vsi_fip.address
  }

  connection {
    host = ibm_is_floating_ip.ubuntu_vsi_fip.address
    user = "root"  
    private_key = <<EOF
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcn
NhAAAAAwEAAQAAAQEAxTOrJ6gAMbbIp42kxV+dEXcCL+8dbXOpTdgM9tosh/a89WqeJGnn
isR0fvcGD+UvK4jP0BhZmbGoZaNHEINRSc8wQX5hmoBofPnNMDl0YkFBnNvJ/g/InWqcyw
qvoYENYtYKQb+RIRV9FghuZpvgQnO/kyu9GRR736MbydZ+MF/lL1uTAPEofBEFEMYYcqDQ
+6UwbKKdsYU2DfKliCGVVXq4cDBWxfgyP94YtuvJjYK1DEJytAPPaAqal+WDFYKktAl6vn
5K6DvosQvbTsp0OobOhwdJbO3HwqSHxesXPFqNcs8EKFRNO6YbP+pCbevczM7XnvCdY0iN
EyS3eohFywAAA9gkw4MRJMODEQAAAAdzc2gtcnNhAAABAQDFM6snqAAxtsinjaTFX50Rdw
Iv7x1tc6lN2Az22iyH9rz1ap4kaeeKxHR+9wYP5S8riM/QGFmZsahlo0cQg1FJzzBBfmGa
gGh8+c0wOXRiQUGc28n+D8idapzLCq+hgQ1i1gpBv5EhFX0WCG5mm+BCc7+TK70ZFHvfox
vJ1n4wX+UvW5MA8Sh8EQUQxhhyoND7pTBsop2xhTYN8qWIIZVVerhwMFbF+DI/3hi268mN
grUMQnK0A89oCpqX5YMVgqS0CXq+fkroO+ixC9tOynQ6hs6HB0ls7cfCpIfF6xc8Wo1yzw
QoVE07phs/6kJt69zMztee8J1jSI0TJLd6iEXLAAAAAwEAAQAAAQB/PgKO+QD/EvDP5D5Q
OIyRi1e29DPpvrqchu5+jXI0XMm6FQxrdIY5bN+6WMvpj7jq/0EQBdYyrIZ65mrhRco6tN
xvNgvmdDp3gXubRUdKas7aVps0Opz4raT0AjYnIK0xe+hsWh5b2ZC3mcMapDOEzUjsvkkq
mKQBPi6dArCzptkGRs1cDjNs4SP06KHg/98uVEcY40b+hXkl9WVnaRTiKpG9sBixL0ajAv
0jjU84/ym3uYK6HmILj3JiZ6xQozApvq0GZmbBJgjWCYggEQIJKiEhC+L5G91e/SVwv5Tm
UKqzKBciQ8kXTptzMeqa4IymPuPIf76S5DN15TfkxnpRAAAAgBCKQK8SOIxWUc5kr42R+w
FtXNXWKd5UJsK/uFzpzf1bSFGNPj5DluMUlaUpIKOwcZDAXvNYfW6zJU2cmGBqkJD9nSnM
b/BEk6H4gIIoPfwXLlFj0gYl+FJ/l3FxHIgmADRGT38zqM+uAkFNw6p5a2ewc/5qtqG/R7
s2znhLeJ/4AAAAgQD6SnYYEUV/10HVar8mwzGzc+NrhDpkcpBvfMfAB26YtlzIlHjkq50a
j3fnBUJ98X7UEil2JPJjMxceLmL5CM3jeSSeso0H2VzVWbiK95h8dS7+M8Qkw4aeF0QGOG
WK3/yRK4mNEof4wi0f2NXjg3s8tA1agL6pTzUujUxLmp+EwwAAAIEAybMzhE1q2WOZg3VA
6s9xPsblYB2vWet9FiqyS49e7VJpYwsvm09Ydc6Mu22pWeglcwJSzFw1ddtnxOC8B0vYSs
+Kq58Mg/n5hmaJXiuKOHYjpVLTiLCaHYOfx0zS5pUO5coSkYtiCj9YW/T/i/Iaa8+H7zZ/
i6IZzvRovzZWilkAAAAhbWFsYXJrQE1hbGFycy1NYWNCb29rLVByby0yLmxvY2FsAQI=
-----END OPENSSH PRIVATE KEY-----
EOF
  }

  provisioner "ansible" {
    plays {
      playbook {
        file_path = "script/install.yaml"
      }
      verbose = true
       extra_vars = {
        vpcid = data.ibm_is_subnet.vnf_subnet.vpc
        vpcurl = var.rias_api_url
        zone = data.ibm_is_subnet.vnf_subnet.zone
        apikey = var.apikey
        mgmtip1 = var.mgmt_ip1
        extip1 = var.ext_ip1
        mgmtip2 = var.mgmt_ip2
        extip2 = var.ext_ip2
        ipaddress = ibm_is_instance.ubuntu_vsi.primary_network_interface[0].primary_ipv4_address 
        ha1pwd = var.ha_password1
        ha2pwd = var.ha_password2
      }
    }

    ansible_ssh_settings {
      insecure_no_strict_host_key_checking = true
      connect_timeout_seconds              = 60
    }

  }
}


