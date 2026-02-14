![GitHub stars](https://img.shields.io/github/stars/shi88ihs//torblock?style=social)
![GitHub forks](https://img.shields.io/github/forks/shi88ihs//torblock?style=social)
![GitHub issues](https://img.shields.io/github/issues/shi88ihs//torblock)
![GitHub last commit](https://img.shields.io/github/last-commit/shi88ihs//torblock)
![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-success)

# VPS-Tor-Exit-Nodes-NTFtables-Blocking-Script-
Tor Exit Nodes Blocking Script for Securing VPS' &amp; Web Infrstucture

# 🛡️ TorBlock - Production-grade Tor exit node blocker for Linux servers

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell_Script-121011?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![nftables](https://img.shields.io/badge/nftables-required-blue)](https://netfilter.org/projects/nftables/)

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


