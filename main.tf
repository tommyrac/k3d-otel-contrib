terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "k3d-otest"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "k3d-otest"
  }
}

resource "null_resource" "create_k3d_cluster" {
  provisioner "local-exec" {
    command = "k3d cluster create otest --agents 3"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "helm_release" "cert_manager" {
  depends_on       = [null_resource.create_k3d_cluster]
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.17.2"

  set {
    name  = "installCRDs"
    value = "true"
  }

  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "helm_release" "otel_operator" {
  depends_on       = [null_resource.create_k3d_cluster, helm_release.cert_manager]
  name             = "opentelemetry-operator"
  namespace        = "opentelemetry-operator-system"
  create_namespace = true

  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-operator"
  version    = "0.90.03"

  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "null_resource" "apply_manifests" {
  depends_on = [null_resource.create_k3d_cluster]

  provisioner "local-exec" {
    command = <<EOT
      kubectl apply -f manifests/nginx.yaml
      kubectl apply -f manifests/redis.yaml
      kubectl apply -f manifests/redis-exporter.yaml
      kubectl apply -f manifests/redis-exporter-service.yaml
      kubectl apply -f manifests/nginx-exporter-service.yaml
    EOT
  }
}

resource "null_resource" "wait_for_crds" {
  depends_on = [helm_release.otel_operator]

  provisioner "local-exec" {
    command = "sleep 5"  # Wait for CRDs to be installed
  }
}

resource "null_resource" "otel_collector" {
  depends_on = [null_resource.wait_for_crds]

  provisioner "local-exec" {
    command = "kubectl apply -f manifests/otel-collector.yaml"
  }
}

resource "null_resource" "delete_k3d_cluster" {
  depends_on = [helm_release.otel_operator, helm_release.cert_manager]
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete otest"
  }
}
