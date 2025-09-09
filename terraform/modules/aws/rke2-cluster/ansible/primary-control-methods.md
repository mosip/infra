# Primary Control Plane Selection - Complete Guide

You asked a great question! **Yes, you can absolutely control which IP becomes the primary control plane** using the `rke-user-data.sh.tpl` template and several other methods.

## 🎯 How It Currently Works

### **Instance Creation Flow:**
```
aws-resource-creation-main.tf
├── Creates instances with names: "CONTROL-PLANE-NODE-1", "CONTROL-PLANE-NODE-2", etc.
├── Passes to user-data template:
│   ├── role = "CONTROL-PLANE-NODE-1" (idx=0)
│   ├── role = "CONTROL-PLANE-NODE-2" (idx=1)
│   └── index = 0, 1, 2, etc.
└── rke-user-data.sh.tpl sets NODE_NAME=${role}

Ansible Selection:
├── Sorts nodes alphabetically by name
├── "CONTROL-PLANE-NODE-1" becomes primary (first in sort)
└── Others become subsequent
```

## 🔧 Methods to Control Primary Selection

### **Method 1: Node Naming (Default - Now Enhanced)**

**Current Logic:** `CONTROL-PLANE-NODE-1` is always primary

**Enhanced User-Data Template** (just implemented):
```bash
# In rke-user-data.sh.tpl
if [[ "${role}" == "CONTROL-PLANE-NODE-1" ]]; then
  echo "export IS_PRIMARY_CONTROL_PLANE=true" | sudo tee -a $ENV_FILE_PATH
  echo "This node is designated as PRIMARY CONTROL PLANE"
else
  echo "export IS_PRIMARY_CONTROL_PLANE=false" | sudo tee -a $ENV_FILE_PATH
  echo "This node is designated as SUBSEQUENT CONTROL PLANE"
fi
```

### **Method 2: By Specific IP Address**

**Use Case:** You want a specific IP to always be primary

**In `rke-user-data.sh.tpl`** (uncomment the IP option):
```bash
# Uncomment this section in the template:
if [[ "$INTERNAL_IP" == "10.0.1.10" ]]; then
  echo "export IS_PRIMARY_CONTROL_PLANE=true" | sudo tee -a $ENV_FILE_PATH
  echo "This node is designated as PRIMARY CONTROL PLANE (by IP)"
else
  echo "export IS_PRIMARY_CONTROL_PLANE=false" | sudo tee -a $ENV_FILE_PATH
  echo "This node is designated as SUBSEQUENT CONTROL PLANE (by IP)"
fi
```

### **Method 3: By Index/Position**

**Use Case:** You want the first created instance to be primary

**In `rke-user-data.sh.tpl`** (uncomment the index option):
```bash
# Uncomment this section in the template:
if [[ "${index}" == "0" ]]; then
  echo "export IS_PRIMARY_CONTROL_PLANE=true" | sudo tee -a $ENV_FILE_PATH
  echo "This node is designated as PRIMARY CONTROL PLANE (by index)"
else
  echo "export IS_PRIMARY_CONTROL_PLANE=false" | sudo tee -a $ENV_FILE_PATH
  echo "This node is designated as SUBSEQUENT CONTROL PLANE (by index)"
fi
```

### **Method 4: By Subnet/AZ Logic**

**Use Case:** You want primary in a specific availability zone

**Modify the template to add AZ logic:**
```bash
# Get AZ info
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

# Make primary based on AZ
if [[ "$AZ" == "ap-south-1a" ]] && [[ "${role}" == CONTROL-PLANE-NODE-* ]]; then
  echo "export IS_PRIMARY_CONTROL_PLANE=true" | sudo tee -a $ENV_FILE_PATH
  echo "This node is PRIMARY (in preferred AZ: $AZ)"
else
  echo "export IS_PRIMARY_CONTROL_PLANE=false" | sudo tee -a $ENV_FILE_PATH
  echo "This node is SUBSEQUENT (AZ: $AZ)"
fi
```

### **Method 5: Custom Terraform Logic**

**Use Case:** You want complex logic in Terraform itself

**Modify the main.tf to override selection:**
```hcl
# In modules/aws/rke2-cluster/main.tf
locals {
  # Custom primary selection logic
  custom_primary_ip = "10.0.1.15"  # Your desired primary IP
  
  # Reorder control plane IPs to put desired primary first
  control_plane_ips_reordered = concat(
    [local.custom_primary_ip],
    [
      for key, value in var.K8S_CLUSTER_PRIVATE_IPS : value 
      if length(regexall(".*CONTROL-PLANE-NODE.*", key)) > 0 && value != local.custom_primary_ip
    ]
  )
}
```

## 🔍 How to Verify Your Selection

### **Check User-Data Logs:**
```bash
# SSH to any control plane node
sudo tail -f /tmp/k8s-userdata-*.log | grep PRIMARY
```

### **Check Environment Variables:**
```bash
# On each control plane node
grep IS_PRIMARY_CONTROL_PLANE /etc/environment
```

### **Check Terraform Outputs:**
```bash
terraform output PRIMARY_CONTROL_PLANE_IP
terraform output CONTROL_PLANE_SELECTION_ORDER
```

### **Check Ansible Inventory:**
```bash
cat terraform/modules/aws/rke2-cluster/ansible/inventory.yml | grep -A3 is_primary
```

## 📊 Examples

### **Example 1: Default Behavior**
```yaml
# Current: NODE-1 is always primary
control_plane:
  hosts:
    abc123-CONTROL-PLANE-NODE-1:
      ansible_host: 10.0.1.10
      is_primary: "true"    ← PRIMARY
    abc123-CONTROL-PLANE-NODE-2:
      ansible_host: 10.0.1.11  
      is_primary: "false"   ← Subsequent
```

### **Example 2: IP-Based Selection**
```bash
# If you set custom IP logic in user-data:
# 10.0.1.15 becomes primary regardless of node name
# User-data will set IS_PRIMARY_CONTROL_PLANE=true on that IP
```

### **Example 3: AZ-Based Selection**
```bash
# Node in ap-south-1a becomes primary
# Others become subsequent regardless of naming
```

## 🎯 Recommended Approach

For your use case, I recommend using **Method 1 (Enhanced Node Naming)** because:

1. ✅ **Predictable**: NODE-1 is always primary
2. ✅ **Simple**: No complex IP logic needed  
3. ✅ **Debuggable**: Easy to identify in logs
4. ✅ **AWS-agnostic**: Works regardless of IP assignment
5. ✅ **Already implemented**: Just updated your template!

## 🚀 Next Steps

1. **Run terraform apply** - The enhanced template is now in place
2. **Check logs** to see primary selection working
3. **Verify with outputs** to confirm correct selection
4. **If needed**, modify the template to use one of the alternative methods

The key insight is that **yes, you absolutely can control primary selection** using the user-data template, and you now have multiple methods to do so depending on your specific requirements!
