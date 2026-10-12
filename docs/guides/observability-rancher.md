# Observability cluster & Rancher

The `observ` profile builds a small management cluster with **Rancher UI** and **Keycloak**.
MOSIP clusters can then be imported into that Rancher for central management.

## 1. Deploy the observability cluster

Deploy it **before** the clusters that will import into it.

1. Set the **`RANCHER_BOOTSTRAP_PASSWORD`** environment secret — the initial Rancher `admin`
   password. (It is no longer kept in a tfvars file.)
2. Fill in `profiles/observ/aws/common.tfvars` (its own `cluster_name` and domain, e.g.
   `soil38-observ.mosip.net`).
3. Run **terraform plan / apply** with `COMPONENT=all`, `PROFILE=observ`, `TERRAFORM_APPLY` ✅.

Result: a one-node cluster with Rancher at `rancher.<domain>` and Keycloak at `iam.<domain>`.

## 2. First login to Rancher

1. Open `https://rancher.<domain>`.
2. Log in with the bootstrap password, set a new strong password, accept the terms.

## 3. Connect Keycloak to Rancher (SAML)

Run the Keycloak ⇄ Rancher integration workflow so operators log in to Rancher through Keycloak —
see the [Rancher–Keycloak integration guide](https://github.com/mosip/infra/blob/develop/Rancher-keycloak-integration/README.md).

## 4. Import MOSIP clusters

When deploying a MOSIP cluster, tick **`ENABLE_RANCHER_IMPORT`** (secrets `RANCHER_API_URL`,
`RANCHER_API_TOKEN`). The workflow:

1. registers the cluster in Rancher through the API,
2. applies the import on the cluster (with a fresh token after setup),
3. grants team access (`GRANT_GROUP_ACCESS`, `RANCHER_CLUSTER_OWNER_GROUP*`),
4. with `PUBLISH_KUBECONFIG`, stores the kubeconfig as the `KUBECONFIG` environment secret.

No import URL goes into tfvars.

=== "Data centre"

    Pass the import command yourself:

    ```bash
    ansible-playbook -i inventory.yml ansible/site.yml \
      -e enable_rancher_import=true \
      -e "rancher_import_url='kubectl apply -f https://rancher.example.org/v3/import/<token>.yaml'"
    ```

    Get the command in Rancher → Cluster Management → Import Existing → Generic.

## Verify

- Rancher → Cluster Management: the cluster shows **Active**.
- If not: `kubectl get pods -n cattle-system` and check the cluster can reach the Rancher URL.
