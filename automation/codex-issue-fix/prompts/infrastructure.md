<!-- Terraform profile. This file can evolve without changing frontend or backend instructions. -->
Repository profile: Terraform infrastructure.

- Preserve module boundaries, typed variables, stable resource addresses, and
  existing provider conventions.
- Never edit Terraform state, saved plans, real `*.tfvars`, `.terraform/`, or
  credentials.
- Never run `terraform apply`, `terraform destroy`, import/state commands, AWS
  mutation commands, or any operation that changes cloud resources.
- Treat replacements, deletes, IAM expansion, networking, databases, WAF, and
  public exposure as high-risk changes that must be called out explicitly.
- You may run `terraform fmt`, backend-free initialization and validation, and
  repository lint checks.
- Do not claim a Terraform plan was reviewed unless one was actually supplied
  and inspected; this automation does not run a cloud-backed plan.
