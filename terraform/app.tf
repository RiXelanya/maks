data "google_client_config" "default" {}

resource "google_compute_network" "default" {
  project = var.project_name
  name = "project-network"

  auto_create_subnetworks  = false
  enable_ula_internal_ipv6 = true
}

resource "google_compute_subnetwork" "default" {
  project = var.project_name
  name = "project-subnetwork"

  ip_cidr_range = "10.0.0.0/16"
  region        = "asia-southeast2"

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "EXTERNAL"

  network = google_compute_network.default.id
  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "192.168.0.0/24"
  }

  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "192.168.1.0/24"
  }
}

resource "google_container_cluster" "default" {
  name = "maks-autopilot-cluster"

  location                 = "asia-southeast2"
  enable_autopilot         = true
  enable_l4_ilb_subsetting = true

  network    = google_compute_network.default.id
  subnetwork = google_compute_subnetwork.default.id

  logging_service = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  ip_allocation_policy {
    stack_type                    = "IPV4_IPV6"
    services_secondary_range_name = google_compute_subnetwork.default.secondary_ip_range[0].range_name
    cluster_secondary_range_name  = google_compute_subnetwork.default.secondary_ip_range[1].range_name
  }

  # Set `deletion_protection` to `true` will ensure that one cannot
  # accidentally delete this instance by use of Terraform.
  deletion_protection = true
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.default.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.default.master_auth[0].cluster_ca_certificate)

  ignore_annotations = [
    "^autopilot\\.gke\\.io\\/.*",
    "^cloud\\.google\\.com\\/.*"
  ]
}

##   KUBERNETES WEB APP ##

resource "kubernetes_deployment_v1" "default" {
  metadata {
    name = "web-app-deployment"
  }

  spec {
    replicas = var.app_replicas
    selector {
      match_labels = {
        app = "web-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "web-app"
        }
      }

      spec {
        container {
          image = "us-docker.pkg.dev/google-samples/containers/gke/hello-app:2.0"
          name  = "hello-app-container"

          port {
            container_port = 8080
            name           = "web-app-svc"
          }

          security_context {
            allow_privilege_escalation = false
            privileged                 = false
            read_only_root_filesystem  = false

            capabilities {
              add  = []
              drop = ["NET_RAW"]
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "web-app-svc"

              http_header {
                name  = "X-Custom-Header"
                value = "Awesome"
              }
            }

            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }

        security_context {
          run_as_non_root = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        # Toleration is currently required to prevent perpetual diff:
        # https://github.com/hashicorp/terraform-provider-kubernetes/pull/2380
        toleration {
          effect   = "NoSchedule"
          key      = "kubernetes.io/arch"
          operator = "Equal"
          value    = "amd64"
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "default" {
  metadata {
    name = "web-app-loadbalancer"
  }

  spec {
    selector = {
      app = kubernetes_deployment_v1.default.spec[0].selector[0].match_labels.app
    }

    ip_family_policy = "RequireDualStack"

    port {
      port        = 80
      target_port = kubernetes_deployment_v1.default.spec[0].template[0].spec[0].container[0].port[0].name
    }

    type = "LoadBalancer"
  }

  depends_on = [time_sleep.wait_service_cleanup]
}

##    KUBERNETES DATABASE ##

# Persistent Volume Claim
resource "kubernetes_persistent_volume_claim" "db_pvc" {
  metadata {
    name      = "db-pvc"
    namespace = "default"
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

# StatefulSet for a sample database (e.g., PostgreSQL)
resource "kubernetes_stateful_set" "db" {
  metadata {
    name      = "postgres-db"
    namespace = "default"
  }

  spec {
    service_name = "postgres-db"
    replicas     = var.db_replicas

    selector {
      match_labels = {
        app = "postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:15"

          port {
            container_port = 5432
          }

          env {
            name  = "POSTGRES_USER"
            value = var.db_admin
          }

          env {
            name  = "POSTGRES_PASSWORD"
            value = var.db_password
          }

          volume_mount {
            mount_path = "/var/lib/postgresql/data"
            name       = "postgres-storage"
          }
        }

        volume {
          name = "postgres-storage"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.db_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "postgres"
    }

    port {
      port        = 5432
      target_port = 5432
    }

    cluster_ip = "None" # This makes it a headless service for StatefulSet
  }
}


# Provide time for Service cleanup
resource "time_sleep" "wait_service_cleanup" {
  depends_on = [google_container_cluster.default]

  destroy_duration = "180s"
}