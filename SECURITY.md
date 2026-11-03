# Security Policy

## Reporting a vulnerability
Please **do not** report security vulnerabilities through public issues, discussions or pull requests.

Report them privately through GitHub: **Security → Report a vulnerability** on this repository ([direct link](https://github.com/mosip/infra/security/advisories/new)). If you cannot use GitHub, email **info@mosip.io** with "Security" in the subject.

Please include:
- the affected file, workflow or profile, and the branch or release;
- steps to reproduce, and the impact you expect;
- any suggested fix.

We will acknowledge your report, keep you informed while we investigate, and credit you in the advisory unless you prefer otherwise.

## Scope
This repository contains deployment automation (Terraform, Ansible, GitHub workflows, Helmsman desired state files). For vulnerabilities in MOSIP services themselves, report them to the respective MOSIP repository the same way.

## Good practice for deployments
- Keep real values (domains, zone IDs, keys) in your fork's tfvars or GitHub Environment variables/secrets — never in pull requests to this repository.
- Restrict who can run the workflows, and scope secrets to GitHub Environments.
