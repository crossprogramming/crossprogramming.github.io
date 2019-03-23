---
layout: post
title: "Running Ansible Vault on Windows"
date: 2018-03-29 11:52:10 +0200
tags: [programming, ansible, ansible-vault, docker, docker-machine, hyper-v, boot2docker, windows]
---
- [Context](#context)
- [Prerequisites](#prerequisites)
- [Setup Ansible managed node using Docker Machine](#docker-machine)
- [Clone Ansible Vault example](#git-clone)
- [Encountered issues](#issues)
  - [Issue #1: Executable bit](#executable-bit)
  - [Issue #2: Line endings](#line-endings)
- [Ansible Vault commands](#ansible-vault)
- [Run Ansible via Docker container](#run-ansible)
- [Resources](#resources)

* * *

<!-- markdownlint-disable MD033 -->
<h2 id="context">Context</h2>  

After having successfully run Ansible on Windows using Docker, as documented inside my previous [post](http://crossprogramming.com/2018/02/14/running-ansible-on-windows.html), I thought about documenting how to use [Ansible Vault](https://docs.ansible.com/ansible/latest/vault.html) on Windows.  
This tool was included in Ansible since version 1.5 and its purpose is to ensure sensitive data like credentials, private keys, certificates, etc., used by Ansible playbooks, are stored encrypted.  
This post will present my approach for running Ansible Vault on Windows using Docker, along with the issues I have encountered and their fixes.  

As a real life example of when to use Ansible Vault, I have chosen the task of running a Docker container inside a virtual machine:  

- Create the VM
  - I'll use Docker Machine to create a VM using [Hyper-V driver](https://docs.docker.com/machine/drivers/hyper-v/); this approach has the added benefit of creating a VM which already has Docker installed
  - Beside having access to a Docker host with ~~minimum~~ medium effort, I ended up tinkering with a new Linux distro, other than what I'm usually exposed to (Ubuntu and CentOS)
- Setup the VM to be managed by Ansible  
  - Provide SSH access - already done, since Docker Machine will handle it while creating the VM
  - Provide a working Python version - as you'll see below, this step is not difficult at all
- Clone a git repository from [GitHub](https://github.com/satrapu/ansible-vault-on-windows) containing the Ansible playbook used for running the Docker container based on the [hello-world](https://hub.docker.com/_/hello-world/) image
- Add the Docker Hub credentials ued for pulling the image inside the appropriate Ansible variable YAML file
- Run Ansible Vault from a Docker container to encrypt these credentials
- Run the Ansible playbook used for pulling the Docker image, run the container, then remove them both

I will use [satrapu/ansible-alpine-apk](https://hub.docker.com/r/satrapu/ansible-alpine-apk/) Docker image for running both Ansible and Ansible Vault on Windows.  
All the Docker and Docker Machine related commands below must be executed inside a Powershell console run as admin (use Git Bash as a backup for some commands - e.g. "docker-machine ssh").  

<h2 id="prerequisites">Prerequisites</h2>
All versions below are the latest at the time of writing this particular section (March 26th, 2018).  

- Windows 10 Professional Edition (v1709)
- Hyper-V
- Docker for Windows - I've recently upgraded to v18.03.0-ce, but older versions should be good enough
- Docker Machine - v0.13.0 or older, since v0.14.0 (coming with Docker for Windows v18.0.3.0-ce) is unable to create VMs using hyperv driver - see more details [here](https://github.com/docker/machine/issues/4424)
  - Right after I've upgraded Docker for Windows from 17.12.1-ce to v18.03.0-ce, I was no longer able to create VMs using Docker Machine and hyperv driver; this issue did not occur when using v0.13.0!  
  - Download Docker Machine v0.13.0 from [GitHub](https://github.com/docker/machine/releases/download/v0.13.0/docker-machine-Windows-x86_64.exe), rename it to docker-machine.exe and then move it inside %DOCKER_HOME%\resources\bin to overwrite the existing docker-machine.exe (v0.14.0)
- [Visual Studio Code](https://code.visualstudio.com/) - v1.21.1
  - Any other editor capable of switching line endings between CRLF and LF should be fine too - see below for the actual motivation behind this prerequisite ;)
- [Git](https://git-scm.com/download/win) - v2.16.2
  - The version is not that important, but installing Git Bash along with Git is!

<h2 id="docker-machine">Setup Ansible managed node using Docker Machine</h2>  

- Create a virtual network switch named __ansible__, as described [here](https://docs.docker.com/machine/drivers/hyper-v/#2-set-up-a-new-external-network-switch-optional)
- Create a Hyper-V virtual machine named __ansible-vault__ having 2 CPUs, 2048 MB RAM, 10 GB disk and attached to the previously created external virtual switch  
  - The boot2docker ISO URL is explicitly set to fixate the Docker version (v18.03.0-ce) for repeatability purposes  
  - Prepare to wait for a rather long period of time (10 minutes or more) for the VM to be created
  - Ignore the SSH reported error

```powershell
docker-machine create `
               --driver hyperv `
               --hyperv-cpu-count 2 `
               --hyperv-memory 2048 `
               --hyperv-disk-size 10240 `
               --hyperv-virtual-switch "ansible" `
               --hyperv-boot2docker-url https://github.com/boot2docker/boot2docker/releases/download/v18.03.0-ce/boot2docker.iso `
               ansible-vault
# Running pre-create checks...
# (ansible-vault) Boot2Docker URL was explicitly set to "https://github.com/boot2docker/boot2docker/releases/download/v18.03.0-ce/boot2docker.iso" at create time, so Docker Machine cannot upgrade this machine to the latest version.
# Creating machine...
# (ansible-vault) Boot2Docker URL was explicitly set to "https://github.com/boot2docker/boot2docker/releases/download/v18.03.0-ce/boot2docker.iso" at create time, so Docker Machine cannot upgrade this machine to the latest version.
# (ansible-vault) Downloading C:\Users\admin\.docker\machine\cache\boot2docker.iso from https://github.com/boot2docker/boot2docker/releases/download/v18.03.0-ce/boot2docker.iso...
# (ansible-vault) 0%....10%....20%....30%....40%....50%....60%....70%....80%....90%....100%
# (ansible-vault) Creating SSH key...
# (ansible-vault) Creating VM...
# (ansible-vault) Using switch "ansible"
# (ansible-vault) Creating VHD
# (ansible-vault) Starting VM...
# (ansible-vault) Waiting for host to start...
# Waiting for machine to be running, this may take a few minutes...
# Detecting operating system of created instance...
# Waiting for SSH to be available...
# Error creating machine: Error detecting OS: Too many retries waiting for SSH to be available.  Last error: Maximum number of retries (60) exceeded
```  

- Check that the VM is running (look for "STATE Running"):

```powershell
 docker-machine ls
# NAME            ACTIVE   DRIVER   STATE     URL                        SWARM   DOCKER    ERRORS
# ansible-vault   -        hyperv   Running   tcp://192.168.1.168:2376           Unknown   Unable to query docker version: Get https://192.168.1.168:2376/v1.15/version: x509: certificate signed by unknown authority
```

- Get the IPv4 address of the VM, since you'll needed it inside the Ansible inventory file:

```powershell
docker-machine ip ansible-vault
# 192.168.1.168
```

- Connect to the VM using SSH (see more [here](https://github.com/boot2docker/boot2docker#ssh-into-vm))
  - In case you're unable to enter the VM via SSH from a Powershell terminal, try using Git Bash run as admin - welcome to Windows!  

```powershell
docker-machine ssh ansible-vault
#                         ##         .
#                   ## ## ##        ==
#                ## ## ## ## ##    ===
#            /"""""""""""""""""\___/ ===
#       ~~~ {~~ ~~~~ ~~~ ~~~~ ~~~ ~ /  ===- ~~~
#            \______ o           __/
#              \    \         __/
#               \____\_______/
#  _                 _   ____     _            _
# | |__   ___   ___ | |_|___ \ __| | ___   ___| | _____ _ __
# | '_ \ / _ \ / _ \| __| __) / _` |/ _ \ / __| |/ / _ \ '__|
# | |_) | (_) | (_) | |_ / __/ (_| | (_) | (__|   <  __/ |
# |_.__/ \___/ \___/ \__|_____\__,_|\___/ \___|_|\_\___|_|
# Boot2Docker version 18.03.0-ce, build HEAD : 404ee40 - Thu Mar 22 17:12:23 UTC 2018
# Docker version 18.03.0-ce, build 0520e24
```  

- Install Python and Python setup tools on the VM, as they are needed by Ansible - check [this](https://stackoverflow.com/a/28750034) StackOverflow article for instructions.  
  Keep in mind that all changes done to this machine will be lost after a restart, as documented [here](https://github.com/boot2docker/boot2docker#persist-data)!

```bash
tce-load -wi python python-setuptools
# python.tcz.dep OK
# tk.tcz.dep OK
# readline.tcz.dep OK
# Downloading: libffi.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# python-setuptools.tcz.dep OK
# libffi.tcz           100% |*************************************************************************************************| 16384   0:00:00 ETA
# libffi.tcz: OK
# Downloading: expat2.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# expat2.tcz           100% |*************************************************************************************************| 73728   0:00:00 ETA
# expat2.tcz: OK
# Downloading: ncurses.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# ncurses.tcz          100% |*************************************************************************************************|   196k  0:00:00 ETA
# ncurses.tcz: OK
# Downloading: readline.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# readline.tcz         100% |*************************************************************************************************|   144k  0:00:00 ETA
# readline.tcz: OK
# Downloading: gdbm.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# gdbm.tcz             100% |*************************************************************************************************| 73728   0:00:00 ETA
# gdbm.tcz: OK
# Downloading: tcl.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# tcl.tcz              100% |*************************************************************************************************|  1128k  0:00:00 ETA
# tcl.tcz: OK
# Downloading: tk.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# tk.tcz               100% |*********************************************************************************************************************************************|   916k  0:00:00 ETA
# tk.tcz: OK
# Downloading: openssl.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# openssl.tcz          100% |*********************************************************************************************************************************************|  1500k  0:00:00 ETA
# openssl.tcz: OK
# Downloading: bzip2-lib.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# bzip2-lib.tcz        100% |*********************************************************************************************************************************************| 28672   0:00:00 ETA
# bzip2-lib.tcz: OK
# Downloading: sqlite3.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# sqlite3.tcz          100% |*********************************************************************************************************************************************|   388k  0:00:00 ETA
# sqlite3.tcz: OK
# Downloading: python.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# python.tcz           100% |*********************************************************************************************************************************************| 11820k  0:00:00 ETA
# python.tcz: OK
# Downloading: python-setuptools.tcz
# Connecting to repo.tinycorelinux.net (89.22.99.37:80)
# python-setuptools.tc 100% |*********************************************************************************************************************************************|   236k  0:00:00 ETA
# python-setuptools.tcz: OK
```

In case you forgot this step, when running Ansible playbook you'll see something like this:

{% raw %}

```powershell
# PLAY [docker_hosts] ************************************************************

# TASK [Gathering Facts] *********************************************************
# fatal: [ansible_vault_example]: FAILED! => {"changed": false, "failed": true, "module_stderr": "", "module_stdout": "/bin/sh: /usr/local/bin/python: not found\r\n", "msg": "MODULE FAILURE", "rc": 0}
#         to retry, use: --limit @/opt/ansible-playbooks/hello-world.retry

# PLAY RECAP *********************************************************************
# ansible_vault_example      : ok=0    changed=0    unreachable=0    failed=1
```

{% endraw %}  

- Display Python version

```bash
python --version
# Python 2.7.14
```  

- Exit the VM:

```bash
exit
```  

<h2 id="git-clone">Clone Ansible Vault example</h2>  

- Clone the following git repository hosted on GitHub somewhere on your Windows machine (e.g. E:\Satrapu\Programming\Ansible\ansible-vault-on-windows):

```powershell
cd E:/Satrapu/Programming/Ansible
git clone https://github.com/satrapu/ansible-vault-on-windows.git
```

This git repo is based on the classic Ansible folder structure, as documented [here](http://docs.ansible.com/ansible/latest/playbooks_best_practices.html#directory-layout).

- Change the Ansible inventory file named __local__
  - Set the value of the __ansible_host__ property to the IP address of the ansible-vault VM (e.g. ansible_host=192.168.1.168)
  - Please note property __ansible_ssh_private_key_file__ has been set to "/opt/docker-machine/ansible-vault/id_rsa" value - the id_rsa represents a private key generated by Docker Machine while  creating ansible-vault VM and which will be made available inside the Ansible Docker container via a Docker volume; this property should not be changed without fully understanding what else needs to be changed (see below)

- Create a file named __vault_password__ under __../ansible-vault-password__ folder (outside Git repo!) and add a password (one line, no line ending)  
  - Since this file contains a password, it must not be put under source control, that's why it should be created outside the Git repo
  - To make it available inside Ansible Docker container, we'll mount the containing folder as a Docker volume under path "/opt/ansible-vault-password"
    - Example: "-v E:/Satrapu/Programming/Ansible/ansible-vault-password:/opt/ansible-vault-password"
  - I have used [https://strongpasswordgenerator.com](https://strongpasswordgenerator.com/) to generate such password  
    - Click "Show Options" panel under the "Generate password" big green button to fine tune your password

- Replace the __TBD__ placeholders from the __/ansible-vault-on-windows/group_vars/docker_hosts/vault.yml__ file:

```yaml
vault_docker_registry_url: TBD
vault_docker_registry_auth_username: TBD
vault_docker_registry_auth_password: TBD
vault_docker_registry_auth_email: TBD
```

with the appropriate values, like this:  

```yaml
vault_docker_registry_url:  https://index.docker.io/v1/
vault_docker_registry_auth_username: some_user_name
vault_docker_registry_auth_password: P@zZwWwooRdddd
vault_docker_registry_auth_email: some_user_name@server.ro
```

This file should be put under source control once it has been encrypted.  
For instance, the Docker Hub registry URL can be found via this command:

```powershell
docker info | findstr Registry
# Registry: https://index.docker.io/v1/
```

In case you forgot to correctly update __vault.yml__ file, when running Ansible playbook you should see something like this:

{% raw %}

```powershell
# PLAY [docker_hosts] ************************************************************

# TASK [Gathering Facts] *********************************************************
# ok: [ansible_vault_example]

# TASK [run_hello_world_container : Install pip] *********************************
# changed: [ansible_vault_example]

# TASK [run_hello_world_container : Install docker-py] ***************************
# changed: [ansible_vault_example]

# TASK [run_hello_world_container : Login into Docker registry TBD] **************
# fatal: [ansible_vault_example]: FAILED! => {"changed": false, "failed": true, "msg": "Parameter error: the email address appears to be incorrect. Expecting it to match /[^@]+@[^@]+\\.[^@]+/"}
#         to retry, use: --limit @/opt/ansible-playbooks/hello-world.retry

# PLAY RECAP *********************************************************************
# ansible_vault_example      : ok=3    changed=2    unreachable=0    failed=1
```

{% endraw %}  

- You'll see a __vars.yml__ file under the same folder, __/ansible-vault-on-windows/group_vars/docker_hosts__:

{% raw %}

```yaml
docker_registry_url: "{{ vault_docker_registry_url }}"
docker_registry_auth_username: "{{ vault_docker_registry_auth_username }}"
docker_registry_auth_password: "{{ vault_docker_registry_auth_password }}"
docker_registry_auth_email: "{{ vault_docker_registry_auth_email }}"
```

{% endraw %}

Ansible will use the password residing inside the one-line file passed as the value of the __--vault-password-file__ argument (e.g. --vault-password-file=/opt/ansible-vault-password/vault_password) to automatically decrypt the vault.yml file and will populate the above variables with the correct sensitive data, e.g. the user name and password used for pulling images from Docker Hub.

- After applying the aforementioned changes, the local git repo should look like this:  

```powershell
# Change drive letters and paths according to your local setup
E:; cd E:/Satrapu/Programming/Ansible/ansible-vault-on-windows; tree /F
# E:\SATRAPU\PROGRAMMING\ANSIBLE\ANSIBLE-VAULT-ON-WINDOWS
# │   .gitattributes
# │   .gitignore
# │   ansible.cfg
# │   hello-world.yml
# │   LICENSE
# │   local
# │   README.md
# │   vault_password_provider.py
# │
# ├───group_vars
# │   └───docker_hosts
# │           vars.yml
# │           vault.yml
# │
# └───roles
#     └───run_hello_world_container
#         ├───defaults
#         │       main.yml
#         │
#         └───tasks
#                 main.yml

```

<h2 id="issues">Encountered issues</h2>  

<h3 id="executable-bit">Issue #1: Executable bit</h3>  

Running Ansible Vault from a Docker container will fail since I'm trying to mount a Windows folder in a Linux container and all of its files will be mounted with all Linux permissions (read, write and execute):

```powershell
docker container run `
                 --rm `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-on-windows:/opt/ansible-playbooks `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-password:/opt/ansible-vault-password `
                 satrapu/ansible-alpine-apk:2.4.1.0-r0 `
                 ansible-vault encrypt `
                    --vault-password-file=/opt/ansible-vault-password/vault_password `
                    ./group_vars/docker_hosts/vault.ym
#  [WARNING]: Error in vault password file loading (default): Problem running
# vault password script /opt/ansible-vault-password/vault_password ([Errno 8]
# Exec format error). If this is not a script, remove the executable bit from the
# file.
# ERROR! Problem running vault password script /opt/ansible-vault-password/vault_password ([Errno 8] Exec format error). If this is not a script, remove the executable bit from the file.
```

Here are the permissions found inside the Docker container:

```powershell
docker container run `
                 --rm `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-password:/opt/ansible-vault-password `
                 satrapu/ansible-alpine-apk:2.4.1.0-r0 `
                 ls -al /opt/ansible-vault-password
# total 5
# drwxr-xr-x    2 root     root             0 Mar 29 19:56 .
# drwxr-xr-x    1 root     root          4096 Mar 29 20:03 ..
# -rwxr-xr-x    1 root     root           100 Mar 24 19:20 vault_password
```

The above executable bit related error message is pretty clear, unfortunately, at the moment there is no easy way of mounting files without the execute bit, as stated [here](https://docs.docker.com/docker-for-windows/troubleshoot/#permissions-errors-on-data-directories-for-shared-volumes).  

On the other hand, Ansible knows how to process a file with executable bit containing a Vault password if it is a Python script, as documented [here](http://docs.ansible.com/ansible/latest/playbooks_vault.html#running-a-playbook-with-vault), so the idea is to load the password via a Python script, which will be passed as the value of the --vault-password-file argument - see an example [here](https://github.com/hashicorp/packer/issues/555#issuecomment-145749614).  
At this moment I'm able to bypass the pesky Windows-Docker-folder-mounting issue, but this has lead me to the 2nd issue :)

<h3 id="line-endings">Issue #2: Line endings</h3>  

Ansible Vault being able to run a Python script which returns the password is great news, but keep in mind we're still editing files on Windows, which uses CRLF as line ending, which, of course, will not work on Linux:

```powershell
docker container run `
                 --rm `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-on-windows:/opt/ansible-playbooks `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-password:/opt/ansible-vault-password `
                 satrapu/ansible-alpine-apk:2.4.1.0-r0 `
                 ansible-vault encrypt `
                    --vault-password-file=./vault_password_provider.py `
                    ./group_vars/docker_hosts/vault.yml
#  [WARNING]: Error in vault password file loading (default): Problem running
# vault password script /opt/ansible-playbooks/vault_password_provider.py ([Errno
# 2] No such file or directory). If this is not a script, remove the executable
# bit from the file.
# ERROR! Problem running vault password script /opt/ansible-playbooks/vault_password_provider.py ([Errno 2] No such file or directory). If this is not a script, remove the executable bit from the file.
```

The fix is to edit vault_password_provider.py with an editor having line endings set for this file to "LF" instead of "CRLF" - see such setup for [Visual Studio Code](https://stackoverflow.com/a/39532890).

<h2 id="ansible-vault">Ansible Vault commands</h2>  
Having fixed the above 2 issues, the following Ansible Vault commands will work like a charm:

- Encrypt vault.yml:

```powershell
docker container run `
                 --rm `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-on-windows:/opt/ansible-playbooks `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-password:/opt/ansible-vault-password `
                 satrapu/ansible-alpine-apk:2.4.1.0-r0 `
                 ansible-vault encrypt `
                    --vault-password-file=./vault_password_provider.py `
                    ./group_vars/docker_hosts/vault.yml
```

- Decrypt vault.yml:

```powershell
docker container run `
                 --rm `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-on-windows:/opt/ansible-playbooks `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-password:/opt/ansible-vault-password `
                 satrapu/ansible-alpine-apk:2.4.1.0-r0 `
                 ansible-vault decrypt `
                    --vault-password-file=./vault_password_provider.py `
                    ./group_vars/docker_hosts/vault.yml
```

- View the decrypted vault.yml:

```powershell
docker container run `
                 --rm `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-on-windows:/opt/ansible-playbooks `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-password:/opt/ansible-vault-password `
                 satrapu/ansible-alpine-apk:2.4.1.0-r0 `
                 ansible-vault view `
                    --vault-password-file=./vault_password_provider.py `
                    ./group_vars/docker_hosts/vault.yml
# vault_docker_registry_url: https://index.docker.io/v1/
# vault_docker_registry_auth_username: xxxxxxx
# vault_docker_registry_auth_password: xxxxxxx
# vault_docker_registry_auth_email: xxxxxxx
```

<h2 id="run-ansible">Run Ansible via Docker container</h2>  

- Run Ansible playbook:
  
{% raw %}

```powershell
# Replace <YOUR_ADMIN_USERS> placeholder with the Windows user name used for creating ansible-vault VM.
# Tip: Increase the verbosity of the ansible-playbook output by adding "-vvv" option at the end of the below line
docker container run `
                 --rm `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-on-windows:/opt/ansible-playbooks `
                 -v E:/Satrapu/Programming/Ansible/ansible-vault-password:/opt/ansible-vault-password `
                 -v C:/Users/<YOUR_ADMIN_USERS>/.docker/machine/machines/ansible-vault:/opt/docker-machine/ansible-vault `
                 satrapu/ansible-alpine-apk:2.4.1.0-r0 `
                 ansible-playbook `
                    --inventory-file=local `
                    --vault-password-file=./vault_password_provider.py `
                    hello-world.yml

# PLAY [docker_hosts] ************************************************************

# TASK [Gathering Facts] *********************************************************
# ok: [ansible_vault_example]

# TASK [run_hello_world_container : Install pip] *********************************
# ok: [ansible_vault_example]

# TASK [run_hello_world_container : Install docker-py] ***************************
# ok: [ansible_vault_example]

# TASK [run_hello_world_container : Login into Docker registry https://index.docker.io/v1/] ***
# changed: [ansible_vault_example]

# TASK [run_hello_world_container : Pull Docker image hello-world:linux] *********
# changed: [ansible_vault_example]

# TASK [run_hello_world_container : Logout from Docker registry https://index.docker.io/v1/] ***
# ok: [ansible_vault_example]

# TASK [run_hello_world_container : Run Docker container hello-world-from-satrapu] ***
# changed: [ansible_vault_example]

# TASK [run_hello_world_container : Remove Docker container hello-world-from-satrapu] ***
# changed: [ansible_vault_example]

# TASK [run_hello_world_container : Remove Docker image hello-world:linux] *******
# changed: [ansible_vault_example]

# PLAY RECAP *********************************************************************
# ansible_vault_example      : ok=9    changed=5    unreachable=0    failed=0
```  

{% endraw %}

<h2 id="resources">Resources</h2>  

- [Docker Machine](https://docs.docker.com/machine/)  
- [Docker Machine command-line reference](https://docs.docker.com/machine/reference/)
- [boot2docker](http://boot2docker.io/)  
- [Tiny Core Linux](http://www.tinycorelinux.net/)  
- Ansible modules
  - [easy_install](http://docs.ansible.com/ansible/latest/modules/easy_install_module.html)
  - [pip](http://docs.ansible.com/ansible/latest/modules/pip_module.html)
  - [docker_login](http://docs.ansible.com/ansible/latest/modules/docker_login_module.html)
  - [docker_image](http://docs.ansible.com/ansible/latest/modules/docker_image_module.html)
  - [docker_container](http://docs.ansible.com/ansible/latest/modules/docker_container_module.html)
