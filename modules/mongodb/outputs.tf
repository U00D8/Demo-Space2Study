output "project_id" {
  description = "MongoDB Atlas Project ID"
  value       = mongodbatlas_project.main.id
}

output "cluster_id" {
  description = "MongoDB Atlas Cluster ID"
  value       = mongodbatlas_cluster.main.id
}

output "cluster_name" {
  description = "MongoDB Atlas Cluster name"
  value       = mongodbatlas_cluster.main.name
}

output "cluster_connection_string" {
  description = "MongoDB Atlas Cluster connection string (standard)"
  value       = mongodbatlas_cluster.main.connection_strings[0].standard
  sensitive   = true
}

output "cluster_connection_string_srv" {
  description = "MongoDB Atlas Cluster connection string (SRV)"
  value       = mongodbatlas_cluster.main.connection_strings[0].standard_srv
  sensitive   = true
}

output "database_username" {
  description = "Database username"
  value       = mongodbatlas_database_user.main.username
}

output "database_name" {
  description = "Database name"
  value       = var.database_name
}

output "srv_connection_string_app" {
  description = "Connection string for application (SRV format with database name)"
  value       = "mongodb+srv://${mongodbatlas_database_user.main.username}:${mongodbatlas_database_user.main.password}@${trimsuffix(substr(mongodbatlas_cluster.main.connection_strings[0].standard_srv, 14, -1), "/")}/${var.database_name}?retryWrites=true&w=majority"
  sensitive   = true
}
