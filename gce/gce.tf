#network

provider "google" {
    credentials = "${file("~/.config/gcloud/gce_tf.json")}"
    project = "gce-rke-cluster"
    region = "us-east1"
    zone = "us-east1-c"
}

resource "google_compute_network" "gce_vpc" {
  name = "gce-vpc"
  description = "GCE Kubernetes VPC"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gce_vpc_subnet" {
    name = "gce-subnet"
    ip_cidr_range = "10.240.0.0/24"
    region = "us-east1"
    network = google_compute_network.gce_vpc.self_link
}

resource "google_compute_address" "gce_address" {
    name = "gce-address"
    region = "us-east1"
}

data "google_compute_address" "gce_address_ip" {
    name = "gce-address"
}

# firewall

resource "google_compute_firewall" "gce_firewall_internal" {
    name = "gce-firewall-internal"
    network = google_compute_network.gce_vpc.self_link

    allow {
        protocol = "icmp"
    }

    allow {
        protocol = "tcp"
    }

    allow {
        protocol = "udp"
    }
    source_ranges = ["10.240.0.0/24", "10.200.0.0/16"]
}

resource "google_compute_firewall" "gce_firewall_external" {
    name = "gce-firewall-external"
    network = google_compute_network.gce_vpc.self_link

    allow {
        protocol = "icmp"
    }

    allow {
        protocol = "tcp"
        ports = ["22","6443"]
    }
    source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "rke_allow_health_check" {
    name = "rke-allow-health-check"
    network = google_compute_network.gce_vpc.self_link

    allow {
        protocol = "tcp"
    }
    #google pools
    source_ranges = ["209.85.152.0/22","209.85.204.0/22","35.191.0.0/16"]
}

# forwarding

resource "google_compute_forwarding_rule" "rke-api-forward" {
    name = "rke-forward"
    #port_range = "6443"
    port_range = "1-65535"
    ip_address = data.google_compute_address.gce_address_ip.address
    target = google_compute_target_pool.rke_target_pool.self_link
}


data "google_compute_forwarding_rule" "rke-forward-data" {
  name = "rke-forward"
}

#resource "google_compute_forwarding_rule" "rke-https-forward" {
#    name = "rke-forward"
#    ip_address = data.google_compute_address.gce_address_ip.address
#    port_range = "443"
#    target = google_compute_target_pool.rke_target_pool.self_link
#}

# load balance

resource "google_compute_target_pool" "rke_target_pool" {
    name = "rke-target-pool"

    instances = [
        google_compute_instance.master_1.self_link,
        google_compute_instance.worker_1.self_link,
    ]

    health_checks = [
        google_compute_http_health_check.rke_health_check.name
    ]
}

# health

resource "google_compute_http_health_check" "rke_health_check" {
    name = "rke-health-check"
    request_path = "/healthz"
    check_interval_sec = 10
    timeout_sec = 1
}

# compute

resource "google_compute_instance" "master_1" {
    name = "master-1"
    machine_type = "n1-standard-1"
    zone = "us-east1-c"

    boot_disk {
        initialize_params {
            image = "ubuntu-1804-bionic-v20200218"
            size = 40
        }
    }

    can_ip_forward = true

    tags = ["kubernetes", "controller"]

    network_interface {
        network = google_compute_network.gce_vpc.self_link
        network_ip = "10.240.0.11"
        subnetwork = google_compute_subnetwork.gce_vpc_subnet.self_link

        access_config {
            //ephemeral_ip
        }
    }

    service_account {
        scopes = ["compute-rw", "storage-ro", "service-management", "service-control", "logging-write", "monitoring"]
    }
}

resource "google_compute_instance" "worker_1" {
    name = "worker-1"
    machine_type = "n1-standard-1"
    zone = "us-east1-c"

    boot_disk {
        initialize_params {
            image = "ubuntu-1804-bionic-v20200218"
            size = 40
        }
    }

    metadata = {
        pod-cidr = "10.200.1.0/24"
    }

    can_ip_forward = true

    tags = ["kubernetes", "worker"]

    network_interface {
        network = google_compute_network.gce_vpc.self_link
        network_ip = "10.240.0.21"
        subnetwork = google_compute_subnetwork.gce_vpc_subnet.self_link

        access_config {
            //ephemeral_ip
        }
    }

    service_account {
        scopes = ["compute-rw", "storage-ro", "service-management", "service-control", "logging-write", "monitoring"]
    }
}

# DNS 

resource "google_dns_managed_zone" "rke-cluster" {
  name        = "rke-cluster"
  dns_name    = "rke.cluster."
  description = "Internal DNS name"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.gce_vpc.self_link
    }
  }
}

resource "google_dns_record_set" "a" {
  name         = "${google_dns_managed_zone.rke-cluster.dns_name}"
  managed_zone = google_dns_managed_zone.rke-cluster.name
  type         = "A"
  ttl          = 300

  rrdatas = [google_compute_forwarding_rule.rke-api-forward.ip_address]
}


# output
output "out_worker_1_private_ip" {
    value = google_compute_instance.worker_1.network_interface.0.network_ip
}

output "out_worker_1_public_ip" {
    value = google_compute_instance.worker_1.network_interface.0.access_config.0.nat_ip
}

output "out_master_1_private_ip" {
    value = google_compute_instance.master_1.network_interface.0.network_ip
}

output "out_master_1_public_ip" {
    value = google_compute_instance.master_1.network_interface.0.access_config.0.nat_ip
}

output "out_loadbalancer_ip" {
    value = data.google_compute_forwarding_rule.rke-forward-data.ip_address
}

