![GitHub stars](https://img.shields.io/github/stars/shi88ihs//torblock?style=social)
![GitHub forks](https://img.shields.io/github/forks/shi88ihs//torblock?style=social)
![GitHub issues](https://img.shields.io/github/issues/shi88ihs//torblock)
![GitHub last commit](https://img.shields.io/github/last-commit/shi88ihs//torblock)
![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-success)

# VPS-Tor-Exit-Nodes-NTFtables-Blocking-Script-
Tor Exit Nodes Blocking Script for Securing VPS' &amp; Web Infrstucture

# 🛡️ TorBlock - Automated Tor Exit Node Blocker

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell_Script-121011?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![nftables](https://img.shields.io/badge/nftables-required-blue)](https://netfilter.org/projects/nftables/)

A production-ready bash script that automatically blocks all known Tor exit nodes using nftables firewall rules. Designed for Linux servers that need to restrict anonymous Tor traffic while maintaining simplicity and reliability.

## 🎯 Features

- **Automated IP Blocking**: Loads and blocks 1000+ Tor exit node IPs automatically
- **nftables Integration**: Uses modern Linux firewall framework with efficient set-based filtering
- **Robust Error Handling**: Validates each IP and provides detailed status reporting
- **Zero Dependencies**: Pure bash script with only nftables required
- **Production Ready**: Includes logging, verification, and easy removal
- **Idempotent**: Safe to run multiple times - cleans and recreates rules

## 📋 Prerequisites

- Linux system with kernel 3.13+ (for nftables support)
- nftables installed (`nft` command available)
- Root/sudo privileges
- Bash 4.0 or higher

[Full README content continues...]
```

---

## 📁 Complete Project Structure

Here's how to transform this into a professional GitHub portfolio project:

### **File Structure:**
```
torblock/
├── README.md                 # Main documentation (created above)
├── LICENSE                   # MIT License
├── torblock.sh              # Main script (your working script)
├── .gitignore               # Git ignore file
├── CONTRIBUTING.md          # Contribution guidelines
├── CHANGELOG.md             # Version history
├── examples/
│   ├── cron-example.sh      # Cron automation example
│   └── systemd-example/
│       ├── torblock.service
│       └── torblock.timer
├── tests/
│   └── test_torblock.sh     # Basic tests
└── docs/
    ├── INSTALLATION.md      # Detailed installation guide
    ├── ARCHITECTURE.md      # Technical architecture
    └── FAQ.md               # Frequently asked questions
```

---

## 🎨 How to Make It Portfolio-Ready

### 1. **LICENSE File**
```
MIT License

Copyright (c) 2025 A. Walker - GitHub @shi88hs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction...
```

### 2. **.gitignore**
```
# Tor exit node lists
*.txt
tor-exit-nodes*

# Logs
*.log

# Temporary files
*.tmp
*.swp
*~

# OS specific
.DS_Store
Thumbs.db


## Demo

![Demo](docs/images/demo.gif)

## Screenshots

### Successful Installation
![Installation](docs/images/install.png)

### Blocking in Action
![Blocking](docs/images/blocking.png)
```
```
🛡️ TorBlock - Production-grade Tor exit node blocker for Linux servers

Secure your server from anonymous Tor traffic with this lightweight, 
zero-dependency bash script. Uses nftables for efficient IP filtering. 
Perfect for web servers, APIs, and services requiring authenticated access.

⚡ Blocks 1000+ Tor nodes in seconds

🔒 Production-tested and battle-hardened

📊 Detailed logging and verification

🚀 Easy automation with cron/systemd
