provider "aws" {
  profile = "default"
  region  = var.region
}

data "aws_ami" "centos" {
  most_recent = true

  filter {
    name   = "name"
    values = ["CentOS Linux 7 x86_64 HVM EBS *"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["679593333241"] # CentOS
}


resource "aws_instance" "docker_host_1" {
  ami           = "${data.aws_ami.centos.id}"
  instance_type = "t2.medium"

  root_block_device {
    volume_size = 16
  }

  key_name = "ssh-key"
}

resource "aws_key_pair" "ssh" {
  key_name   = "ssh-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLe2ZLi8HGqGi6LC1XsdD7G7Ja85aboH4d/2XUpM664AQvz3e4YkfY/kI4UgXXgWRXApIRjhLO2xKaXYWmIvzjfxcZ5GlB2BwNwdEdiGFAUMU9Ia5D0Ui8nZvZvmPZ9ukQ57+HHLVg8lPd4tgC8DxhrfMk9FU7nTG1bTWEzQP0vn84GTYR42JjzfURBkoKBMYGp2cgpzWD9/KWj86HwBxICuATJxkQ7XhIq6W2SKCjetyBKRRyN6oBdqo1ZfbRvgNHUksu8nxy+suFuOrMhfxDHYhHAZUxnYKd5oIsjY5fDs2PhKldKzScbBbWvHSDHS9D24Khm93ouCyXFc8DW5oZ zesty@FORTKICKASSLITE"
}

resource "aws_eip" "ip" {
  vpc = true
  instance = aws_instance.docker_host_1.id
}

module "ansible_provisioner" {
  source    = "github.com/cloudposse/tf_ansible"

  arguments = ["--user=centos"]
  envs      = ["host=${aws_instance.docker_host_1.public_ip}"]
  playbook  = "/home/zesty/ansible/playbooks/provision_docker_hosts.yml"
  dry_run   = false

}