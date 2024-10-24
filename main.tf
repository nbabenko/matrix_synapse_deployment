terraform {
  required_providers {
    grid = {
      source  = "threefoldtech/grid"
      version = "~> 1.11.1"
    }
  }
}

variable "node_id" {
  description = "ID of the node for deployment"
  type        = number
}

variable "vm_name" {
  description = "Name of the VM to be created"
  type        = string
}

variable "network_name" {
  description = "Name of the network to be created"
  type        = string
}

variable "cpu" {
  description = "Number of CPU cores for the VM"
  type        = number
}

variable "memory" {
  description = "Memory in MB for the VM"
  type        = number
}

variable "storage" {
  description = "Storage in MB for the VM"
  type        = number
}

variable "ssh_private_key_to_use" {
  description = "Path to the SSH private key to be used"
  type        = string
}

variable "ssh_public_key_to_use" {
  description = "Path to the SSH public key to be used"
  type        = string
}

variable "use_self_signed_ssl" {
  description = "Whether to use Let's Encrypt for SSL certificates"
  type        = bool
}

variable "ssl_certificate_key_path" {
  description = "Path to the SSL certificate key file"
  type        = string
}

variable "ssl_certificate_crt_path" {
  description = "Path to the SSL certificate file"
  type        = string
}

variable ssl_certificate_ca_bundle_path {
  description = "Path to the SSL certificate CA bundle file"
  type        = string
}

variable threefold_account_memo {
  description = "ThreeFold Account Memo"
  type        = string
}

provider "grid" {
  network = "main"
  mnemonics = var.threefold_account_memo
}

resource "grid_network" "matrix_network" {
  name     = var.network_name
  ip_range = "10.0.0.0/16"
  nodes    = [var.node_id]  
}

resource "grid_deployment" "matrix_vm" {
  name         = var.vm_name
  node         = var.node_id 
  network_name = grid_network.matrix_network.name

  vms {
    name        = var.vm_name
    flist       = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-latest.flist"
    cpu         = var.cpu
    memory      = var.memory
    rootfs_size = var.storage
    entrypoint  = "/sbin/zinit init"
    publicip    = true

    env_vars = {
      SSH_KEY = file(var.ssh_public_key_to_use)
    }
  }
}

resource "null_resource" "post_deployment_file_prepare" {
  depends_on = [grid_deployment.matrix_vm]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_to_use)
    host        = replace(grid_deployment.matrix_vm.vms[0].computedip, "/25", "")
  }

  # Ensure that the /matrix-synapse/data directory exists
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /matrix-synapse/data",
      "mkdir -p /tmp"
    ]
  }

  provisioner "file" {
    source      = "server_config.sh"
    destination = "/matrix-synapse/server_config.sh"
  }

  provisioner "file" {
    source      = "restore_from_backup.sh"
    destination = "/matrix-synapse/restore_from_backup.sh"
  }

  provisioner "file" {
    source      = "backup_matrix.sh"
    destination = "/matrix-synapse/backup_matrix.sh"
  }

  provisioner "file" {
    source      = "generate_self_signed_certificate.sh"
    destination = "/matrix-synapse/generate_self_signed_certificate.sh"
  }

  provisioner "file" {
    source      = "container_up.sh"
    destination = "/matrix-synapse/container_up.sh"
  }

  provisioner "file" {
    source      = "set_certificate_permissions.sh"
    destination = "/matrix-synapse/set_certificate_permissions.sh"
  }

  # Copy the shell script to the VM
  provisioner "file" {
    source      = "setup_matrix.sh"
    destination = "/tmp/setup_matrix.sh"
  }
}

resource "null_resource" "post_deployment_ssl_copy" {
  depends_on = [null_resource.post_deployment_file_prepare]
  count = var.use_self_signed_ssl ? 0 : 1

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_to_use)
    host        = replace(grid_deployment.matrix_vm.vms[0].computedip, "/25", "")
  }

  # Copy the SSL certificate and secret files to the VM
  provisioner "file" {
    source      = var.ssl_certificate_key_path
    destination = "/matrix-synapse/data/tls.key"
  }

  provisioner "file" {
    source      = var.ssl_certificate_crt_path
    destination = "/matrix-synapse/data/tls.crt"
  }

  provisioner "file" {
    source      = var.ssl_certificate_ca_bundle_path
    destination = "/matrix-synapse/data/ca-bundle.ca-bundle"
  }

}

resource "null_resource" "wait_for_dns_update" {
  depends_on = [null_resource.post_deployment_ssl_copy]
  count = var.use_self_signed_ssl ? 1 : 0  # Only execute when use_self_signed_ssl is true

  provisioner "local-exec" {
    command = <<EOT
      echo "Please update your DNS settings and add an A record for the IP: $(terraform output -raw vm_ip_address) with your target server name."
      echo "Once you have updated the DNS, create a file named 'continue.txt' in the current directory."
      while [ ! -f continue.txt ]; do
        echo "Waiting for 'continue.txt' file. Please create the file when done updating DNS to A record for the IP: $(terraform output -raw vm_ip_address) with your target server name."
        sleep 10
      done
      echo "DNS settings confirmed. Proceeding..."
    EOT
  }
}

resource "null_resource" "post_deployment_execute" {
  depends_on = [null_resource.wait_for_dns_update]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_to_use)
    host        = replace(grid_deployment.matrix_vm.vms[0].computedip, "/25", "")
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup_matrix.sh",
      "ls -la /tmp/setup_matrix.sh",  # Verify the script exists and is executable
      "/tmp/setup_matrix.sh"
    ]
  }
}

output "vm_ip_address" {
  value = replace(grid_deployment.matrix_vm.vms[0].computedip, "/25", "")
}
