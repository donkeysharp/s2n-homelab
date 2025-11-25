S2N Homelab Ansible Configuration
===

> **Quiz:**
> - Guess why s2n?
> - Why all LotR characters?

Ansible configuration for managing the S2N homelab datacenter infrastructure.

## Prerequisites
- Ansible 2.9 or higher
- SSH access to all hosts
- Sudo privileges on target hosts
- `sshpass` installed on your computer

## Configuration
### Update Inventory
Edit `inventory/hosts.yml` and update:
- IP addresses for your servers
- Hostnames
- SSH usernames

### Customize Packages
To modify the package list, edit `roles/common/defaults/main.yml` or override in `group_vars/all.yml`:

Example:
```yaml
common_packages:
  - htop
  - vim
  - curl
  - lm-sensors
  - tmux
  # Add your packages here
```

## Usage
### First time setup
Execute this **only the first time**, so that servers have the minimum connection settings:

```sh
ansible-playbook playbooks/base-setup.yml -e "ansible_user=<YOUR_INSTALLATION_USER>" -e "ansible_ssh_common_args='-o PreferredAuthentications=password -o PubkeyAuthentication=no'" --ask-pass --ask-become-pass
```

### Run the main playbook
```bash
ansible-playbook playbooks/homelab.yml
```

### Run against specific host groups
```bash
# Only x86_64 servers
ansible-playbook playbooks/homelab.yml --limit x86_64

# Only Raspberry Pi servers
ansible-playbook playbooks/homelab.yml --limit raspberry_pi

# Single host
ansible-playbook playbooks/homelab.yml --limit frodo
```

### Dry run (check mode)
```bash
ansible-playbook playbooks/homelab.yml --check
```

### Run with verbose output
```bash
ansible-playbook playbooks/homelab.yml -v
```
