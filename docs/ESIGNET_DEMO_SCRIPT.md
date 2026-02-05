# eSignet Deployment Demo - 5 Minute Talk

## Introduction (30 seconds)

"Today I'll show you how we deploy eSignet using Helmsman - an automated deployment tool that makes our infrastructure setup fast, reliable, and repeatable."

**What is eSignet?**
- eSignet is an authentication system - like a digital ID card system
- It helps users prove who they are securely online
- Used for government services, banking, and other secure applications

---

## What is Helmsman? (1 minute)

"Helmsman is our deployment automation tool. Think of it like a recipe book for deploying applications."

**Key Benefits:**
1. **Automated** - One command deploys everything
2. **Repeatable** - Same result every time
3. **Version Controlled** - All configuration is in Git
4. **Safe** - Built-in checks before deployment

**How it works:**
- We write YAML files describing what to deploy
- Helmsman reads these files and executes the deployment
- Pre-install and post-install hooks handle setup tasks automatically

---

## eSignet Deployment Architecture (1.5 minutes)

"Our eSignet deployment has 4 main stages:"

### Stage 1: Prerequisites
- Config Server - stores all configuration
- Keycloak - manages user authentication
- Databases - stores data
- S3 Storage - for files

### Stage 2: Pre-Install Setup (esignet-preinstall.sh)
- Creates secrets for security (captcha keys, MISP keys)
- Copies secrets to config-server
- Updates config-server with environment variables
- Waits for config-server to restart

### Stage 3: Main Deployment
- Deploys eSignet services
- Sets up mock services for testing
- Configures API gateways

### Stage 4: Post-Install Setup
- Runs partner onboarding jobs
- Configures client credentials
- Updates mock services with real client IDs
- Validates deployment

---

## Live Demo Flow (1.5 minutes)

**Step 1: Show the Helmsman DSF file**
```
"This is our deployment recipe - see how clean and simple it is?"
- Point to esignet-dsf.yaml
- Show app definitions
- Highlight pre-install and post-install hooks
```

**Step 2: Run the deployment**
```bash
helmsman -f esignet-dsf.yaml --apply
```
"Watch how it automatically:
1. Checks prerequisites
2. Runs pre-install setup
3. Deploys all services
4. Runs post-install configuration"

**Step 3: Show the results**
```bash
kubectl get pods -n esignet
```
"In about 25 minutes, everything is deployed and running!"

---

## Key Features We Built (30 seconds)

**Smart Waiting:**
- We don't use slow rollout status checks
- Instead, we track deployment generations
- Scripts wait for actual new pods, not old ones

**Idempotent Scripts:**
- Can run multiple times safely
- Won't duplicate work or break existing setup
- Perfect for automation

**Error Handling:**
- Validates secrets exist before proceeding
- Clear error messages if something fails
- Easy to debug and fix

---

## Results & Benefits (30 seconds)

**Before Helmsman:**
- Manual deployment took hours
- Many manual steps = human errors
- Hard to reproduce exactly

**After Helmsman:**
- Automated deployment in ~25 minutes
- Zero manual intervention
- Same result every time
- Easy to deploy to multiple environments

**Next Steps:**
- Further optimization to reduce to <20 minutes
- Add more automated tests
- Expand to other MOSIP modules

---

## Q&A Preparation

**Common Questions:**

Q: "What if deployment fails halfway?"
A: "Helmsman is idempotent - just fix the issue and re-run. It picks up where it left off."

Q: "How do you handle secrets?"
A: "All secrets are stored in GitHub Secrets and injected at deployment time. Never in Git."

Q: "Can you deploy to different environments?"
A: "Yes! Just change the kubeconfig and run the same command. Dev, staging, production - all identical."

Q: "How long did this take to build?"
A: "We iterated over several weeks, optimizing wait times and fixing edge cases. Now it's rock solid."

---

## Demo Script (Word-for-word 5 minutes)

"Good morning everyone. Today I want to show you how we automated eSignet deployment using Helmsman.

eSignet is our authentication system - think of it as a secure digital ID system. Previously, deploying it took hours of manual work. Now, with Helmsman, it's one command and 25 minutes.

Let me show you how it works.

[SHOW SCREEN: esignet-dsf.yaml]

This is our Helmsman deployment file. It's like a recipe - it tells Helmsman exactly what to deploy and in what order. See these sections? Prerequisites, main apps, and hooks for setup tasks.

The magic happens in these hooks - pre-install and post-install scripts. They handle all the complex setup automatically.

[SHOW SCREEN: esignet-preinstall.sh highlights]

The pre-install script creates security secrets, copies them to the right places, and configures our config-server. It's smart - it checks if work is already done and skips it. This means we can run it multiple times safely.

[SHOW SCREEN: Terminal]

Now let me show you it in action. One command:

helmsman -f esignet-dsf.yaml --apply

[RUN COMMAND - let it start]

Watch the output - it's checking prerequisites, running pre-install setup, deploying services. All automatically.

[SHOW SCREEN: Kubernetes pods appearing]

Here you can see pods starting up. eSignet services, mock services for testing, everything we need.

[SHOW SCREEN: Post-install logs]

After deployment, post-install hooks run. They onboard partners, generate client credentials, and configure everything end-to-end.

The best part? This entire process is:
- Repeatable - same result every time
- Version controlled - all in Git
- Automated - zero manual steps
- Fast - 25 minutes from zero to fully running

Before Helmsman, this was hours of error-prone manual work. Now our team can deploy to dev, staging, and production with confidence.

We're still optimizing - our goal is under 20 minutes. But even now, this has transformed how we work.

Any questions?"

---

## Tips for Delivery

1. **Keep it moving** - don't get stuck on technical details
2. **Show, don't tell** - terminal output is more convincing than words
3. **Highlight the benefit** - always tie back to time/effort saved
4. **Have a backup** - pre-record the deployment if live demo might fail
5. **Practice timing** - 5 minutes goes fast, stick to the script
