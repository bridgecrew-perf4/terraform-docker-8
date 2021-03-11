terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.59.0"
    }
  }
}

provider "google" {
  # Configuration options
  project     = "tonal-bloom-302318"
  region      = "us-central1"
  zone        = "us-central1-a"
}

resource "google_compute_instance" "terraform-staging" {
  name          = "terraform-staging"
  #machine_type = "e2-small" // 2vCPU, 2GB RAM
  machine_type  = "e2-medium" // 2vCPU, 4GB RAM
  #machine_type = "custom-6-20480" // 6vCPU, 20GB RAM / 6.5GB RAM per CPU, if needed more refer to next line
  #machine_type = "custom-2-15360-ext" // 2vCPU, 15GB RAM

  #tags = ["terraform", "staging"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      size  = "10" // size in GB for Disk
      type  = "pd-balanced" // Available options: pd-standard, pd-balanced, pd-ssd
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP and external static IP
      #nat_ip = google_compute_address.static.address
    }
  }

  metadata = {
    ssh-keys = "root:${file("/root/.ssh/id_rsa.pub")}" // Point to ssh public key for user root
  }

#  provisioner "remote-exec" {
#    inline = [
#      "sudo apt update",
#    ]
#    connection {
#      type     = "ssh"
#      user     = "root"
#      private_key = file("/root/.ssh/id_rsa")
#      host        = self.network_interface[0].access_config[0].nat_ip
#    }
#  }
}

output "staging_public_ip" {
    value = google_compute_instance.terraform-staging.network_interface[0].access_config[0].nat_ip
}

resource "google_compute_instance" "terraform-production" {
  name          = "terraform-production"
  #machine_type = "e2-small" // 2vCPU, 2GB RAM
  machine_type  = "e2-medium" // 2vCPU, 4GB RAM
  #machine_type = "custom-6-20480" // 6vCPU, 20GB RAM / 6.5GB RAM per CPU, if needed more refer to next line
  #machine_type = "custom-2-15360-ext" // 2vCPU, 15GB RAM

  #tags = ["terraform", "production"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      size  = "10" // size in GB for Disk
      type  = "pd-balanced" // Available options: pd-standard, pd-balanced, pd-ssd
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP and external static IP
      #nat_ip = google_compute_address.static.address
    }
  }

  metadata = {
    ssh-keys = "root:${file("/root/.ssh/id_rsa.pub")}" // Point to ssh public key for user root
  }

#  provisioner "remote-exec" {
#    inline = [
#      "sudo apt update",
#    ]
#    connection {
#      type     = "ssh"
#      user     = "root"
#      private_key = file("/root/.ssh/id_rsa")
#      host        = self.network_interface[0].access_config[0].nat_ip
#    }
#  }
}

output "production_public_ip" {
    value = google_compute_instance.terraform-production.network_interface[0].access_config[0].nat_ip
}

#resource "local_file" "production_public_ip" {
#  content = <<-EOF
#    [production]
#    google_compute_instance.terraform-production.network_interface[0].access_config[0].nat_ip
#    EOF
#  filename = "./inventory/hosts"
#}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [google_compute_instance.terraform-production]

  create_duration = "30s" // Change to 90s
}

resource "null_resource" "ansible_hosts_provisioner" {
  depends_on = [time_sleep.wait_30_seconds]
  provisioner "local-exec" {
    interpreter = ["/bin/bash" ,"-c"]
    command = <<-EOT
      export terraform_staging_public_ip=$(terraform output staging_public_ip);
      export terraform_production_public_ip=$(terraform output production_public_ip);
      sed -e "s/staging_instance_ip/$terraform_staging_public_ip/g" ./inventory/hosts;
      sed -e "s/production_instance_ip/$terraform_production_public_ip" ./inventory/hosts;
    EOT
  }
}

resource "time_sleep" "wait_5_seconds" {
  depends_on = [null_resource.ansible_hosts_provisioner]

  create_duration = "5s" // Change to 10s
}

resource "null_resource" "ansible_playbook_provisioner" {
  depends_on = [time_sleep.wait_5_seconds]
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=\"False\" ansible-playbook -u root --private-key=\"/root/.ssh/id_rsa\" -i inventory/hosts main.yml"
  }
}