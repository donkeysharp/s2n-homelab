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

```bash
ansible-playbook playbooks/base-setup.yml -e "ansible_user=<YOUR_INSTALLATION_USER>" -e "ansible_ssh_common_args='-o PreferredAuthentications=password -o PubkeyAuthentication=no'" --ask-pass --ask-become-pass
```

### Installing requirements
```bash
ansible-playbook install -r requirements.yml
```

### Install k3s
```bash
ansible-playbook -i inventory/hosts.yml --vault-password-file .vault-password playbooks/k3s_cluster.yml
```

### Uninstall k3s
```bash
ansible-playbook -i inventory/hosts.yml --vault-password-file .vault-password playbooks/k3s_reset.yml
```

### Run the common setup playbook
```bash
ansible-playbook  playbooks/homelab.yml
```

### Run database playbook
```bash
ansible-playbook --vault-password-file .vault-password playbooks/database.yml
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
### Create vault secrets
```bash
ansible-vault encrypt_string --vault-password-file .vault-password "secret" --name secret_name

secret_name: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          61336330623430353435626532333037316363623938376566346235393362616362646332396135
          3166656135653565653533376332366237363830316431340a316265346334646566613462313532
          61313363366363623636353666626539303030616464613033623337626536663965326164353730
          3139643537353230640a383931623064663665363865663764666565336136373763333336386439
          6362
```

### Run Specific commands
```bash
ansible agent -b -m command -a whoami
ansible k3s_cluster -b -m command -a whoami
ansible database -b -m command -a whoami
ansible agent -b -m command -a whoami
```


## Server organization
Here are the servers:
- `frodo`
  - labels: architecture=x86_64 brand=gmk
- `samwise`
  - labels: architecture=x86_64 brand=gmk
- `aragorn`
  - labels: architecture=arm brand=rpi3b
- `legolas`
  - labels: architecture=arm brand=rpi3b
- `gimli`
  - labels: architecture=arm brand=rpi3b
- `pippin`
  - labels: architecture=arm brand=rpi3b
- `merry`
  - labels: architecture=arm brand=rpi3b
- `galadriel`
  - labels: architecture=x86_64 brand=dell
- `elrond`
  - labels: architecture=x86_64 brand=dell
- `arwen`
  - labels: architecture=x86_64 brand=dell
