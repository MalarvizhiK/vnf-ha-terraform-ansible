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
  remote     = var.f5_mgmt_ipv4_cidr_block
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
    private_key = "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcnNhAAAAAwEAAQAAAQEAxTOrJ6gAMbbIp42kxV+dEXcCL+8dbXOpTdgM9tosh/a89WqeJGnnisR0fvcGD+UvK4jP0BhZmbGoZaNHEINRSc8wQX5hmoBofPnNMDl0YkFBnNvJ/g/InWqcywqvoYENYtYKQb+RIRV9FghuZpvgQnO/kyu9GRR736MbydZ+MF/lL1uTAPEofBEFEMYYcqDQ+6UwbKKdsYU2DfKliCGVVXq4cDBWxfgyP94YtuvJjYK1DEJytAPPaAqal+WDFYKktAl6vn5K6DvosQvbTsp0OobOhwdJbO3HwqSHxesXPFqNcs8EKFRNO6YbP+pCbevczM7XnvCdY0iNEyS3eohFywAAA9gkw4MRJMODEQAAAAdzc2gtcnNhAAABAQDFM6snqAAxtsinjaTFX50RdwIv7x1tc6lN2Az22iyH9rz1ap4kaeeKxHR+9wYP5S8riM/QGFmZsahlo0cQg1FJzzBBfmGagGh8+c0wOXRiQUGc28n+D8idapzLCq+hgQ1i1gpBv5EhFX0WCG5mm+BCc7+TK70ZFHvfoxvJ1n4wX+UvW5MA8Sh8EQUQxhhyoND7pTBsop2xhTYN8qWIIZVVerhwMFbF+DI/3hi268mNgrUMQnK0A89oCpqX5YMVgqS0CXq+fkroO+ixC9tOynQ6hs6HB0ls7cfCpIfF6xc8Wo1yzwQoVE07phs/6kJt69zMztee8J1jSI0TJLd6iEXLAAAAAwEAAQAAAQB/PgKO+QD/EvDP5D5QOIyRi1e29DPpvrqchu5+jXI0XMm6FQxrdIY5bN+6WMvpj7jq/0EQBdYyrIZ65mrhRco6tNxvNgvmdDp3gXubRUdKas7aVps0Opz4raT0AjYnIK0xe+hsWh5b2ZC3mcMapDOEzUjsvkkqmKQBPi6dArCzptkGRs1cDjNs4SP06KHg/98uVEcY40b+hXkl9WVnaRTiKpG9sBixL0ajAv0jjU84/ym3uYK6HmILj3JiZ6xQozApvq0GZmbBJgjWCYggEQIJKiEhC+L5G91e/SVwv5TmUKqzKBciQ8kXTptzMeqa4IymPuPIf76S5DN15TfkxnpRAAAAgBCKQK8SOIxWUc5kr42R+wFtXNXWKd5UJsK/uFzpzf1bSFGNPj5DluMUlaUpIKOwcZDAXvNYfW6zJU2cmGBqkJD9nSnMb/BEk6H4gIIoPfwXLlFj0gYl+FJ/l3FxHIgmADRGT38zqM+uAkFNw6p5a2ewc/5qtqG/R7s2znhLeJ/4AAAAgQD6SnYYEUV/10HVar8mwzGzc+NrhDpkcpBvfMfAB26YtlzIlHjkq50aj3fnBUJ98X7UEil2JPJjMxceLmL5CM3jeSSeso0H2VzVWbiK95h8dS7+M8Qkw4aeF0QGOGWK3/yRK4mNEof4wi0f2NXjg3s8tA1agL6pTzUujUxLmp+EwwAAAIEAybMzhE1q2WOZg3VA6s9xPsblYB2vWet9FiqyS49e7VJpYwsvm09Ydc6Mu22pWeglcwJSzFw1ddtnxOC8B0vYSs+Kq58Mg/n5hmaJXiuKOHYjpVLTiLCaHYOfx0zS5pUO5coSkYtiCj9YW/T/i/Iaa8+H7zZ/i6IZzvRovzZWilkAAAAhbWFsYXJrQE1hbGFycy1NYWNCb29rLVByby0yLmxvY2FsAQI="
  }

  provisioner "ansible" {
    plays {
      playbook {
        file_path = "script/install.yaml"
      }
      verbose = true
       extra_vars = {
        vpcid = var.vpc_id
        vpcurl = var.rias_api_url
        zone = var.zone
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


