# Kubernetes assets (kubeconfig, manifests)

# Defining the module from which we'll get our config and manifest files

module "bootstrap" {
  source = "git::https://github.com/poseidon/terraform-render-bootstrap.git?ref=44315b8c02eb73b8da762ac4a4894fce77ae00d2"

  cluster_name                    = var.cluster_name
  api_servers                     = [var.k8s_domain_name]
  etcd_servers                    = var.controllers.*.domain
  networking                      = var.networking
  network_mtu                     = var.network_mtu
  network_ip_autodetection_method = var.network_ip_autodetection_method
  pod_cidr                        = var.pod_cidr
  service_cidr                    = var.service_cidr
  cluster_domain_suffix           = var.cluster_domain_suffix
  enable_reporting                = var.enable_reporting
  enable_aggregation              = var.enable_aggregation
}

# GKE autopiloted cluster definition

resource "google_container_cluster" "bootstrap" {
  name             = "bootstrap-${var.cluster_name}"
  location         = "us-west1"
  enable_autopilot = true
  networking_mode  = "VPC_NATIVE"

  binary_authorization {
    evaluation_mode = "DISABLED"
  }
  ip_allocation_policy {}
}

data "google_client_config" "default" {}

# Kubernetes provider list (one per region)

provider "kubernetes" {
  alias = "bootstrap-typhoon"
  # config_path = module.bootstrap.assets_dist.kubeconfig-bootstrap
  host                   = "https://${google_container_cluster.bootstrap.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.bootstrap.master_auth[0].cluster_ca_certificate)
}

# End of kubernetes provider list
# Kubernetes manifests list

resource "kubernetes_manifest" "static" {
  for_each = toset(module.bootstrap.assets_dist.static_manifests)
  manifest = yamldecode(each.value)
}

resource "kubernetes_manifest" "basic" {
  for_each = toset(module.bootstrap.assets_dist.manifests)
  manifest = yamldecode(each.value)
}

resource "kubernetes_manifest" "network" {
  for_each = toset((var.networking == "cilium") ? module.bootstrap.assets_dist.cilium_manifests : (var.networking == "flannel" ? module.bootstrap.assets_dist.flannel_manifests : module.bootstrap.assets_dist.calico_manifests))
  manifest = yamldecode(each.value)
}

# End of kubernetes manifests list
# Beginning of kubernetes config yaml list

# resource "kubernetes_config_map" "adm" {
#   metadata {
#     name = "${var.cluster_name}-cluster"
#   }
#   data = {
#     "kubeconfig-admin" = yamldecode(module.bootstrap.assets_dist.kubeconfig-admin)
#   }
# }

resource "kubernetes_config_map" "bootstrap" {
  metadata {
    name = "${var.cluster_name}-cluster"
  }
  data = {
    "kubeconfig-bootstrap" = yamldecode(module.bootstrap.assets_dist.kubeconfig-bootstrap)
  }
}

# End of kubernetes config yaml list
