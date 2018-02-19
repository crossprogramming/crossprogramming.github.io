---
layout: post
title: "Running Ansible on Windows"
date: 2018-02-15 00:08:33 +0200
tags: [programming, ansible, docker, alpine, linux, windows, apk, pip, git, github]
---
- [Context](#context)
- [Why dockerize Ansible?](#dockerize)
- [Common things](#common)
- [Approach #1: APK](#apk)  
- [Approach #2: PIP](#pip)  
- [Approach #3: Sources](#sources) 
- [Example](#example)
- [Conclusion](#conclusion) 
- [Resources](#resources) 

* * *  

<h2 id="context">Context</h2>
[Ansible](https://www.ansible.com/) is an automation tool written in Python which simplistically speaking works like this: Ansible is installed on a machine (the control node) and it will execute a series of Python scripts generated based on some [YAML](http://www.yaml.org/) files (playbooks, roles and tasks) on a bunch of other machines (the managed nodes).  
This tool was so successful that in October 2015 Red Hat [acquired](https://www.redhat.com/en/about/press-releases/red-hat-acquire-it-automation-and-devops-leader-ansible) Ansible, Inc., the commercial entity behind it. In case you're wondering why did this acquisition happended, read [this article](https://www.redhat.com/en/blog/why-red-hat-acquired-ansible); it will also highlight the main features of this tool and why should we use it.  

I have used Ansible for the past year and I really liked it due to its (apparent) lean learning curve and its ability to automate (almost) anything. I was fortunate enough to use it from a MacBook Pro and thus I was able to easily install it via [Homebrew](http://brewformulas.org/Ansible), the macOS package manager.  
The common scenarios where I used this tool were: __provisioning__ Linux (CentOS 7.x) environments (e.g. installing Oracle JDK, running MySQL or Oracle databases inside Docker, setting up firewall rules and much more) and performing automated __deployments__ for various SAP Hybris applications.

<h2 id="dockerize">Why dockerize Ansible?</h2>
Until now, Ansible is still not officially supporting [a Windows control machine](http://docs.ansible.com/ansible/latest/intro_installation.html#control-machine-requirements).
One brave enough soul might try install Python and then Ansible on a Windows machine, be it virtual or not, but one should use the officially supported ways: running Ansible from a Linux or macOS machine. Or use Docker.  

Running Ansible from a Docker container has several benefits:
* Use a great automation tool on Windows
* Easy to share the tool across the team, no matter the underlying OS
* Fixate your Ansible version to ensure the stability & repeatability of your automated processes (no more "Works on my machine ... only" syndrom!)  
* Easy to test latest & greatest release without impacting your current dev environment
* Keeps your dev environment clean  

Creating an Ansible Docker image is not that hard and you can find [plenty](https://hub.docker.com/search/?q=ansible) of such images.
I decided to write my own in order to learn how to author Docker images, in addition to merely using them.  

Since Ansible works like a charm on a Linux control node, I've decided to use [Alpine Linux Docker image](https://hub.docker.com/_/alpine/) as the base for my own as it's very small: v3.6 is less than 4MB, while v3.7 is a little over 4MB.  
Alpine Linux has its own package manager, [apk](https://wiki.alpinelinux.org/wiki/Alpine_Linux_package_management), so I could've installed one of the available packages and be done with it, but this approach has one flaw: even though Ansible has released many [versions](http://releases.ansible.com/ansible/), Alpine didn't packed them all, so you just have to live with whatever Ansible versions a specific Alpine release comes with - e.g. [v3.6](https://pkgs.alpinelinux.org/packages?name=ansible&branch=v3.6), [v3.7](https://pkgs.alpinelinux.org/packages?name=ansible&branch=v3.7).  

There are different ways to overcome this limitation: install Ansible using [pip](https://pip.pypa.io/en/stable/), the Python package manager, install it from its sources hosted on [GitHub](https://github.com/ansible/ansible), use a different Linux distribution, etc.  
Pip offers [lots](https://pypi.python.org/pypi/ansible) of Ansible versions to choose from, while installing Ansible from its sources gives you the ability to dockerize any of its git commits. I recommend the former when you need to get stuff done and the latter when you want to experiment/test a specific commit.  

Below you may find 3 Docker images I have created for running Ansible on Windows, each with its pros and cons.

<h2 id="common">Common things</h2>
I wanted a simple way of running Ansible playbooks from my Windows machine, so I'm using a Docker volume for sharing them with the Docker container; the playbooks can be found here: __/opt/ansible-playbooks__ - this path is customizable via a build argument, __ANSIBLE_PLAYBOOKS_HOME__.  
The whole development experience is like this: open your favourite (Ansible aware) text editor (see several options [below](#resources)), write your playbooks, then play them from a CLI of your choice (e.g. PowerShell, [Git Bash](http://www.techoism.com/how-to-install-git-bash-on-windows/) or [Cmder](http://cmder.net/)) - basically, the same as running Ansible from a Linux or macOS control node.  

Below you may find the Docker commands you should use for any of these 3 images.  
Please replace the __\<SUFFIX\>__ placeholder with the appropriate value: __apk__, __pip__ or __git__.

<h3>Building the Docker image</h3>
````bash
docker image build --file Dockerfile-<SUFFIX> --tag satrapu/ansible-alpine-<SUFFIX>:latest .
````

<h3>Pushing the Docker image to DockerHub</h3>
Please note you need to be logged-in before pushing a Docker image to a registry, be it DockerHub or a private one!  

````bash
docker image push satrapu/ansible-alpine-<SUFFIX>:latest
````

<h3>Running the Docker container</h3>
````bash
docker container run -v <DOCKER_HOST_ANSIBLE_PLAYBOOKS_HOME>:/opt/ansible-playbook satrapu/ansible-alpine-<SUFFIX>:latest ansible-playbook <RELATIVE_PATH_TO_YOUR_ANSIBLE_PLAYBOOK>
````

<h2 id="apk">Approach #1: APK</h2>
The Dockerfile used for installing Ansible via apk can be found [here](https://github.com/satrapu/docker-ansible/blob/master/Dockerfile-apk).
Additionally, this image uses an argument, __ANSIBLE_VERSION__, which specifies the particular Ansible release version to install at build time.  

* Pros
  * Small image size ~ 97MB
  * Simple Dockerfile
  * Easy to upgrade to future Ansible or Alpine versions
* Cons
  * Coarse grained control over the Ansible release version to use

<h3>Specific Docker commands</h3>
````bash
docker image build --file Dockerfile-apk --tag satrapu/ansible-alpine-apk:latest .
docker image push satrapu/ansible-alpine-apk:latest
docker container run -v <DOCKER_HOST_ANSIBLE_PLAYBOOKS_HOME>:/opt/ansible-playbook satrapu/ansible-alpine-apk:latest ansible-playbook <ANSIBLE_PLAYBOOK>
````

<h2 id="pip">Approach #2: PIP</h2>
The Dockerfile used for installing Ansible via pip can be found [here](https://github.com/satrapu/docker-ansible/blob/master/Dockerfile-pip).
Additionally, this image uses an argument, __ANSIBLE_VERSION__, which specifies the particular Ansible release version to install at build time.

* Pros
  * Easy to upgrade to future Ansible or Alpine versions
  * Finer grained control over the Ansible release version to use
  * Medium image size ~ 268MB
* Cons
  * The Dockerfile is a little bit more complex than apk based approach
  * Any upgrade to future Ansible or Alpine versions may require additional effort in order to identify the right prerequisites (e.g. specific versions of Python packages)
  * Increased Docker image build time

<h3>Specific Docker commands</h3>
````bash
docker image build --file Dockerfile-pip --tag satrapu/ansible-alpine-pip:latest .
docker image push satrapu/ansible-alpine-pip:latest
docker container run -v <DOCKER_HOST_ANSIBLE_PLAYBOOKS_HOME>:/opt/ansible-playbook satrapu/ansible-alpine-pip:latest ansible-playbook <ANSIBLE_PLAYBOOK>
````

<h2 id="sources">Approach #3: Sources</h2>
The Dockerfile used for installing Ansible from its sources can be found [here](https://github.com/satrapu/docker-ansible/blob/master/Dockerfile-git).
Additionally, this image used an argument, __ANSIBLE_GIT_CHECKOUT_ARGS__, which is directly passed to the __git checkout__ command, thus it can represent a git branch name, tag or commit hash (short or long), including specific flags, as documented [here](https://git-scm.com/docs/git-checkout).

* Pros
  * Finest grained control over the Ansible release version to use
* Cons
  * Rather complex Dockerfile
  * Any future change in the process of installing Ansible from sources might negatively affect building this image
  * Any upgrade to future Ansible or Alpine versions may require additional effort in order to identify the right prerequisites (e.g. Python packages)
  * Largest image size ~ 487MB
  * Rather long Docker image build time

<h3>Specific Docker commands</h3>
````bash
docker image build --file Dockerfile-git --tag satrapu/ansible-alpine-git:latest .
docker image push satrapu/ansible-alpine-git:latest
docker container run -v <DOCKER_HOST_ANSIBLE_PLAYBOOKS_HOME>:/opt/ansible-playbook satrapu/ansible-alpine-git:latest ansible-playbook <ANSIBLE_PLAYBOOK>
````

<h2 id="example">Example</h2>
The below commands have been executed on a machine running Windows 10 Pro x64, release 1709 and Docker version 17.12.0-ce, build c97c6d6.  
Given the following folder __hello-world__ on this Windows machine:
````powershell
P:\Satrapu\Programming\Ansible
└───hello-world
        hello-world.yml
````

Containing the __hello-world.yml__ file:
````yaml
---
# This playbook prints a simple debug message
- name: Echo 
  hosts: 127.0.0.1
  connection: local

  tasks:
  - name: Print debug message
    debug:
      msg: Hello, world!
````

I'm playing the hello-world.yml playbook via the following command:
````powershell
docker container run -v P:\Satrapu\Programming\Ansible\hello-world:/opt/ansible-playbooks satrapu/ansible-alpine-apk ansible-playbook hello-world.yml

PLAY [Echo] ********************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [Print debug message] *****************************************************
ok: [localhost] => {
    "msg": "Hello, world!"
}

PLAY RECAP *********************************************************************
localhost                  : ok=2    changed=0    unreachable=0    failed=0
````

I can run other Ansible commands:
````powershell
# Print Ansible version
docker container run satrapu/ansible-alpine-apk ansible --version
ansible 2.4.1.0
  config file = /etc/ansible/ansible.cfg
  configured module search path = [u'/root/.ansible/plugins/modules', u'/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/lib/python2.7/site-packages/ansible
  executable location = /usr/bin/ansible
  python version = 2.7.14 (default, Dec 14 2017, 15:51:29) [GCC 6.4.0]
````

<h2 id="conclusion">Conclusion</h2>
Ansible can be run on many operating systems with similar developer experience, as long as they are [supported by Docker](https://docs.docker.com/install/#supported-platforms).  
Just because a tool is not officially supported on Windows or it's *nix only, doesn't mean you have to forget about it - dockerize it and start using it!

<h2 id="resources">Resources</h2>
* Ansible official resources
  * [Documentation](http://docs.ansible.com)
  * [Developer guide](http://docs.ansible.com/ansible/latest/dev_guide)
  * [Directory layout](http://docs.ansible.com/ansible/latest/playbooks_best_practices.html#directory-layout)
  * [Variable quick reference](https://github.com/lorin/ansible-quickref)
  * [Configuration file template](https://raw.githubusercontent.com/ansible/ansible/devel/examples/ansible.cfg)
  * [YAML syntax](http://docs.ansible.com/ansible/latest/YAMLSyntax.html)
  * [Best practices](http://docs.ansible.com/ansible/latest/playbooks_best_practices.html)
  * [Ansible Best Practices: The Essentials](https://www.ansible.com/blog/ansible-best-practices-essentials)
  * [Ansible Tower](https://www.ansible.com/products/tower)
* Other resouces
  * [Debug Ansible Playbooks Like A Pro](https://blog.codecentric.de/en/2017/06/debug-ansible-playbooks-like-pro/)
* Udemy free courses  
  * [Ansible for the Absolute Beginner - Hands-On](https://www.udemy.com/learn-ansible/learn/v4/overview)  
  * [Ansible Essentials: Simplicity in Automation](https://www.udemy.com/ansible-essentials-simplicity-in-automation/learn/v4/overview) 
* IDEs
  * [Atom](https://atom.io/)
    * Extensions
      * [language-ansible](https://atom.io/packages/language-ansible)
      * [autocomplete-ansible](https://atom.io/packages/autocomplete-ansible)
      * [linter-ansible-linting](https://atom.io/packages/linter-ansible-linting)
      * [linter-ansible-syntax](https://atom.io/packages/linter-ansible-syntax)
      * [ansible-vault](https://atom.io/packages/ansible-vault)
      * [language-ini](https://atom.io/packages/language-ini) (used for highlighting Ansible inventory files)
      * [atom-jinja2](https://atom.io/packages/atom-jinja2)
  * [Visual Studio Code](https://code.visualstudio.com/)
    * Extensions
      * [language-Ansible](https://marketplace.visualstudio.com/items?itemName=haaaad.ansible)
      * [ansible-autocomplete](https://marketplace.visualstudio.com/items?itemName=timonwong.ansible-autocomplete)
      * [ansible-vault](https://marketplace.visualstudio.com/items?itemName=dhoeric.ansible-vault)
      * [Jinja](https://marketplace.visualstudio.com/items?itemName=wholroyd.jinja)