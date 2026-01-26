output "karpenter_installed" {
  description = "Karpenter installation status"
  value       = "Karpenter ${helm_release.karpenter.version} installed in namespace ${local.karpenter_namespace}"
}
