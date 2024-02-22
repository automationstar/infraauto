# Terraform for Azure Kubernetes Service

This module simplifies deploying Azure Kubernetes Service (AKS) using Terraform, promoting best practices in infrastructure automation. It includes creating storage accounts for Terraform state and modular Azure AKS configurations.

> Note: A GitHub actions template for private repositories is also included.

## Maintainer
- **Name:** Datta Attili
- **GitHub:** [automationstar](https://github.com/automationstar)
- **Email:** [chaitanya6153@gmail.com](mailto:chaitanya6153@gmail.com)

## Security Controls
We've achieved Authority to Operate, sharing documentation on operations, security controls, CIS benchmarks, and assessments.

## Workflow
Steps include exporting `ARM_ACCESS_KEY`, initializing Terraform with backend configurations, planning, and applying configurations incrementally.

## Usage
Example usage with variables for AKS deployment, including Kubernetes version, node size, and VM sizes.

## Variables Values
Detailed variable descriptions, including prefixes, environment names, Kubernetes settings, and network configurations.

## Contributing
Contributions are welcome! Please submit pull requests or report issues through GitHub.

## History
Changelog with dates and descriptions of major updates to the AKS cluster specification.

---

This guide incorporates insights from our discussion on adopting the latest Terraform Azure provider versions, using managed identities, and leveraging Terraform modules for efficient infrastructure management.
