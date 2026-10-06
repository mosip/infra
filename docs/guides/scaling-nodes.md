# Add or remove nodes

Existing nodes are never touched when you add one: Terraform keys nodes by name, and the RKE2
setup skips nodes that already run RKE2.

## Add nodes

=== "AWS"

    1. Raise the count in `profiles/<profile>/aws/compute.tfvars`:

        ```hcl
        k8s_worker_node_count = 3   # was 1
        ```

    2. Run **terraform plan / apply** with `COMPONENT=compute`, `TERRAFORM_APPLY` ✅.
       The plan shows **only the new instances**.
    3. Run `COMPONENT=configure`. The new nodes install RKE2 and join; nginx picks up their IPs.

=== "Data centre"

    1. **Append** the new addresses to `my-hosts.yml` (`workers:`, `etcd:` or `control_plane:`).
    2. Regenerate the inventory and run:

        ```bash
        python3 ansible/inventory/generate.py --profile profiles/mosip --from-hosts my-hosts.yml -o inventory.yml
        ansible-playbook -i inventory.yml ansible/playbooks/rke2.yml
        ansible-playbook -i inventory.yml ansible/playbooks/nginx.yml
        ```

!!! warning "Control-plane and etcd"
    Keep **odd** counts (1 → 3, not 2) for etcd quorum, and never change which node is listed
    first — it is the RKE2 primary.

## Verify

```bash
kubectl get nodes -o wide     # new nodes Ready
```

## Remove nodes

Removing is not graceful on its own — drain the node first.

1. Drain and delete it from Kubernetes:

    ```bash
    kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
    kubectl delete node <node>
    ```

    For control-plane or etcd nodes, also remove the etcd member first.

2. Then remove the machine:
    - **AWS** — lower the count and run `COMPONENT=compute`. Terraform removes the
      highest-numbered node of that role.
    - **Data centre** — remove the address from `my-hosts.yml` and decommission the VM.

**Related:** [Concepts](../overview/concepts.md) · [Workflow inputs](../reference/workflow-inputs.md)
