# Infrastructure Automation with Terraform for Azure Kubernetes Service

This repository is dedicated to Terraform modules for Infrastructure as Code (IaC), focusing on automating the deployment of Azure Kubernetes Service (AKS) and its related resources. Our modules are designed to provide a customizable and modular approach to deploying AKS, ensuring best practices for security, scalability, and maintainability.

## Overview

The `infraauto` project encompasses a wide range of Terraform configurations, aiming to automate the setup of:
- Azure Container Registry (ACR) for Docker container management.
- AKS for managing Kubernetes services in Azure.
- Azure Active Directory integrations for secure identity and access management.
- Azure Key Vault for managing secrets and certificates.
- Log Analytics for monitoring and analytics.
- Networking resources including virtual networks and subnets for AKS.

## Getting Started

1. **Prerequisites**: Ensure you have the Azure CLI and Terraform installed and configured.
2. **Clone the repository**: `git clone https://github.com/your-repository/infraauto.git`
3. **Initialize Terraform**: Navigate to the specific module directory (e.g., `AKS-TF-Kubernetes`) and run `terraform init`.

## Modules and Resources

### AKS-TF-Kubernetes
Contains the core Terraform configurations for deploying AKS, including:
- ACR configuration (`acr.tf`)
- AKS cluster setup (`aks.tf`)
- Azure Active Directory setup (`azuread.tf`)
- Key Vault and Log Analytics configurations

### Resources
Focuses on additional infrastructure components:
- Active Directory configurations
- Networking and firewall setups
- Identity management

## Security and Compliance

Refer to the `SECURITY.md` for detailed information on security controls, CIS benchmarks, and compliance documentation supporting our Authority to Operate (ATO).

## Contributing

Contributions to the `infraauto` project are welcome! Please refer to the contributing guidelines outlined in the `README.md` within each module directory.

## Contact

For any queries or contributions, please contact the project maintainer:
- **Name:** Datta Chaitanya Attili
- **Email:** chaitanya6153@gmail.com
- **GitHub:** automationstar

## License

This project is licensed under the MIT License - see the `LICENSE.md` file for details.

## Acknowledgements

Thanks to all contributors and users of the `infraauto` project for your support and feedback.
