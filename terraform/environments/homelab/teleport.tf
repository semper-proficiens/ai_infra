# SSH access role — allows login as root to all nodes
resource "teleport_role" "infra_access" {
  metadata {
    name        = "infra-access"
    description = "SSH access to all infra nodes"
  }

  spec {
    allow {
      logins      = ["root"]
      node_labels = { "*" = ["*"] }
    }
  }
}

# kubectl exec role for k3s cluster
resource "teleport_role" "k8s_access" {
  metadata {
    name        = "k8s-access"
    description = "kubectl exec access to k3s cluster"
  }

  spec {
    allow {
      kubernetes_groups    = ["system:masters"]
      kubernetes_resources {
        kind      = "pod"
        namespace = "*"
        name      = "*"
        verbs     = ["get", "list", "exec"]
      }
    }
  }
}

# Provision token for VM nodes (long-lived, managed by Terraform)
resource "teleport_provision_token" "vm_nodes" {
  metadata {
    name    = "tf-vm-nodes"
    expires = timeadd(timestamp(), "87600h") # 10 years
  }

  spec {
    roles       = ["Node"]
    join_method = "token"
  }

  lifecycle {
    ignore_changes = [metadata[0].expires]
  }
}

# Provision token for LXC nodes (long-lived, managed by Terraform)
resource "teleport_provision_token" "lxc_nodes" {
  metadata {
    name    = "tf-lxc-nodes"
    expires = timeadd(timestamp(), "87600h") # 10 years
  }

  spec {
    roles       = ["Node"]
    join_method = "token"
  }

  lifecycle {
    ignore_changes = [metadata[0].expires]
  }
}

# Machine ID bot for automated script access (k3sup, CI/CD)
resource "teleport_bot" "infra_bot" {
  name  = "infra-bot"
  roles = [teleport_role.infra_access.metadata[0].name]
}
