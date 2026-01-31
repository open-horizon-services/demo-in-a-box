packer {
  required_plugins {
    vagrant = {
      version = "~> 1"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

variable "box_version" {
  type    = string
  default = "1.0.0"
  description = "Version number for the custom box"
}

variable "ubuntu_box_version" {
  type    = string
  default = "20240126.0.0"
  description = "Ubuntu Jammy base box version to build from"
}

source "vagrant" "ubuntu-jammy" {
  communicator = "ssh"
  source_path  = "ubuntu/jammy64"
  box_version  = var.ubuntu_box_version
  provider     = "virtualbox"
  
  output_dir = "packer_output"
  teardown_method = "destroy"
  skip_add = true
}

build {
  sources = ["source.vagrant.ubuntu-jammy"]
  
  provisioner "shell" {
    inline = [
      "set -e",
      "echo '==> Setting non-interactive mode'",
      "export DEBIAN_FRONTEND=noninteractive",
      "",
      "echo '==> Updating package lists'",
      "sudo apt-get -y update",
      "",
      "echo '==> Upgrading system packages'",
      "sudo apt-get -y upgrade --no-install-recommends",
      "",
      "echo '==> Installing Open Horizon dependencies'",
      "sudo apt-get install -y --no-install-recommends \\",
      "  gcc \\",
      "  make \\",
      "  git \\",
      "  curl \\",
      "  jq \\",
      "  net-tools \\",
      "  docker.io \\",
      "  docker-compose-v2",
      "",
      "echo '==> Cleaning up package cache'",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "",
      "echo '==> Enabling docker service'",
      "sudo systemctl enable docker",
      "",
      "echo '==> Box preparation complete'",
      "echo 'Installed packages:'",
      "dpkg -l | grep -E '(gcc|make|git|curl|jq|net-tools|docker)'"
    ]
  }
  
  provisioner "shell" {
    inline = [
      "echo '==> Zeroing out free space to improve box compression'",
      "sudo dd if=/dev/zero of=/EMPTY bs=1M || true",
      "sudo rm -f /EMPTY",
      "sync"
    ]
  }
  
  post-processor "shell-local" {
    inline = [
      "set -e",
      "echo '==> Copying and renaming box file'",
      "cp packer_output/package.box ubuntu-jammy-horizon-virtualbox-${var.box_version}.box",
      "",
      "echo '==> Creating metadata file'",
      "echo '{",
      "  \"name\": \"demo-in-a-box/ubuntu-jammy-horizon\",",
      "  \"description\": \"Ubuntu 22.04 LTS with Open Horizon dependencies pre-installed\",",
      "  \"versions\": [{",
      "    \"version\": \"${var.box_version}\",",
      "    \"providers\": [{",
      "      \"name\": \"virtualbox\",",
      "      \"url\": \"file://$(pwd)/ubuntu-jammy-horizon-virtualbox-${var.box_version}.box\"",
      "    }]",
      "  }]",
      "}' > box-metadata.json",
      "",
      "echo ''",
      "echo '========================================='",
      "echo 'Custom box built successfully!'",
      "echo '========================================='",
      "echo 'Box file: ubuntu-jammy-horizon-virtualbox-${var.box_version}.box'",
      "echo 'Metadata: box-metadata.json'",
      "echo ''",
      "echo 'To add this box to Vagrant, run:'",
      "echo '  vagrant box add --name demo-in-a-box/ubuntu-jammy-horizon ubuntu-jammy-horizon-virtualbox-${var.box_version}.box'",
      "echo ''"
    ]
  }
}
