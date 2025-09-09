# Primary Control Plane Selection Guide

## 🎯 How Primary Control Plane is Determined

### **Current Logic (Deterministic)**

The primary control plane is selected using **alphabetical sorting** of node names:

```hcl
# Terraform sorts control plane nodes by name
control_plane_ips = [
  for key in sort([
    for k, v in var.K8S_CLUSTER_PRIVATE_IPS : k 
    if length(regexall(".*CONTROL-PLANE-NODE.*", k)) > 0
  ]) : var.K8S_CLUSTER_PRIVATE_IPS[key]
]
```

### **Selection Process:**

1. **Extract all control plane nodes** from `K8S_CLUSTER_PRIVATE_IPS`
2. **Sort node names alphabetically** (e.g., `CONTROL-PLANE-NODE-1`, `CONTROL-PLANE-NODE-2`)
3. **First in sorted order becomes primary**
4. **Rest become subsequent control planes**

## 📊 Examples

### **Example 1: Standard Naming**
```
Input:
├── test123-CONTROL-PLANE-NODE-3: 10.0.1.12
├── test123-CONTROL-PLANE-NODE-1: 10.0.1.10  
└── test123-CONTROL-PLANE-NODE-2: 10.0.1.11

After Sorting:
├── test123-CONTROL-PLANE-NODE-1: 10.0.1.10  ← PRIMARY
├── test123-CONTROL-PLANE-NODE-2: 10.0.1.11  ← Subsequent
└── test123-CONTROL-PLANE-NODE-3: 10.0.1.12  ← Subsequent
```

### **Example 2: Custom Naming**
```
Input:
├── prod-CONTROL-PLANE-NODE-main: 10.0.1.15
├── prod-CONTROL-PLANE-NODE-backup: 10.0.1.13
└── prod-CONTROL-PLANE-NODE-aux: 10.0.1.14

After Sorting (alphabetical):
├── prod-CONTROL-PLANE-NODE-aux: 10.0.1.14     ← PRIMARY (first alphabetically)
├── prod-CONTROL-PLANE-NODE-backup: 10.0.1.13  ← Subsequent
└── prod-CONTROL-PLANE-NODE-main: 10.0.1.15    ← Subsequent
```

## 🎛️ How to Control Primary Selection

### **Method 1: Use Node Naming (Recommended)**

Ensure your desired primary has the **first name alphabetically**:

```hcl
# In your terraform.tfvars or variables
# Name your nodes so the desired primary comes first alphabetically
cluster_name = "mycluster"

# This will create:
# mycluster-CONTROL-PLANE-NODE-1  ← Will be PRIMARY
# mycluster-CONTROL-PLANE-NODE-2  ← Subsequent
# mycluster-CONTROL-PLANE-NODE-3  ← Subsequent
```

### **Method 2: Modify Terraform Logic**

If you want a specific IP to always be primary, modify the main.tf:

```hcl
# Option A: Hardcode specific primary IP
control_plane_ips = concat(
  ["10.0.1.10"],  # Force this IP as primary
  [
    for key, value in var.K8S_CLUSTER_PRIVATE_IPS : value 
    if length(regexall(".*CONTROL-PLANE-NODE.*", key)) > 0 && value != "10.0.1.10"
  ]
)

# Option B: Use specific node name pattern
control_plane_ips = concat(
  # Always put NODE-1 first if it exists
  [
    for key, value in var.K8S_CLUSTER_PRIVATE_IPS : value 
    if key == "${var.cluster_name}-CONTROL-PLANE-NODE-1"
  ],
  # Then add all others
  [
    for key, value in var.K8S_CLUSTER_PRIVATE_IPS : value 
    if length(regexall(".*CONTROL-PLANE-NODE.*", key)) > 0 && 
       key != "${var.cluster_name}-CONTROL-PLANE-NODE-1"
  ]
)
```

## 🔍 How to Verify Primary Selection

### **Check Terraform Outputs:**
```bash
terraform output PRIMARY_CONTROL_PLANE_IP
terraform output CONTROL_PLANE_SELECTION_ORDER
```

### **Check Generated Inventory:**
```bash
cat terraform/modules/aws/rke2-cluster/ansible/inventory.yml
```

Look for:
```yaml
control_plane:
  hosts:
    cluster-CONTROL-PLANE-NODE-1:
      ansible_host: 10.0.1.10
      is_primary: "true"    ← This is the primary
    cluster-CONTROL-PLANE-NODE-2:
      ansible_host: 10.0.1.11
      is_primary: "false"   ← This is subsequent
```

### **Check Ansible Execution:**
```bash
# See which node runs first
grep "PRIMARY Control Plane" terraform/modules/aws/rke2-cluster/ansible/inventory.yml
```

## 🎯 Best Practices

### **1. Consistent Naming Convention**
```
✅ Good: cluster-CONTROL-PLANE-NODE-1, cluster-CONTROL-PLANE-NODE-2
❌ Avoid: cluster-CONTROL-PLANE-NODE-main, cluster-CONTROL-PLANE-NODE-backup
```

### **2. Use Lowest IP for Primary**
- AWS typically assigns IPs sequentially
- First subnet IP often becomes primary naturally

### **3. Document Your Choice**
```hcl
# In your terraform files
locals {
  # Primary control plane will be the first in alphabetical order
  # Currently: CONTROL-PLANE-NODE-1 with IP determined by AWS
}
```

## 🚨 Important Notes

1. **Primary runs first**: Only the primary control plane initializes the cluster
2. **Subsequent join**: All other nodes join the existing cluster  
3. **Order matters**: Primary must be ready before others can join
4. **Deterministic**: The same input always produces the same primary selection
5. **Change impact**: Changing primary selection requires cluster recreation

## 🔧 Troubleshooting

### **Wrong Node Selected as Primary?**
```bash
# 1. Check current selection
terraform output CONTROL_PLANE_SELECTION_ORDER

# 2. If needed, rename your nodes in terraform
# 3. Or use hardcoded IP method above

# 4. Recreate cluster
terraform destroy
terraform apply
```

### **Verify Primary is Working:**
```bash
# Test the selected primary
cd terraform/modules/aws/rke2-cluster/ansible
./test-cluster.sh
```

The primary control plane selection is now **deterministic and predictable** based on alphabetical sorting of node names.
