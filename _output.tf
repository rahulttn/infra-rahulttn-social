output "core-service-role" {
  value = aws_iam_role.instance.arn
}
output "shared-apps-helm-integration-role" {
    value =   module.secrets-store-csi.iam_role_arn
}
output "elasticsearch_ip_addr" {
  value = join(":",[aws_instance.elastic_nodes.private_ip,"9200"])
}
output "kibana_ip_addr" {
  value = join(":",[aws_instance.kibana.private_ip,"5601"])
}