#networks

resource "google_compute_network" "gce_vpc" {
  name = "gce-vpc"
  description = "GCE Kubernetes VPC"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gce_vpc_subnet" {
    name = "gce-subnet"
    ip_cidr_range = "10.240.0.0/24"
    region = "us-east1-c"
    network = google_compute_network.gce_vpc.self_link
}

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
    source_ranges = "0.0.0.0/0"
}

resource "google_compute_address" "gce_address" {
    name = "gce-address"
    region = "us-east1-c"
}

# compute

resource "google_compute_instance" "master_1 {
    name = "master-1"
    machine_type = "n1-standard-1"
    zone = "us-east-1c"

    boot_disk {
        initialize_params {
            image = "ubuntu-1804-lts/ubuntu-os-cloud"
            size = 40
        }
    }

    metadata = {
        pod-cidr = "10.200.1.0/24"
    }

    can_ip_forward = true

    tags = ["kubernetes", "controller"]

    network_interface {
        network = "google_compute_network.gce_vpc.self_link"
        network_ip = "10.240.0.21"
        subnetwork = google_compute_subnetwork.gce_vpc_subnet.self_link
    }

    service_account {
        scopes = ["compute-rw", "storage-ro", "service-management", "service-control", "logging-write", "monitoring"]
    }
}