---
layout: post
title:  "Running Ansible on Windows using Docker"
date:   2018-02-13 21:51:20 +0200
tags: [programming, ansible, docker, alpine, linux, windows, apk, pip, github]
---
- [Context](#context)  
- [Approach #1: APK](#apk)  
- [Approach #2: PIP](#pip)  
- [Approach #3: Sources](#sources) 
- [Conclusion](#conclusion) 
- [Bonus](#bonus) 

* * *  

<h2 id="context">Context</h2>
[Ansible](https://www.ansible.com/) is an automation tool written in Python which simplistically works like this: Ansible is installed on a machine (the control node) and it will execute a series of Python scripts generated based on some YAML files (the playbooks, roles and tasks) over SSH to a bunch of other machines (the managed nodes).  
This tool became so successful that in October 2015 Red Hat [acquired](https://www.redhat.com/en/about/press-releases/red-hat-acquire-it-automation-and-devops-leader-ansible) Ansible, Inc., the commercial entity behind it. In case you're wondering why did this acquisition happended, read [this article](https://www.redhat.com/en/blog/why-red-hat-acquired-ansible); it will also highlight the main features of this tool and why should we use it.  

I have used Ansible for the past year and I really liked it due to its (apparent) lean learning curve and its ability to automate just about anything. I was fortunate enough to use it from a MacBook Pro and thus I was able to install it via [Homebrew](http://brewformulas.org/Ansible), the macOS package manager. Until now, Ansible is still not supporting officially [a Windows control machine](http://docs.ansible.com/ansible/latest/intro_installation.html#control-machine-requirements).
One brave enough might try installing Python on a Windows machine, be it virtual or not, but one should use the officially supported ways: running Ansible from a Linux or Mac machine or from ... Docker.  

Creating an Ansible Docker image is not that hard and you can find [plenty](https://hub.docker.com/search/?q=ansible) of such images.
I decided to write my own in order to learn how to author Docker images, in addition to using them.  
Since Ansible works on a Linux control node, I've decided to use [Alpine Linux Docker image](https://hub.docker.com/_/alpine/) as the base for my own as it's very small: v3.6 is less than 4MB, while v3.7 is a little over. Alpine Linux has its own package manager, [apk](https://wiki.alpinelinux.org/wiki/Alpine_Linux_package_management), so I could've installed one of the available Ansible apk packages and be done with it. But this approach has one flaw: even though Ansible has released many [versions](http://releases.ansible.com/ansible/), Alpine didn't packed them all, so you just have to live with whatever Ansible versions a specific Alpine release comes with - usually one, as one can easily see [here](https://pkgs.alpinelinux.org/packages?name=ansible&branch=v3.6) and [here](https://pkgs.alpinelinux.org/packages?name=ansible&branch=v3.7).   
There are several ways to overcome this limitation: use [pip](https://pip.pypa.io/en/stable/), the Python package manager, or install Ansible from its sources hosted on [GitHub](https://github.com/ansible/ansible).
Pip contains [lots](https://pypi.python.org/pypi/ansible) of Ansible versions, while installing Ansible from sources gives you the ability to release any Ansible git commit.

<h2 id="apk">Approach #1: APK</h2>
TBD  

<h2 id="pip">Approach #2: PIP</h2>
TBD  

<h2 id="sources">Approach #3: Sources</h2>
TBD   

<h2 id="conclusion">Conclusion</h2>
TBD 

<h2 id="bonus">Bonus</h2>
* Official resources
  * [Source code](https://github.com/ansible/ansible)
  * [Documentation](http://docs.ansible.com)
  * [Developer guide](http://docs.ansible.com/ansible/latest/dev_guide)
  * [Directory layout](http://docs.ansible.com/ansible/latest/playbooks_best_practices.html#directory-layout)
  * [Variable quick reference](https://github.com/lorin/ansible-quickref)
  * [Configuration file template](https://raw.githubusercontent.com/ansible/ansible/devel/examples/ansible.cfg)
  * [Best practices](http://docs.ansible.com/ansible/latest/playbooks_best_practices.html)
  * [Ansible Best Practices: The Essentials](https://www.ansible.com/blog/ansible-best-practices-essentials)
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