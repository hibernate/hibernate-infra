output "vpc_id" {
  value = module.vpc.vpc_id
}

output "runner_group_name" {
  value = github_actions_runner_group.runs_on.name
}
