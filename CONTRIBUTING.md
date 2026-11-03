# Contributing to MOSIP Rapid Deployment

Thank you for helping make MOSIP easier to deploy. Bug reports, fixes, docs and new cloud or data-centre support are all welcome.

## Ways to contribute
- **Ask or share:** [GitHub Discussions](https://github.com/mosip/infra/discussions) or the [MOSIP Community](https://community.mosip.io).
- **Report a bug or request a feature:** open an [issue](https://github.com/mosip/infra/issues/new/choose) with the workflow, profile and log excerpt.
- **Security issues:** do **not** open a public issue. See [SECURITY.md](SECURITY.md).
- **Code and docs:** pull requests, as described below.

## Pull request flow
1. Fork the repository and create a branch from `develop` (or from the feature branch named in the issue).
2. Keep each PR to one topic and reference its issue (`Part of #NNN` / `Closes #NNN`).
3. **Sign off every commit** (Developer Certificate of Origin; the DCO check blocks unsigned commits):
   ```bash
   git commit -s -m "fix(dns): ..."
   ```
   The `Signed-off-by` name and email must match the commit author.
4. Describe in the PR **what changed, why, and how you verified it** (plan output, test run, workflow run).

## Ground rules for this repository
- **New behaviour is opt-in.** With existing tfvars, the Terraform plan must stay identical; add new keys with defaults that keep today's behaviour.
- **No real environment values.** Commit placeholders only (`<cluster-name>`, `<route53_zone_id>`, ...), never state files, `backend.tf`, plans, keys or secrets.
- **Workflows:** pass inputs through `env:` (not `${{ }}` inside `run:`), use least-privilege `permissions:`, and pin actions to a commit SHA.

## Checks to run before opening a PR
```bash
terraform fmt -check -recursive terraform
# in each changed module / root that has tests
terraform init -backend=false && terraform test
actionlint .github/workflows/*.yml
shellcheck .github/scripts/*.sh
# changed a workflow's inputs? regenerate the docs form images
python .github/mkdocs/render_workflow_forms.py
# changed docs? strict site build
pip install -r docs/requirements.txt && mkdocs build --strict
```
The same checks run in CI (`infra checks`, `docs`). The workflow form images in `docs/_images/workflows/` are generated — see [Workflow form images](.github/workflows/README.md#workflow-form-images-docs).

## License
By contributing, you agree that your contributions are licensed under the [Mozilla Public License 2.0](LICENSE).
