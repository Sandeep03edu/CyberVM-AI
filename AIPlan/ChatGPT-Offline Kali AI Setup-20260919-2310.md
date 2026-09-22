# Offline Kali AI Setup

**User:** Anonymous  
**Created:** 9/19/2026 0:06:05  
**Updated:** 9/19/2026 23:08:30  
**Exported:** 9/19/2026 23:10:02  
**Link:** [https://chatgpt.com/c/6aad8494-986c-83ee-8416-c3dcf50c9c34](https://chatgpt.com/c/6aad8494-986c-83ee-8416-c3dcf50c9c34)  

## Prompt:
9/19/2026, 12:06:20 AM

Kali linux distro with complete offline AI for security testing? Can we create or use any complerte offline LLM

## Response:
9/19/2026, 12:06:22 AM

> **Searching 5 websites**
>
> 
>
> Worked for a couple of seconds

Yes. **You can build a Kali Linux machine with a genuinely offline, local LLM that assists with security testing.** You don't need an internet connection while using it.

In fact, Kali published a guide in March 2026 showing essentially this architecture: **Kali + Ollama + local Qwen model + MCP-Kali-Server + 5ire**, with commands processed locally. ([Kali Linux](https://www.kali.org/blog/kali-llm-ollama-5ire/?utm_source=chatgpt.com))

### What I would build

```text
                 ┌─────────────────────────┐
                 │       YOU               │
                 │ "Analyze this target"   │
                 └────────────┬────────────┘
                              │
                              ▼
                 ┌─────────────────────────┐
                 │     Local LLM            │
                 │  Qwen / Llama / Mistral │
                 │       Ollama             │
                 └────────────┬────────────┘
                              │
                         Tool calling
                              │
                              ▼
                 ┌─────────────────────────┐
                 │      MCP-Kali            │
                 │      Tool Gateway        │
                 └────────────┬────────────┘
                              │
          ┌───────────────────┼──────────────────┐
          ▼                   ▼                  ▼
        Nmap               Gobuster           Nikto
        SQLmap             Burp/etc.          Metasploit
        ffuf               John               WPScan
          │                   │                  │
          └───────────────────┴──────────────────┘
                              │
                              ▼
                     Local results → LLM
```

The important distinction is that **the LLM itself isn't the pentesting tool**. The LLM reasons over results and can invoke local tools through a controlled interface. Kali's own example uses MCP-Kali-Server for exactly this type of integration. ([Kali Linux](https://www.kali.org/blog/kali-llm-ollama-5ire/?utm_source=chatgpt.com))

### Completely offline?

**Yes, after initial setup.**

You'd download:

- Kali's offline/Everything ISO
- Ollama
- the LLM model
- MCP server/components
- your security tools
- optionally a local GUI such as 5ire/Open WebUI

Then you can disconnect the machine from the Internet.

Kali's **Everything** image is specifically intended for offline scenarios and is over 9 GB because it contains a large collection of tools. ([Kali Linux](https://www.kali.org/docs/introduction/what-image-to-download/?utm_source=chatgpt.com))

Ollama runs the model locally on Linux and supports CPU/GPU execution. ([GitHub](https://github.com/ollama/ollama/blob/main/docs/linux.mdx?utm_source=chatgpt.com))

---

## But there is an important question: what hardware do you have?

The answer changes **dramatically** depending on your GPU/RAM.

Roughly:

| Hardware | Practical local LLM |
|---|---|
| 16 GB RAM, no GPU | 3B-7B quantized |
| 32 GB RAM, no GPU | 7B-14B quantized |
| 32 GB + 8 GB VRAM | 7B-14B |
| 64 GB + 12-16 GB VRAM | 14B-32B |
| 64-128 GB + 24 GB VRAM | 30B-ish quantized |
| 128 GB+ / multiple GPUs | Much larger models |

You **do not need a giant model** to make a useful security assistant.

Kali's own offline example demonstrated the setup with **Qwen3 4B** on a machine with a GTX 1060 6 GB. ([Kali Linux](https://www.kali.org/blog/kali-llm-ollama-5ire/?utm_source=chatgpt.com))

---

# And yes, we can create our own "Cybersecurity LLM"

There are actually three different levels.

### Level 1 - Local general LLM

For example:

```text
Kali
 └── Ollama
      └── Qwen
```

Give it a security-focused system prompt and it can help with:

- Nmap output interpretation
- HTTP analysis
- enumeration
- Linux commands
- log analysis
- vulnerability explanations
- CTF reasoning
- scripting
- report generation

This is the easiest approach.

### Level 2 - Security-specialized AI agent

Much more interesting:

```text
                Local LLM
                   │
             ┌─────┴─────┐
             │ MCP Layer │
             └─────┬─────┘
                   │
       ┌───────────┼───────────┐
       │           │           │
      Nmap       ffuf        SQLmap
       │           │           │
       └───────────┼───────────┘
                   │
             Result analysis
                   │
                   ▼
              Next action
```

Now you could tell it:

> Analyze my authorized lab target 10.10.10.20.

And have it:

1. perform reconnaissance
2. interpret the result
3. identify interesting services
4. select an appropriate local tool
5. run it
6. analyze output
7. continue enumeration
8. maintain findings
9. produce a report

**with you approving actions**.

Kali already has an MCP-oriented approach for connecting local LLMs to Kali tools. ([Kali Linux](https://www.kali.org/blog/kali-llm-ollama-5ire/?utm_source=chatgpt.com))

There is also an `llm-tools-nmap` package in Kali that exposes Nmap capabilities through function calling. ([Kali Linux](https://www.kali.org/tools/llm-tools-nmap/?utm_source=chatgpt.com))

---

# Level 3 - Your own cybersecurity model

This is where it gets interesting.

Instead of merely downloading a general LLM, we could build something like:

```text
                 CYBER-KALI-AI
                       │
       ┌───────────────┼────────────────┐
       │               │                │
   Reasoning       Security KB       Tools
       │               │                │
     Qwen          CVE data          Nmap
     14B           OWASP             ffuf
     /32B          MITRE             Burp
       │           Payload DB        SQLmap
       │               │             etc.
       └───────────────┼────────────────┘
                       │
                 Agent Controller
                       │
                  Kali Linux
```

But I **wouldn't start by training an LLM from scratch**.

That's enormously expensive and usually unnecessary.

Instead:

**Base model + security knowledge + RAG + tools + agent orchestration**

is much more practical.

For example:

```text
Qwen
  +
OWASP documentation
  +
CWE/CVE knowledge
  +
MITRE ATT&CK
  +
your CTF notes
  +
Kali man pages
  +
your own pentest reports
  +
tool output
  =
Cybersecurity AI
```

That can be entirely local.

---

## We could even make it specifically useful for your CTF work

For example, rather than a generic "KaliGPT", we could build:

```text
┌─────────────────────────────────────────────┐
│              LOCAL CTF AI                   │
├─────────────────────────────────────────────┤
│                                             │
│ Recon Analyzer                              │
│ ├── Nmap                                    │
│ ├── HTTP headers                             │
│ ├── robots.txt                               │
│ ├── directories                              │
│ └── technology detection                     │
│                                             │
│ Web Analyzer                                │
│ ├── SQLi                                    │
│ ├── XSS                                     │
│ ├── SSTI                                    │
│ ├── SSRF                                    │
│ ├── prototype pollution                     │
│ ├── authentication flaws                     │
│ └── API analysis                             │
│                                             │
│ Binary Analyzer                             │
│ ├── strings                                  │
│ ├── file                                     │
│ ├── Ghidra                                   │
│ ├── radare2                                  │
│ └── GDB                                      │
│                                             │
│ CTF Knowledge Base                          │
│ ├── OWASP                                    │
│ ├── CWE                                      │
│ ├── CVE                                      │
│ ├── HackTricks-like notes                    │
│ └── YOUR OWN NOTES                           │
│                                             │
└─────────────────────────────────────────────┘
```

And importantly, **everything stays on the machine**.

There are already community projects demonstrating similar local Kali assistants using Ollama and local models, although I'd treat those as starting points rather than assuming they're production-quality. ([GitHub](https://github.com/PratikGUlig/Building-a-Custom-Cybersecurity-AI-with-Ollama-on-Kali-Linux?utm_source=chatgpt.com))

### One thing I'd recommend

Don't make the AI have unrestricted root shell access.

Instead:

```text
LLM
 ↓
Agent
 ↓
Scope checker
 ↓
Tool allowlist
 ↓
Human approval
 ↓
Command
 ↓
Result
 ↓
LLM
```

That makes the system much safer and also gives you a useful audit trail.

---

If you tell me your **CPU + RAM + GPU model + GPU VRAM** (for example `i7-12700H / 32GB RAM / RTX 3060 6GB`), I can design a **fully offline Kali + LLM setup specifically for your hardware**, including the model size, Ollama configuration, local knowledge base, MCP tools, and an offline CTF/pentest-agent architecture.

---

**Sources:**

- [Kali & LLM: Completely local with Ollama & 5ire | Kali Linux Blog](https://www.kali.org/blog/kali-llm-ollama-5ire/?utm_source=chatgpt.com)
- [ollama/docs/linux.mdx at main · ollama/ollama · GitHub](https://github.com/ollama/ollama/blob/main/docs/linux.mdx?utm_source=chatgpt.com)

## Prompt:
9/19/2026, 12:07:05 AM

I have 32 GB RAM, no GPU

## Response:
9/19/2026, 12:07:07 AM

Yes. With **32 GB RAM and no GPU**, you can build a very usable **fully offline cybersecurity AI on Kali Linux**. The main limitation is speed: inference will run on CPU, so model size matters.

### Hardware-appropriate setup

I'd use:

| Component | Recommendation |
|---|---|
| OS | Kali Linux 64-bit |
| RAM | 32 GB |
| GPU | None |
| Runtime | Ollama |
| Main model | **Qwen3 8B** quantized |
| Alternative | Qwen3 14B if you accept slower responses |
| Knowledge | Local RAG database |
| Tool interface | MCP |
| UI | Open WebUI or similar local interface |
| Security tools | Kali's existing tools |
| Internet | **Not required after setup** |

A good architecture would be:

```text
                 ┌──────────────────────┐
                 │       YOU            │
                 │  Local Web Interface │
                 └──────────┬───────────┘
                            │
                            ▼
                 ┌──────────────────────┐
                 │     Cyber AI         │
                 │   Qwen 8B / 14B      │
                 │       Ollama         │
                 └───────┬───────┬──────┘
                         │       │
              ┌──────────┘       └──────────┐
              ▼                             ▼
       Local Knowledge                 MCP Tools
       ───────────────                 ─────────
       OWASP                          Nmap
       CWE                            ffuf
       CVE                            Nikto
       MITRE                          sqlmap
       Kali docs                      Gobuster
       Your CTF notes                 etc.
              │                             │
              └────────────┬────────────────┘
                           ▼
                    Analysis / Reasoning
                           │
                           ▼
                     Findings / Report
```

### 8B vs 14B

For your machine, I'd **start with 8B**.

An 8B quantized model can comfortably fit in your RAM alongside Kali and your tools. A 14B model is also possible, but CPU inference will be noticeably slower.

I would **not jump to 30B+** just because you have 32 GB RAM. Once you account for Kali, the model runtime, context, RAG database, browser, and security tools, memory gets tight.

### The really important part

The model itself isn't what makes this a good security AI.

I'd build it as:

**LLM + security knowledge + tool calling + persistent findings**

rather than simply installing a chatbot.

For example, you could give it the output of:

```text
nmap
ffuf
curl
whatweb
nikto
sqlmap
gobuster
openssl
dig
whois
```

and have the local model interpret the results and determine what information is relevant for the next stage of an **authorized lab/CTF assessment**.

You could also put your own CTF notes into its local knowledge base. That would be particularly useful for remembering patterns you've encountered, such as prototype-pollution challenges, XML-RPC behavior, API enumeration, etc.

### Completely offline

After downloading everything:

```text
Internet
   │
   │  initial installation/download
   ▼
┌───────────────────────────┐
│ Kali + models + knowledge │
└───────────────────────────┘
             │
             ▼
        DISCONNECT
             │
             ▼
┌───────────────────────────┐
│       OFFLINE MACHINE     │
│                           │
│ Ollama                    │
│ Qwen                      │
│ RAG database              │
│ MCP                       │
│ Kali tools                │
│ Local web UI              │
└───────────────────────────┘
```

No API key, OpenAI account, cloud inference, or Internet connection is necessary during operation.

**One caveat:** vulnerability databases and documentation naturally become stale when you're offline. You can periodically reconnect on a separate/update window and refresh your local CVE/OWASP/etc. datasets.

If you want, I can give you a **step-by-step build for your exact 32-GB/no-GPU machine**, starting from a fresh Kali installation and ending with a local AI that can interact with Kali tools.

## Prompt:
9/19/2026, 12:08:10 AM

Give me a step-by-step build for my exact 32-GB/no-GPU machine

## Prompt:
9/19/2026, 12:09:08 AM

Give me a step-by-step build for my exact 32-GB/no-GPU machine considering I am using Linux distro and want to create a Kali distro or image which I can install or create/kill anytime and setup everything anytime to ensure running and killing my Image and not OS. Ask clarification questions if any

## Response:
9/19/2026, 12:09:11 AM

> **Searching www.kali.org**
>
> 
>
> Worked for a couple of seconds

Yes. Given your requirement - **Linux host, 32 GB RAM, CPU-only, and the ability to create/start/stop/destroy the entire Kali environment without touching the host OS** - I would **not** make the first design a custom bootable Kali ISO.

I would build a **Kali VM appliance** and make the entire AI/security stack live inside that VM.

That gives you:

```text
YOUR EXISTING LINUX
        │
        │ KVM/QEMU
        ▼
┌──────────────────────────────────────┐
│          KALI-CYBER-AI VM            │
│                                      │
│ Kali Linux                           │
│ Ollama                               │
│ Qwen 8B                              │
│ Local security knowledge base        │
│ MCP / tool integration               │
│ Nmap / ffuf / Burp / SQLmap / etc.  │
│ Open WebUI                           │
└──────────────────────────────────────┘
        │
        ▼
   VM disk image
   kali-cyber-ai.qcow2
```

**Kill the VM → your host OS is untouched.**  
**Delete the QCOW2 → the whole environment is gone.**  
**Copy the QCOW2 → you have a snapshot/clone.**

Kali officially supports QEMU/KVM/virt-manager, and its documentation also provides instructions for testing custom Kali ISOs under QEMU. ([Kali Linux](https://www.kali.org/docs/virtualization/install-qemu-guest-vm/?utm_source=chatgpt.com))

## Before I give you the exact build commands

I need **4 details** because they materially affect the design.

### 1. What is your host Linux distro?

For example:

```text
Ubuntu 24.04
Debian 13
Fedora
Arch
Linux Mint
Parrot
```

Please give me:

```bash
cat /etc/os-release
```

You can paste the output.

---

### 2. What CPU do you have?

Run:

```bash
lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core'
```

Paste the output.

This matters because we're going to give the VM perhaps **8-12 CPU threads**, while leaving enough resources for your host.

---

### 3. How much disk space is available?

Run:

```bash
df -h /
```

And preferably:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

The AI environment will benefit from a reasonably large SSD.

I'd target approximately:

```text
Kali VM             60-100 GB
LLM models           5-15 GB
Security databases   5-20 GB
Snapshots            variable
```

You don't necessarily need all of that immediately.

---

### 4. What do you mean by "kill anytime"?

There are two possible designs.

#### A - Disposable VM

```text
Start VM
   ↓
Do work
   ↓
Shutdown
   ↓
Delete VM
```

Everything disappears.

Good for:

- CTFs
- malware analysis labs
- experiments
- risky configurations
- testing tools

#### B - Golden image + disposable clones

This is what **I recommend**.

```text
             GOLDEN IMAGE
          kali-cyber-ai-base
                  │
       ┌──────────┼──────────┐
       ▼          ▼          ▼
    CTF-01      CTF-02      Lab-03
       │          │          │
     delete     delete     delete
```

Your master Kali + AI environment remains untouched.

When you want a fresh environment:

```text
golden.qcow2
     │
     ├── clone → challenge1.qcow2
     ├── clone → challenge2.qcow2
     └── clone → experiment.qcow2
```

When finished:

```bash
rm challenge1.qcow2
```

Your host remains untouched and your **golden environment remains intact**.

This is much better than rebuilding Kali every time.

---

# The architecture I'd build for you

Assuming your answers don't reveal some unusual hardware limitation:

```text
HOST LINUX
│
├── KVM
├── QEMU
├── libvirt
└── virt-manager
       │
       ▼
══════════════════════════════════════════
       KALI CYBER AI VM
══════════════════════════════════════════
│
├── Kali Linux 2026.x
│
├── Security tooling
│   ├── Nmap
│   ├── ffuf
│   ├── Gobuster
│   ├── Nikto
│   ├── SQLmap
│   ├── WPScan
│   ├── John
│   ├── Hashcat (CPU)
│   └── other Kali tools
│
├── Local AI
│   └── Ollama
│       └── Qwen 8B
│
├── Local knowledge
│   ├── OWASP
│   ├── CWE
│   ├── CVE data
│   ├── MITRE ATT&CK
│   ├── Kali documentation
│   └── your CTF notes
│
├── AI interface
│   └── Open WebUI
│
└── Tool interface
    └── MCP
```

Kali's official package system also provides metapackages such as `kali-linux-headless`, `kali-linux-default`, and `kali-linux-core`, so we can install only what we actually need rather than turning the VM into an unnecessarily huge installation. ([Kali Linux](https://www.kali.org/docs/general-use/metapackages/?utm_source=chatgpt.com))

---

# Why I'm recommending a VM instead of a custom ISO

Kali **does** officially support custom ISO creation through `live-build`, including custom packages, files, hooks and configuration. ([Kali Linux](https://www.kali.org/docs/development/live-build-a-custom-kali-iso/?utm_source=chatgpt.com))

We could eventually create:

```text
kali-cyber-ai.iso
```

and boot/install that whenever you want.

But that's not the best first layer for your requirement.

A VM gives you:

### Snapshots

```text
Clean Kali
   │
   ├── snapshot: clean
   │
   ├── install AI
   │
   ├── install tools
   │
   └── snapshot: cyber-ai-ready
```

If something breaks:

```text
Restore → cyber-ai-ready
```

### Cloning

You can have:

```text
kali-cyber-ai-base.qcow2

ctf-2026-01.qcow2
ctf-2026-02.qcow2
web-lab.qcow2
malware-lab.qcow2
```

### Isolation

Your host remains separate.

### No OS reinstall

You don't need to repeatedly install Kali.

### Easy backup

Your entire environment becomes essentially:

```text
kali-cyber-ai-base.qcow2
```

Copy it somewhere safe.

---

# And there's another possibility

Kali also provides official Docker images. ([Kali Linux](https://www.kali.org/docs/containers/official-kalilinux-docker-images/?utm_source=chatgpt.com))

So technically we could build:

```text
Host Linux
    │
    └── Docker
          │
          └── Kali container
                ├── tools
                └── AI
```

But I **wouldn't use Docker as the primary environment for your project**.

Kali itself notes limitations around things such as systemd and hardware access in its container setup. ([Kali Linux](https://www.kali.org/docs/containers/using-kali-docker-images/?utm_source=chatgpt.com))

For your goal, I'd use:

**KVM/QEMU VM → Kali → AI/tools**

and potentially use Docker **inside the Kali VM** for individual disposable services.

---

# One more design decision

I'd actually make the AI environment modular:

```text
                    Kali VM
                       │
          ┌────────────┼─────────────┐
          │            │             │
          ▼            ▼             ▼
       Security       AI          Knowledge
        Tools       Runtime         Base
          │            │             │
          │          Ollama         RAG
          │            │             │
          └────────────┼─────────────┘
                       │
                       ▼
                  AI Agent
                       │
                       ▼
                  MCP Gateway
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
        Nmap          ffuf        SQLmap
```

Then the AI isn't given an unrestricted shell.

Instead, the agent can be designed around **explicit tool capabilities and approval**.

For example:

```text
AI:
"I want to run an Nmap scan."

        ↓

Tool controller:
"nmap --... authorized-target"

        ↓

You approve

        ↓

Nmap

        ↓

Results

        ↓

AI analyzes results
```

That is considerably more controllable than giving an LLM unrestricted root access.

---

## What I need from you

Reply with these four things:

```text
1. Host distro:
2. CPU:
3. Disk:
4. Disposable model:
   A) completely disposable
   B) golden image + disposable clones
```

For **#4**, I'd choose **B** unless you specifically want every environment to disappear completely.

Once you give me those, I'll lay out the build as an actual sequence:

```text
PHASE 0   Host preparation
PHASE 1   KVM/QEMU
PHASE 2   Kali VM
PHASE 3   Golden image
PHASE 4   Ollama
PHASE 5   CPU-optimized LLM
PHASE 6   Offline model storage
PHASE 7   Security tools
PHASE 8   Local security knowledge/RAG
PHASE 9   MCP/tool integration
PHASE 10  Local AI UI
PHASE 11  Network isolation
PHASE 12  Snapshot/clone system
PHASE 13  One-command start
PHASE 14  One-command destroy
PHASE 15  Offline operation test
```

I'll also structure it so that **after the initial downloads, you can disconnect the machine from the Internet and still run the entire AI/security environment locally**.

---

**Sources:**

- [Kali inside QEMU/LibVirt with virt-manager (Guest VM) | Kali Linux Documentation](https://www.kali.org/docs/virtualization/install-qemu-guest-vm/?utm_source=chatgpt.com)

## Prompt:
9/19/2026, 12:11:49 AM

PRETTY_NAME="Ubuntu 24.04.2 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.2 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=noble
LOGO=ubuntu-logo

CPU(s):                                  20
On-line CPU(s) list:                     0-19
Model name:                              13th Gen Intel(R) Core(TM) i5-13600K
Thread(s) per core:                      2
Core(s) per socket:                      14
CPU(s) scaling MHz:                      31%
NUMA node0 CPU(s):                       0-19

df -h /
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p2  915G  560G  309G  65% 

lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
NAME          SIZE TYPE FSTYPE   MOUNTPOINTS
loop0           4K loop squashfs /snap/bare/5
loop1        55.5M loop squashfs /snap/core18/2999
loop2        55.5M loop squashfs /snap/core18/3084
loop3        63.8M loop squashfs /snap/core20/2866
loop4        63.8M loop squashfs /snap/core20/2922
loop5          74M loop squashfs /snap/core22/2411
loop6          74M loop squashfs /snap/core22/2437
loop7        66.8M loop squashfs /snap/core24/1587
loop8        66.8M loop squashfs /snap/core24/1643
loop9       260.3M loop squashfs /snap/firefox/8763
loop10      261.1M loop squashfs /snap/firefox/8803
loop11       16.4M loop squashfs /snap/firmware-updater/223
loop12       16.5M loop squashfs /snap/firmware-updater/226
loop13      140.4M loop squashfs /snap/gimp/560
loop14      140.9M loop squashfs /snap/gimp/561
loop15      349.7M loop squashfs /snap/gnome-3-38-2004/143
loop16      531.5M loop squashfs /snap/gnome-42-2204/263
loop17      531.4M loop squashfs /snap/gnome-42-2204/247
loop18      669.8M loop squashfs /snap/gnome-46-2404/145
loop19      606.1M loop squashfs /snap/gnome-46-2404/153
loop20        395M loop squashfs /snap/mesa-2404/1165
loop21       91.7M loop squashfs /snap/gtk-common-themes/1535
loop22      363.4M loop squashfs /snap/metasploit-framework/2395
loop23        366M loop squashfs /snap/metasploit-framework/2435
loop24        402M loop squashfs /snap/mesa-2404/1839
loop25      110.6M loop squashfs /snap/obsidian/67
loop26      110.6M loop squashfs /snap/obsidian/68
loop27       15.7M loop squashfs /snap/snap-store/1367
loop28       50.1M loop squashfs /snap/snapd/27710
loop29       11.8M loop squashfs /snap/snap-store/1390
loop30       50.3M loop squashfs /snap/snapd/27738
loop31        580K loop squashfs /snap/snapd-desktop-integration/361
loop32        828K loop squashfs /snap/snapd-desktop-integration/391
loop33      143.8M loop squashfs /snap/spotify/99
loop34      175.5M loop squashfs /snap/spotify/97
nvme0n1     931.5G disk          
├─nvme0n1p1     1G part vfat     /boot/efi
└─nvme0n1p2 930.5G part ext4     /home/sandeep03edu-ubuntu/shared/distributed_video_sync_party
                                 /

Will go with Golden image + disposable clones

Ask any other questions if any or give me the complete process and also will my AI be very slow considering I am running it locally without GPU?

## Response:
9/19/2026, 12:11:52 AM

> **Searched 2 websites**
>
> 
>
> Worked for 6s

Your hardware is actually a **good fit for this project**. The i5-13600K gives you 20 logical CPUs, and your 309 GB free space gives us enough room for a fairly substantial VM + models + snapshots.

And yes: **CPU-only will be slower than a GPU**, but I don't think it will be unusably slow if we choose the model correctly. For your machine I'd start with **Qwen3 8B Q4_K_M**, which is about 5.2 GB in Ollama. ([Ollama](https://ollama.com/library/qwen3%3A8b?utm_source=chatgpt.com))

I would **not** start with a 30B/32B model. Qwen3 14B is about 9.3 GB and 30B about 19 GB just for the model, which becomes increasingly uncomfortable once Kali, the VM, RAG, browser, and tools are running. ([Ollama](https://ollama.com/library/qwen3?utm_source=chatgpt.com))

## The design I recommend

```text
                    UBUNTU 24.04 HOST
                    32 GB RAM
                    i5-13600K
                         │
                         │ KVM/QEMU
                         ▼
          ┌───────────────────────────────┐
          │       KALI GOLDEN VM          │
          │                               │
          │  20 GB RAM                    │
          │  10 vCPU                      │
          │  80-100 GB virtual disk       │
          │                               │
          │  Kali Linux                   │
          │  Ollama                       │
          │    └── Qwen3 8B               │
          │  Open WebUI                   │
          │  RAG / Knowledge Base         │
          │  MCP                          │
          │  Security Tools               │
          └───────────────┬───────────────┘
                          │
                  clone / snapshot
                          │
          ┌───────────────┼────────────────┐
          ▼               ▼                ▼
       CTF-01           CTF-02          WEB-LAB
      disposable       disposable      disposable
```

KVM/libvirt is the right base here. Ubuntu documents KVM/libvirt and `virt-manager` for managing VMs, while Kali has an official QEMU/libvirt/virt-manager installation guide. ([Ubuntu](https://ubuntu.com/server/docs/how-to/virtualisation/libvirt/?utm_source=chatgpt.com))

---

# First: your resource allocation

I recommend:

| Resource | Host | Kali VM |
|---|---:|---:|
| RAM | ~12 GB | **20 GB** |
| CPU threads | 10 available | **10 vCPU** |
| Disk | ~200+ GB free | **100 GB max** |
| GPU | - | none |
| Network | normal | NAT initially |

Don't permanently give the VM all 20 CPU threads or all 32 GB RAM. Your Ubuntu desktop needs resources too.

We can tune this later after measuring actual performance.

---

# Phase 1 - Verify virtualization

On Ubuntu:

```bash
sudo apt update
sudo apt install -y cpu-checker
kvm-ok
```

You want:

```text
KVM acceleration can be used
```

Ubuntu specifically recommends `kvm-ok` for checking hardware virtualization. ([Ubuntu](https://ubuntu.com/server/docs/how-to/virtualisation/libvirt/?utm_source=chatgpt.com))

Also run:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

You should get a number greater than `0`.

Your 13600K supports Intel VT-x, so the main thing to check is that virtualization hasn't been disabled in firmware.

---

# Phase 2 - Install the VM stack

Install:

```bash
sudo apt install -y \
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    virt-manager \
    virt-viewer \
    bridge-utils \
    ovmf \
    cpu-checker
```

Then:

```bash
sudo usermod -aG libvirt "$USER"
sudo usermod -aG kvm "$USER"
```

**Log out and log back in** afterward.

Verify:

```bash
virsh --connect qemu:///system list --all
```

You should see an empty VM list initially.

Ubuntu documents `qemu-kvm`, `libvirt-daemon-system`, the `libvirt` group, `virsh`, and `virt-manager` as the standard stack. ([Ubuntu](https://ubuntu.com/server/docs/how-to/virtualisation/libvirt/?utm_source=chatgpt.com))

---

# Phase 3 - Create the storage layout

Don't put the VM inside random directories.

Create:

```bash
mkdir -p ~/CyberAI/{iso,images,backups,scripts}
```

We'll eventually have something like:

```text
~/CyberAI/
├── iso/
│   └── kali-linux.iso
│
├── images/
│   ├── kali-cyber-ai-golden.qcow2
│   ├── ctf-01.qcow2
│   ├── ctf-02.qcow2
│   └── web-lab.qcow2
│
├── backups/
│
└── scripts/
```

**Important:** your current disk has ~309 GB available, so don't create dozens of huge full copies. We'll use **QCOW2 backing files / clones** so disposable environments don't consume the full 100 GB each.

---

# Phase 4 - Download Kali

For the VM, use the current official **Kali Installer ISO**, not a prebuilt VMware image.

Download it from Kali's official download page and verify its SHA256 checksum before installation.

Then put it here:

```text
~/CyberAI/iso/kali-linux.iso
```

I'm deliberately not hard-coding the filename because Kali's current release filename changes.

---

# Phase 5 - Create the Golden VM

Start:

```bash
virt-manager
```

Create a new VM.

Select:

```text
Local install media
```

Choose your Kali ISO.

For resources:

```text
RAM:       20480 MB
CPUs:      10
Disk:      100 GB
```

For the disk, choose:

```text
qcow2
```

rather than raw.

Name:

```text
kali-cyber-ai-golden
```

Kali's own QEMU/libvirt guide uses `virt-manager` for this workflow. ([Kali Linux](https://www.kali.org/docs/virtualization/install-qemu-guest-vm/?utm_source=chatgpt.com))

---

# Phase 6 - Kali installation

Install a normal Kali desktop.

For your use case I'd choose:

```text
Xfce
```

rather than a heavier desktop.

After installation:

```bash
sudo apt update
sudo apt full-upgrade -y
```

Then:

```bash
sudo reboot
```

---

# Phase 7 - Install the Kali toolset

Don't install literally everything immediately.

Start with:

```bash
sudo apt install -y \
    nmap \
    ffuf \
    gobuster \
    nikto \
    sqlmap \
    wpscan \
    curl \
    wget \
    git \
    jq \
    ripgrep \
    tmux \
    python3 \
    python3-pip \
    python3-venv \
    build-essential
```

Then add other Kali tools as you actually need them.

This keeps the golden image manageable.

---

# Phase 8 - Install Ollama inside Kali

This is where the local AI begins.

Install Ollama **inside the VM**, not on Ubuntu.

Then verify:

```bash
ollama --version
```

and:

```bash
systemctl status ollama
```

The important architecture is:

```text
Ubuntu
   │
   └── KVM
        │
        └── Kali
             │
             └── Ollama
                  │
                  └── Qwen
```

Therefore, killing the Kali VM kills the AI environment too.

Your Ubuntu installation doesn't depend on Ollama.

---

# Phase 9 - Download our first model

Inside Kali:

```bash
ollama pull qwen2.5:3b-instruct
```

Then:

```bash
ollama run qwen2.5:3b-instruct
```

The current Ollama Qwen3 8B package is approximately **5.2 GB and Q4_K_M**, with tool-calling/thinking support. ([Ollama](https://ollama.com/library/qwen3%3A8b?utm_source=chatgpt.com))

Test:

```text
Explain the following Nmap output and identify which findings deserve further investigation.
```

Exit with:

```text
/bye
```

Then:

```bash
ollama list
```

---

# How slow will it actually be?

This is the most important part.

### Your CPU

```text
i5-13600K
14 cores
20 threads
```

is significantly better for CPU inference than an ordinary laptop CPU.

But it is still nowhere near a modern dedicated GPU for LLM inference.

With an 8B quantized model, expect **interactive but not instant** responses.

Think roughly:

```text
Small/simple response
      ↓
feels reasonably responsive

Long reasoning response
      ↓
you wait

Large context + RAG + thinking
      ↓
noticeably slower
```

I don't want to give you a fake guaranteed tokens/sec number because actual performance depends on context length, Ollama/llama.cpp version, CPU frequency, quantization, and concurrent processes.

The correct way is to **benchmark your exact machine after installation**.

We can do that with a fixed prompt and record:

```text
tokens/sec
time to first token
total generation time
RAM usage
CPU utilization
```

Then we'll decide whether 8B is sufficient or whether your machine can comfortably handle 14B.

---

# A very important optimization

Don't leave Qwen3 in "thinking" mode for everything.

For example:

```text
Normal mode:
    quick analysis
    command explanation
    parsing output
    documentation

Thinking mode:
    complex CTF reasoning
    multi-step vulnerability analysis
    exploit-chain reasoning
    debugging
```

Otherwise you're spending CPU cycles unnecessarily.

---

# Phase 10 - Open WebUI

I recommend adding Open WebUI after Ollama works.

It gives you a browser interface:

```text
http://127.0.0.1:3000
```

and can connect to Ollama.

Open WebUI is designed to run locally/offline and supports Ollama, knowledge bases, persistent conversations, and extensions. ([Open WebUI](https://docs.openwebui.com/?utm_source=chatgpt.com))

There are two ways we could install it.

### Option A - Python

Less infrastructure.

### Option B - Docker

Cleaner isolation.

For **your project**, I'd choose Docker **inside the Kali VM**:

```text
Kali
│
├── Ollama
│
├── Security tools
│
└── Docker
     └── Open WebUI
```

Then destroying a clone destroys the WebUI container too.

Open WebUI officially supports a CPU-only Docker deployment. ([Open WebUI](https://docs.openwebui.com/getting-started/quick-start/?utm_source=chatgpt.com))

---

# Phase 11 - Build the security knowledge base

This is where the project becomes significantly more useful.

Instead of asking:

```text
"What's SQL injection?"
```

we want:

```text
"What does this specific response indicate,
which vulnerability classes are relevant,
and what evidence should I collect next?"
```

We'll create a local knowledge directory:

```text
/opt/cyber-ai/knowledge/
```

Something like:

```text
knowledge/
├── owasp/
├── cwe/
├── mitre/
├── kali/
├── web-security/
├── linux/
├── networking/
├── ctf/
└── personal-notes/
```

Your own CTF notes can go in:

```text
personal-notes/
```

That is particularly useful because you can feed the system your previous challenge writeups.

---

# Phase 12 - RAG

The next layer is:

```text
User question
      │
      ▼
Local embedding model
      │
      ▼
Knowledge database
      │
      ▼
Relevant documents
      │
      ▼
Qwen3
      │
      ▼
Answer
```

This is much better than stuffing every security document into the model's context.

And it remains offline.

We can use a lightweight local vector database; you don't need a huge infrastructure stack.

---

# Phase 13 - MCP/tool layer

Eventually we'll add:

```text
Qwen
  │
  ▼
MCP
  │
  ├── nmap
  ├── ffuf
  ├── curl
  ├── whatweb
  ├── gobuster
  ├── nikto
  └── sqlmap
```

This is where it starts behaving like an actual **security agent** rather than ChatGPT sitting inside Kali.

For example:

```text
You:

Analyze 192.168.56.101 in my lab.
```

AI:

```text
I need service enumeration.
```

↓

MCP invokes an approved Nmap capability.

↓

```text
22/tcp SSH
80/tcp HTTP
3306/tcp MySQL
```

↓

AI analyzes it.

↓

```text
HTTP requires enumeration.
```

↓

ffuf/etc.

↓

AI analyzes results.

---

# But don't give it unrestricted root

I'd specifically design the tool layer as:

```text
                 AI
                  │
                  ▼
           Tool Controller
                  │
       ┌──────────┴──────────┐
       │                     │
   Allowed tool          Approval
       │                     │
       └──────────┬──────────┘
                  ▼
                Tool
```

For example, initially:

```text
nmap       ALLOW
curl       ALLOW
dig        ALLOW
ffuf       APPROVAL
sqlmap     APPROVAL
metasploit APPROVAL
shell      DENY
```

Then expand capabilities as you test the system.

This also makes the system safer when you're experimenting with autonomous behavior.

---

# Phase 14 - Network architecture

Initially:

```text
Kali VM
   │
   ▼
libvirt NAT
   │
   ▼
Ubuntu
   │
   ▼
Internet
```

That's the safest starting point.

Later we can create **two virtual networks**:

```text
                    Kali
                      │
             ┌────────┴────────┐
             │                 │
          NAT net          LAB network
             │                 │
          Internet        10.10.x.x
                               │
                        vulnerable VMs
```

That lets you create an isolated penetration-testing lab.

For example:

```text
Kali AI
  │
  ├── WebGoat
  ├── DVWA
  ├── Metasploitable
  └── intentionally vulnerable VMs
```

while keeping the lab separated from your real LAN.

---

# Phase 15 - Golden image

Once all of this works:

```text
Kali
  +
Ollama
  +
Qwen
  +
Open WebUI
  +
knowledge base
  +
security tools
  +
MCP
```

**STOP.**

This becomes:

```text
kali-cyber-ai-golden
```

Shut it down:

```bash
virsh shutdown kali-cyber-ai-golden
```

Then back it up.

Do **not** experiment directly on the golden image afterward.

---

# Phase 16 - Disposable clones

Now:

```text
                    GOLDEN
                      │
           ┌──────────┼──────────┐
           ▼          ▼          ▼
         CTF01      CTF02      LAB01
```

You can create clones using libvirt's cloning facilities; Ubuntu documents `virt-clone` for this purpose. ([Ubuntu](https://ubuntu.com/server/docs/how-to/virtualisation/virtual-machine-manager/?utm_source=chatgpt.com))

Example:

```bash
virt-clone \
  --connect qemu:///system \
  --original kali-cyber-ai-golden \
  --name ctf-01 \
  --auto-clone
```

Then:

```bash
virsh start ctf-01
```

Work inside it.

When finished:

```bash
virsh shutdown ctf-01
```

and if you no longer need it:

```bash
virsh destroy ctf-01
virsh undefine ctf-01 --remove-all-storage
```

**Be careful with `--remove-all-storage`**: it permanently removes that VM's storage.

Your golden VM remains untouched.

---

# Even better: snapshots

Inside a disposable VM:

```text
CTF-01
  │
  ├── clean
  │
  ├── after-recon
  │
  ├── after-exploit
  │
  └── broken-state
```

Then:

```bash
virsh snapshot-create-as ctf-01 clean
```

If something goes wrong, restore the snapshot.

---

# Phase 17 - One-command environment management

Eventually I'll have you create:

```text
~/CyberAI/scripts/
├── start.sh
├── stop.sh
├── new-lab.sh
├── destroy-lab.sh
├── snapshot.sh
└── restore.sh
```

So you'll be able to do:

```bash
./start.sh
```

and get:

```text
Kali AI environment started
Open WebUI: http://localhost:3000
```

And:

```bash
./stop.sh
```

to kill it.

And:

```bash
./new-lab.sh ctf-2026-09
```

to create a fresh clone.

And:

```bash
./destroy-lab.sh ctf-2026-09
```

to completely remove the disposable environment.

That's the workflow I'd ultimately aim for.

---

# Your offline requirement

After the initial installation/download stage:

```text
Internet
    │
    │ INITIAL ONLY
    ▼
┌──────────────────────────┐
│ Kali ISO                 │
│ Ollama                   │
│ Qwen3                    │
│ Docker images            │
│ RAG data                 │
│ Security documentation   │
└─────────────┬────────────┘
              │
              ▼
          DISCONNECT
              │
              ▼
┌────────────────────────────────────┐
│           KALI VM                  │
│                                    │
│ Qwen3 ─── local                    │
│ Ollama ── local                    │
│ WebUI ──── local                   │
│ RAG ────── local                   │
│ MCP ────── local                   │
│ Nmap ───── local                   │
│ ffuf ───── local                   │
│ etc.                               │
└────────────────────────────────────┘
```

Open WebUI explicitly supports an offline/local deployment model. ([Open WebUI](https://docs.openwebui.com/?utm_source=chatgpt.com))

The only thing you lose while offline is **fresh external information**. Your local CVE/security knowledge will become stale unless you periodically update it.

---

# What about a bigger model?

Once 8B is working, we benchmark it.

Then potentially:

```text
Qwen3 4B
   ↓
Qwen3 8B       ← START HERE
   ↓
Qwen3 14B      ← TEST LATER
   ↓
Qwen3 30B      ← probably not worth it on this machine
```

The current Ollama catalogue lists approximately:

```text
4B    2.5 GB
8B    5.2 GB
14B   9.3 GB
30B   19 GB
32B   20 GB
```

for the Qwen3 variants. ([Ollama](https://ollama.com/library/qwen3?utm_source=chatgpt.com))

The model file size isn't the same thing as total runtime memory, because context/KV cache and other processes also consume RAM.

---

# Your 32 GB machine is therefore quite workable

I'd characterize it like this:

```text
CPU-only Qwen 4B     ████████████████████  Fast
CPU-only Qwen 8B     ███████████████      Good ← target
CPU-only Qwen 14B    ██████████           Slow but usable
CPU-only Qwen 30B    █████                Too heavy for this design
```

Those bars are **qualitative**, not benchmark measurements.

Your 13600K is the reason I'm comfortable recommending 8B rather than telling you that CPU-only AI will be painfully slow.

---

# One change I'd make to my earlier recommendation

I initially suggested 20 GB VM RAM, and **I still think that's right**, but don't allocate it until we've verified your Ubuntu desktop's normal memory usage.

Run:

```bash
free -h
```

on Ubuntu.

If your host is normally using only 5-7 GB:

```text
32 GB
 ├── Ubuntu     ~8-10 GB
 └── Kali       20 GB
```

is excellent.

If Ubuntu is already consuming 12-15 GB:

```text
32 GB
 ├── Ubuntu     ~14 GB
 └── Kali       18 GB
```

would be safer.

---

## One thing I want you to do **before installing anything**

Don't start blindly executing the entire build yet.

Run these **four diagnostic commands on Ubuntu**:

```bash
kvm-ok
```

```bash
free -h
```

```bash
ls -lh /dev/kvm
```

```bash
systemd-detect-virt
```

Paste their output.

Then I'll give you **Phase 1 → Phase 2 as exact commands for your Ubuntu 24.04.2 installation**, and we'll build this incrementally rather than giving you 50 commands at once. That way, if KVM, networking, storage, or the VM configuration behaves differently on your machine, we catch it before building the AI stack.

And yes - **the final architecture will let you start a disposable Kali+AI environment, use it, kill it, destroy it, and recreate a fresh copy from the golden image without reinstalling or modifying Ubuntu.**

---

**Sources:**

- [qwen2.5:3b-instruct](https://ollama.com/library/qwen3%3A8b?utm_source=chatgpt.com)
- [Libvirt - Ubuntu Server documentation](https://ubuntu.com/server/docs/how-to/virtualisation/libvirt/?utm_source=chatgpt.com)
- [Kali inside QEMU/LibVirt with virt-manager (Guest VM) | Kali Linux Documentation](https://www.kali.org/docs/virtualization/install-qemu-guest-vm/?utm_source=chatgpt.com)
- [Home / Open WebUI](https://docs.openwebui.com/?utm_source=chatgpt.com)

## Prompt:
9/19/2026, 7:25:19 PM

Okay so now, before I start performing above steps, I want to confirm few and want some plan whcih can help me doing my requirements:
1) I am not only going to use a single LLM model, and I will use different LLM models, so I do not want a specific instruction which is only applicable to one LLM and I am looking for a generic architecture following which I can create multiple different VM with different LLM
2) I will be using a Pendrive or harddisk to store my different VMs if possible, such that I can just use a specific VM by picking it from storage and can be used on any machine allowing virtual box
3) The kali Linux VM will also need to setup multiple tools such as Burp suite, or I might use different tools which might not be available on Kali and I might need to run a script everytime I create a VM which might not be an ideal way, I need to make sure each of VM contain the tools which I want without manually doing that from each VM
4) Since VM might need some RAG and I also might need to pass a same RAG over multiple VMs, So i do not want to pass a single RAG to one and then to another, instead I want a complete generic process which I can follow such that I can use the same RAG over different VMs or maybe I can update all VMs by one process to have the latest RAG.
5) Since, right now I am unsure about how fast and good my custom AI will be, I will be also installing the opencode in the VM to see and compare how fast these two can work

MY main motive behind these questions is that today, I will create a VM with some setting and tomorrow I will create another, so I do not want to use manual process to create different VMs as much as possible. I know some processes might not have the automations but I want to keep the setup as generic and independent as possible.

Please ask question as much as possible if blockers and then  give me the best solution

## Response:
9/19/2026, 7:25:27 PM

Yes — your requirements change the design significantly. Instead of building a “Kali + one AI” VM, I’d build a **portable VM platform** with separate reusable layers: base OS, tools, AI runtimes/models, and a shared RAG appliance.

> **Designing the architecture**
>
> I’d separate portable project VMs from a shared RAG appliance VM. I’m evaluating host independence, VirtualBox packaging, offline operation, model-provider abstraction, centralized updates, and safe resource limits before proposing a build sequence.
>
> **Designed the architecture**
>
> 
>
> ****
>
> 
>
> **Searched 2 websites**
>
> 
>
> Worked for 13s

Your five requirements point to a **different architecture than the one I initially proposed**, and I think your instinct is correct: we should design the system as an **image factory + reusable services**, not as a manually configured Kali VM.

The key idea is:

> **Never manually build VM #2. Define what a VM contains, then generate VM #2 from the same automation.**

And we should avoid coupling the architecture to Qwen, Ollama, OpenCode, or any single LLM.

## The architecture I recommend

```text
                         YOUR UBUNTU HOST
                              │
                         VirtualBox
                              │
             ┌────────────────┼────────────────┐
             │                │                │
             ▼                ▼                ▼
       Kali Base VM      RAG Service VM    Optional Lab VMs
             │
       ┌─────┴─────┐
       │           │
       ▼           ▼
   AI-VM-A      AI-VM-B
   Qwen/etc     Llama/etc
       │           │
       └─────┬─────┘
             │
             ▼
       Shared RAG VM
```

But there is an important second layer:

```text
             IMAGE FACTORY
                  │
          ┌───────┴────────┐
          │                │
       Packer           Ansible
          │                │
          └───────┬────────┘
                  │
                  ▼
       Reproducible VM images
```

So your storage could eventually look like:

```text
CyberAI/
│
├── factory/
│   ├── packer/
│   ├── ansible/
│   ├── scripts/
│   └── profiles/
│
├── images/
│   ├── kali-base.ova
│   ├── kali-qwen.ova
│   ├── kali-llama.ova
│   ├── kali-opencode.ova
│   └── rag-server.ova
│
├── models/
│   └── model manifests/
│
├── rag/
│   ├── documents/
│   └── configuration/
│
└── labs/
```

This is much closer to what you're describing.

---

# 1. Don't make the architecture LLM-specific

**Absolutely agree.**

I would *not* make:

```text
Kali
└── Qwen
    └── special configuration
```

Instead make:

```text
Kali
│
├── LLM Runtime
│
├── Model Provider
│
├── Agent Interface
│
└── Security Tools
```

The LLM runtime could be one of:

```text
Ollama
llama.cpp
vLLM
OpenAI-compatible local server
other compatible runtime
```

And the models could be:

```text
Qwen
Llama
Mistral
Gemma
DeepSeek
etc.
```

OpenCode is also compatible with local Ollama models through its provider configuration, so we can treat OpenCode as an **application/agent layer**, not as the underlying model infrastructure. ([OpenCode](https://opencode.ai/docs/providers?utm_source=chatgpt.com))

So conceptually:

```text
                 AI PLATFORM
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
       Ollama     llama.cpp   Other
          │
     ┌────┼───────────────┐
     ▼    ▼               ▼
   Qwen  Llama          Mistral
```

That's much more future-proof.

---

# 2. Portable VMs on USB/HDD

Yes, this is possible.

But I recommend an **external SSD**, not an ordinary pendrive.

Your VM contains:

- OS
- applications
- databases
- models
- potentially tens of GB of data

A cheap USB flash drive will become a major performance bottleneck and may experience considerable write wear.

An external USB 3.x/NVMe SSD is much better.

### VirtualBox portability

VirtualBox can export machines as **OVF/OVA appliances**, which are specifically designed to move a VM between VirtualBox installations. Packer also officially supports producing VirtualBox OVF/OVA artifacts. ([HashiCorp Developer](https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/vm?utm_source=chatgpt.com))

So you can have:

```text
External SSD
│
├── Kali-Qwen.ova
├── Kali-Llama.ova
├── Kali-OpenCode.ova
├── RAG.ova
└── manifests/
```

On another machine:

```text
VirtualBox
    ↓
Import Appliance
    ↓
Kali-Qwen.ova
    ↓
Run
```

### One important caveat

"Any machine with VirtualBox" isn't literally guaranteed.

The target machine still needs:

- compatible CPU architecture, normally x86-64 for your images
- hardware virtualization
- enough RAM
- enough disk space
- a compatible VirtualBox version
- appropriate networking/USB support

For your use case I'd standardize on:

```text
Architecture: x86-64
Firmware: EFI
VirtualBox: reasonably recent version
Guest: Kali x86-64
```

---

# 3. Your Burp/tools requirement

This is where **Packer + Ansible** becomes extremely useful.

Instead of:

```text
Create VM
↓
Install Kali
↓
Install Burp
↓
Install tool X
↓
Install tool Y
↓
Configure X
↓
Configure Y
```

you define:

```text
kali-base
    +
security-tools.yml
    +
applications.yml
    +
configuration.yml
```

and the image factory produces:

```text
kali-security-base.ova
```

HashiCorp's VirtualBox Packer builder is specifically capable of creating a VM, provisioning it, and exporting the result as an OVF/OVA artifact. ([HashiCorp Developer](https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/vm?utm_source=chatgpt.com))

Packer's purpose is essentially what you're asking for: reproducibly create machine images from a defined configuration. ([HashiCorp Developer](https://developer.hashicorp.com/packer/docs/intro?utm_source=chatgpt.com))

---

# 4. The important distinction: Base vs Profile

I would create **two layers of automation**.

### Layer A - Base Kali

Contains:

```text
Kali
├── system updates
├── VirtualBox guest support
├── common CLI utilities
├── Python
├── Git
├── Docker
├── common security tools
├── Burp
└── your standard configuration
```

This becomes:

```text
kali-security-base
```

### Layer B - Profiles

Then define:

```text
profiles/
├── qwen
├── llama
├── mistral
├── opencode
├── research
└── minimal
```

For example:

```text
kali-security-base
        │
        ├── + Qwen profile
        │       ↓
        │   kali-qwen.ova
        │
        ├── + Llama profile
        │       ↓
        │   kali-llama.ova
        │
        └── + OpenCode profile
                ↓
            kali-opencode.ova
```

Now adding another model isn't a redesign.

You create another profile.

---

# 5. RAG - I would NOT put it inside each VM

This is the biggest architectural change I recommend.

You said:

> I want the same RAG across multiple VMs and update it once.

Exactly.

Don't do:

```text
Kali-Qwen
└── RAG

Kali-Llama
└── RAG

Kali-Mistral
└── RAG
```

That's duplication and maintenance hell.

Instead:

```text
                    RAG SERVER
                        │
              ┌─────────┼─────────┐
              │         │         │
              ▼         ▼         ▼
           Qwen VM   Llama VM  OpenCode VM
```

The RAG service becomes its own VM/appliance.

---

# 6. The RAG appliance

I'd make:

```text
rag-server.ova
```

containing something like:

```text
RAG VM
│
├── Document storage
│
├── Embedding model
│
├── Vector database
│
├── Retrieval API
│
└── Update/indexing service
```

For example:

```text
                    ┌────────────────────┐
                    │    RAG VM          │
                    │                    │
Documents ─────────►│ ingestion          │
                    │       ↓            │
                    │ embeddings         │
                    │       ↓            │
                    │ vector DB           │
                    │       ↓            │
                    │ retrieval API       │
                    └─────────┬──────────┘
                              │
               ┌──────────────┼──────────────┐
               ▼              ▼              ▼
             Qwen           Llama         OpenCode
```

Then you update **one thing**:

```text
RAG documents
     ↓
Re-index
     ↓
RAG server updated
     ↓
ALL AI VMs immediately see new knowledge
```

No rebuilding Qwen.

No rebuilding Llama.

No copying the RAG database.

No repeating installation.

That's exactly the kind of separation you're looking for.

---

# 7. And the RAG itself should have a source directory

I'd make your authoritative knowledge source something like:

```text
CyberAI-RAG/
│
├── sources/
│   ├── owasp/
│   ├── cwe/
│   ├── mitre/
│   ├── kali/
│   ├── linux/
│   ├── networking/
│   ├── web/
│   ├── ctf/
│   └── personal/
│
├── metadata/
│
└── manifests/
```

The RAG VM reads from that.

Then:

```bash
rag-update
```

does:

```text
sources/
    ↓
parse
    ↓
chunk
    ↓
embed
    ↓
vector DB
```

All your AI VMs continue using the same RAG API.

---

# 8. This also solves your portability problem

Suppose tomorrow you're on another computer.

Take:

```text
CyberAI SSD
│
├── VMs/
│   ├── kali-qwen.ova
│   ├── kali-llama.ova
│   ├── kali-opencode.ova
│   └── rag-server.ova
│
└── RAG/
    └── source documents
```

Import:

```text
rag-server.ova
```

Then:

```text
kali-qwen.ova
```

and configure the Qwen VM to use:

```text
http://RAG-SERVER:PORT
```

Same RAG.

---

# 9. One thing I would change from the original design

Initially I was thinking:

```text
Kali VM
└── RAG
```

I **no longer recommend that for your project**.

Your requirements clearly justify:

```text
              ┌──────────────┐
              │ RAG Appliance│
              └──────┬───────┘
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
    Kali-Qwen    Kali-Llama   Kali-OpenCode
```

This is much cleaner.

---

# 10. OpenCode

Your idea of comparing your own AI against OpenCode is also fine.

But again, we shouldn't architect around OpenCode.

Think:

```text
                    AI VM
                     │
        ┌────────────┼────────────┐
        │            │            │
      Ollama       OpenCode      Other
        │            │
        ▼            ▼
      Models       Models
        │            │
        └──────┬─────┘
               ▼
             RAG
```

OpenCode can use Ollama as a local provider, so you can experiment with the same local model through different interfaces/agents. ([OpenCode](https://opencode.ai/docs/providers?utm_source=chatgpt.com))

That actually gives you a nice experiment:

```text
Qwen + Ollama
       vs
Qwen + OpenCode
       vs
Llama + Ollama
       vs
Llama + OpenCode
```

while keeping:

```text
Kali tools
RAG
network
VM resources
```

consistent.

That's a much more meaningful comparison.

---

# 11. Your image factory

This is the piece I think you're really asking for.

Instead of manually creating VMs, we'll maintain something like:

```text
cyber-ai-platform/
│
├── packer/
│   ├── kali-base.pkr.hcl
│   ├── kali-qwen.pkr.hcl
│   ├── kali-llama.pkr.hcl
│   └── rag-server.pkr.hcl
│
├── ansible/
│   ├── common.yml
│   ├── security-tools.yml
│   ├── burp.yml
│   ├── ollama.yml
│   ├── opencode.yml
│   └── rag.yml
│
├── profiles/
│   ├── qwen.yml
│   ├── llama.yml
│   ├── mistral.yml
│   └── opencode.yml
│
└── scripts/
    ├── build.sh
    ├── update-tools.sh
    ├── update-rag.sh
    ├── export.sh
    └── new-vm.sh
```

Then:

```bash
./build.sh qwen
```

could eventually produce:

```text
dist/
└── kali-qwen-2026.09.01.ova
```

And:

```bash
./build.sh llama
```

produces:

```text
dist/
└── kali-llama-2026.09.01.ova
```

Packer is explicitly designed to create reproducible machine images, and its VirtualBox integration can export OVF/OVA artifacts. ([HashiCorp Developer](https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/vm?utm_source=chatgpt.com))

---

# 12. Even better: version everything

I strongly recommend this.

Instead of:

```text
kali-qwen.ova
```

use:

```text
kali-qwen-v1.0.0.ova
```

and keep:

```text
manifest.json
```

containing:

```text
OS:
Kali version:
VirtualBox compatibility:
CPU:
RAM:
Tools:
Tool versions:
LLM runtime:
Models:
RAG version:
OpenCode version:
Build date:
SHA256:
```

Then you know exactly what you're testing.

For example:

```text
Experiment A
─────────────
Kali:       2026.x
Qwen:       version X
Ollama:     version Y
RAG:        v3
OpenCode:   version Z
```

versus:

```text
Experiment B
─────────────
Kali:       same
Llama:      version X
Ollama:     same
RAG:        same
OpenCode:   same
```

Now your AI comparison is actually controlled.

---

# 13. Your storage architecture

Given your **309 GB free** on the current SSD, I wouldn't immediately try to keep every possible model and VM locally.

I'd eventually have:

```text
EXTERNAL SSD
│
├── 00-factory/
│   └── source configuration
│
├── 01-images/
│   ├── kali-base.ova
│   ├── kali-qwen.ova
│   ├── kali-llama.ova
│   ├── kali-opencode.ova
│   └── rag-server.ova
│
├── 02-models/
│   └── model archives
│
├── 03-rag/
│   ├── documents
│   └── backups
│
└── 04-labs/
    ├── ctf01/
    ├── ctf02/
    └── research/
```

I would use an **external SSD**, preferably NVMe/USB 3.x, rather than a cheap flash pendrive.

---

# 14. Golden image vs OVA vs disposable clone

There's a subtle distinction here.

### Golden development VM

```text
kali-base-dev
```

This is where we modify/test the system.

### Exported golden artifact

```text
kali-base-v1.0.ova
```

This is immutable.

### Working VM

```text
ctf-2026-09
```

This is disposable.

So:

```text
SOURCE CONFIG
      │
      ▼
   PACKER
      │
      ▼
GOLDEN OVA
      │
      ├──────► VM-A
      ├──────► VM-B
      └──────► VM-C
```

If VM-C gets destroyed:

```text
destroy VM-C
```

Nothing else changes.

---

# 15. This also means we can eventually support multiple hypervisors

You specifically said VirtualBox, so we'll target VirtualBox first.

But because the configuration is separated from the image builder, we could eventually have:

```text
             SAME CONFIGURATION
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
      VirtualBox    KVM       VMware
          │          │          │
        OVA        QCOW2       VMDK
```

Packer supports multiple image builders, so this is a natural future extension. ([HashiCorp Developer](https://developer.hashicorp.com/packer/docs/builders?utm_source=chatgpt.com))

**Don't implement that now.** Just don't design ourselves into a corner.

---

# 16. The complete architecture I recommend

Putting everything together:

```text
                         HOST
                    Ubuntu 24.04
                         │
                    VirtualBox
                         │
       ┌─────────────────┼─────────────────┐
       │                 │                 │
       ▼                 ▼                 ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│ Kali-Qwen   │   │ Kali-Llama  │   │ Kali-other  │
│             │   │             │   │             │
│ Kali        │   │ Kali        │   │ Kali        │
│ tools       │   │ tools       │   │ tools       │
│ Ollama      │   │ Ollama      │   │ runtime     │
│ Qwen        │   │ Llama       │   │ model       │
│ OpenCode    │   │ OpenCode    │   │             │
└──────┬──────┘   └──────┬──────┘   └──────┬──────┘
       │                  │                 │
       └──────────────────┼─────────────────┘
                          │
                          ▼
                 ┌─────────────────┐
                 │   RAG SERVER    │
                 │                 │
                 │ Documents       │
                 │ Embeddings      │
                 │ Vector DB       │
                 │ Retrieval API   │
                 └─────────────────┘
```

And behind everything:

```text
                  IMAGE FACTORY
                       │
             ┌─────────┴─────────┐
             ▼                   ▼
           Packer             Ansible
             │                   │
             └─────────┬─────────┘
                       ▼
                 VirtualBox OVA
```

That's the architecture I would build.

---

# Questions I need answered before we start

There are a few **genuine design decisions** I don't want to guess about.

### A. Target machines

When you say:

> any machine allowing VirtualBox

do you mean:

**A1.** Other x86-64 Linux machines only  
**A2.** Linux + Windows  
**A3.** Linux + Windows + macOS Intel  
**A4.** You want the maximum possible compatibility

This affects things such as networking, Guest Additions, shared folders, and packaging.

---

### B. External storage

Are you planning to use:

**B1.** USB flash pendrive  
**B2.** External HDD  
**B3.** External SSD  
**B4.** External NVMe SSD

If you haven't bought one yet, I'd choose **B3/B4** for this project.

---

### C. Internet

Do you want the resulting VMs to work:

**C1.** Fully offline after initial build  
**C2.** Normally online, but capable of going offline  
**C3.** Mostly isolated, with controlled Internet access

I'd recommend **C2 during development → C1 for the final offline appliance**.

---

### D. RAG

Do you want the RAG to contain:

**D1.** Only security documentation  
**D2.** Security docs + CTF knowledge  
**D3.** Security docs + CTF + your own notes/reports  
**D4.** All of the above + automatically updated vulnerability intelligence

I'd recommend **D3 initially**, then add D4.

---

### E. AI models

Do you want to test:

**E1.** Only local open-weight models  
**E2.** Local models + cloud models when Internet is available  
**E3.** Local models only, but multiple model families

Given your offline goal, I'd architect for **E3**, while leaving the provider interface open enough that E2 can be added later.

---

### F. Security tools

For the initial golden Kali image, should I include:

```text
Burp Suite
Nmap
ffuf
Gobuster
Nikto
SQLmap
WPScan
Metasploit
John
Hashcat
Wireshark
tcpdump
Nuclei
httpx
Amass
DNS tools
Python security tooling
Docker
Git
```

plus a mechanism for installing **non-Kali tools automatically from a manifest**?

That's the approach I'd recommend rather than hard-coding a finite tool list.

---

### G. One particularly important question

Do you want the **RAG server to itself be a portable VM**, i.e.:

```text
RAG.ova
```

that you start alongside whichever AI VM you're testing?

I strongly recommend **yes**.

That gives you the cleanest model:

```text
                         USB SSD
                            │
              ┌─────────────┴──────────────┐
              │                            │
          RAG.ova                     AI VMs
              │                     ┌──────┼──────┐
              │                     │      │      │
              └─────────────────────┤      │      │
                                    Qwen   Llama  Other
```

Then **RAG is completely independent of the LLM**.

---

## One final important point

I would **not start by installing Kali manually and then installing everything manually**.

That would work, but it would directly contradict your long-term requirement.

Instead, our project should be built in this order:

```text
1. VirtualBox
       ↓
2. Image factory
   Packer + Ansible
       ↓
3. Reproducible Kali base
       ↓
4. Security-tool manifest
       ↓
5. RAG appliance
       ↓
6. Generic AI runtime layer
       ↓
7. Model profiles
       ↓
8. OpenCode
       ↓
9. VM export
       ↓
10. Disposable VM workflow
       ↓
11. Offline validation
       ↓
12. Portable external SSD
```

**The most important design principle is that the `.ova` files are outputs, not the source of truth.** The source of truth is our Packer/Ansible configuration. That means six months from now, if you want another Kali image, you don't manually remember what you installed six months ago-you run the build again. Packer is specifically designed around this reproducible-image workflow. ([HashiCorp Developer](https://developer.hashicorp.com/packer/docs/intro?utm_source=chatgpt.com))

If you answer **A-G**, I can turn this into the actual implementation blueprint, including the directory/repository structure, VM network topology, image-building pipeline, RAG appliance design, model-provider abstraction, OpenCode integration, and the exact order in which we should build it.

---

**Sources:**

- [Providers | OpenCode](https://opencode.ai/docs/providers?utm_source=chatgpt.com)
- [VirtualBox Builder | Integrations | Packer | HashiCorp Developer](https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/vm?utm_source=chatgpt.com)

## Prompt:
9/19/2026, 8:10:02 PM

> ### F. Security tools

10. OpenCode

So ai am concerned about using only opencode, but I do not want myself to be restricted to locla LLM only such as Ollama and I want to make sure I can have an option to use different server based LLM such as Claude, codex, deepseek, opencode and all other and these might have different ways

### A. Target machines

Consider my linux machine as the only target machine, however in future I might use windows so just help me how it will vary consideirng all architecture, CPU remains appropriate for the VM, but currently just assume previously mentioned Linux machine as the only target machine

 B. External storage
Based on discussion, I will move from USB Flash Pendrive to some External SSD as I have not bought anything and will buy in future, I already have a external HDD but that I feel might be slow.

C. Internet
I want the Kali VM to be isolated such that anything happening inside the VM should not affect my host Linux machine and I also want an option where I can actually use the internet inside the VM and what does fully offline means here? I want to access Internt inside my VM and also an option or flag by which I can make my Kali VM accessible outside (only if allowed) but it should always be sandboxed and I also want to make a path by which I can pass some files in between the VM but that does not mean I want to break the sandbox nature, I want to transfer few files between the VM and host but I feel I can also look for a temporary python server which might be helpful

### D. RAG

Security documentation is compulsory and It should also contain the real-time updates of documentation and not relying on previous informations and I also want to know if we can also add few more techniques which the hackers in the wild are actually using? How can i make sure my RAG is up to date with new information? What if a new CVE or let's say new way to perform assessment. How can i make sure I have the latest attack vector, updated information and all real-time exploits informations with least false positives?

E. AI models
I want to use both Local models as well as cloud based models as I do not want myself to be completely dependent on just one local LLM Model and should have freedom to use the cloud based model as well 

### F. Security tools

I want all of these tools and might add few more in future, also how can i install burp suite extensions automatically such as Turbo intruder and other? By avoiding the manual setup

### G. One particularly important question

Yes, that feels like a good solution but I also want to make sure my Kali VM gets sufficient ram and RAG VM should not impact my kali VM performance

Ask new questions if any or else if eevrything is clear give me the latest architecture which I can use to perform the complete setup

## Response:
9/19/2026, 8:10:08 PM

I’d make one major change: **OpenCode, Ollama, Claude, Codex, DeepSeek, etc. should all be providers behind a generic AI gateway/profile layer**, while Kali tools and RAG remain independent. This prevents the VM architecture from becoming tied to any one AI product.

> **Searched 1 website**
>
> 
>
> Worked for 16s

Yes. With your clarified requirements, I would **change the architecture substantially** from the earlier “Kali VM + Ollama + RAG” design.

The system should be built as a **portable, reproducible Cybersecurity AI platform**, where:

- Kali is independent of the AI provider.
- OpenCode is one client/agent, **not the foundation**.
- Local and cloud models coexist.
- Claude, OpenAI/Codex, DeepSeek, Ollama, etc. can be used through their native interfaces.
- Security tools are installed from manifests, not manually.
- Burp configuration/extensions are reproducible.
- RAG is a separate shared service.
- Internet access is a switchable VM capability.
- Host ↔ VM file transfer is explicitly controlled.
- VM images can be cloned/exported/imported.
- The entire environment can be rebuilt from configuration.

I would call the overall design something like **CyberAI Platform**.

---

# 1. The final architecture

The most important change is this:

```text
                         UBUNTU HOST
                     Ubuntu 24.04.2 LTS
                     i5-13600K / 32 GB
                             │
                         VirtualBox
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
          ▼                  ▼                  ▼
    ┌───────────┐      ┌─────────────┐    ┌───────────┐
    │ Kali AI-1 │      │ Kali AI-2   │    │ Kali AI-3 │
    │           │      │             │    │           │
    │ Qwen      │      │ Claude/API  │    │ OpenAI    │
    │ Ollama    │      │ OpenCode    │    │ Codex     │
    │ OpenCode  │      │             │    │           │
    └─────┬─────┘      └──────┬──────┘    └─────┬─────┘
          │                    │                 │
          └────────────────────┼─────────────────┘
                               │
                               ▼
                    ┌────────────────────┐
                    │   RAG SERVICE VM   │
                    │                    │
                    │ Documents          │
                    │ Embeddings         │
                    │ Vector DB          │
                    │ Retrieval API      │
                    │ Update pipeline    │
                    └────────────────────┘
```

But underneath those VMs:

```text
                 CYBERAI IMAGE FACTORY
                         │
                 ┌───────┴───────┐
                 │               │
               Packer          Ansible
                 │               │
                 └───────┬───────┘
                         ▼
                Reproducible VMs
                         │
                         ▼
                    OVA / images
```

This separation is the key to everything you want.

---

# 2. Don't make OpenCode the AI foundation

This is an important distinction.

You said:

> I am concerned about using only OpenCode.

You shouldn't be.

OpenCode should be considered **one AI client/agent** in the platform.

Current OpenCode documentation lists 75+ providers, including Anthropic, DeepSeek, OpenAI, Ollama, OpenRouter, Amazon Bedrock, Google Vertex AI, llama.cpp and many others. It also supports custom provider base URLs. ([OpenCode](https://opencode.ai/docs/providers))

So OpenCode itself can be one convenient interface:

```text
OpenCode
   │
   ├── Ollama
   ├── Anthropic
   ├── OpenAI
   ├── DeepSeek
   ├── OpenRouter
   ├── Bedrock
   └── many others
```

But we **shouldn't require OpenCode**.

---

# 3. There are actually three separate things

This is where I want our architecture to be precise.

## A. Model

Examples:

```text
Qwen
Llama
DeepSeek
Claude
GPT
etc.
```

## B. Provider/runtime

Examples:

```text
Ollama
llama.cpp
Anthropic API
OpenAI API
DeepSeek API
OpenRouter
Bedrock
```

## C. Agent/client

Examples:

```text
OpenCode
Codex CLI
Claude Code
your own CyberAI agent
```

These must not be confused.

For example:

```text
             MODEL
               │
       ┌───────┼────────┐
       ▼       ▼        ▼
    Ollama   OpenAI   Anthropic
       │       │        │
       └───────┼────────┘
               │
       ┌───────┼──────────┐
       ▼       ▼          ▼
   OpenCode   Codex    Claude Code
```

That gives you the freedom you're asking for.

OpenCode's current provider system itself demonstrates this separation: providers can be configured with credentials and custom endpoints, and Ollama is simply one provider among many. ([OpenCode](https://opencode.ai/docs/providers))

---

# 4. Your Kali VM therefore shouldn't care which AI you use

The Kali base should contain:

```text
KALI BASE
│
├── Security tools
├── Burp Suite
├── Burp extensions
├── Python
├── Git
├── Docker
├── browsers
├── reverse engineering tools
├── network tools
└── AI integration layer
```

Then:

```text
Kali Base
    │
    ├── Local-AI profile
    │       └── Ollama
    │
    ├── OpenCode profile
    │       └── OpenCode
    │
    ├── Codex profile
    │       └── Codex CLI
    │
    ├── Claude profile
    │       └── Claude Code/API
    │
    └── Multi-AI profile
            ├── Ollama
            ├── OpenCode
            ├── Codex
            └── Claude
```

We can therefore create different images without rebuilding Kali itself.

---

# 5. I recommend a "Multi-AI" VM as your primary test VM

Instead of creating:

```text
Kali-Qwen
Kali-Claude
Kali-Codex
```

I'd have:

```text
Kali-CyberAI
```

with:

```text
                    Kali-CyberAI
                         │
        ┌────────────────┼─────────────────┐
        │                │                 │
      Local            Cloud             Agents
        │                │                 │
     Ollama          Anthropic          OpenCode
     llama.cpp       OpenAI             Codex
        │             DeepSeek          Claude Code
        │             etc.
        │                │
        └────────────────┼─────────────────┘
                         │
                         ▼
                    Shared RAG
```

Then you can compare:

```text
Qwen + OpenCode
DeepSeek + OpenCode
Claude + OpenCode
GPT + Codex
Qwen + your agent
Claude + your agent
```

without changing the Kali environment.

That is much more useful experimentally.

---

# 6. Cloud models do introduce one important security boundary

If you select:

```text
Claude
GPT
DeepSeek API
```

then information sent to that model necessarily leaves your VM and goes to the provider.

So we'll explicitly have:

```text
MODE = OFFLINE
```

versus

```text
MODE = ONLINE-LOCAL
```

versus

```text
MODE = ONLINE-CLOUD
```

### OFFLINE

```text
Kali
 ├── Ollama
 ├── local RAG
 └── security tools

Internet = OFF
```

### ONLINE-LOCAL

```text
Kali
 ├── Ollama
 ├── local RAG
 └── Internet

Cloud AI = OFF
```

### ONLINE-CLOUD

```text
Kali
 ├── Ollama
 ├── local RAG
 ├── Claude/OpenAI/etc.
 └── Internet
```

This gives you a very clear boundary.

---

# 7. Your VM networking should have explicit profiles

VirtualBox's networking model is actually very useful for what you want.

VirtualBox documents NAT as the default mode, with the guest behind a private subnet and not directly visible externally. It also provides host-only and internal networking for isolated communication, while bridged mode places the VM onto the same network as the host. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/Security.html?utm_source=chatgpt.com))

I'd create four network profiles.

## Profile 1 - Isolated

```text
Internet:       OFF
Host access:    OFF
LAN access:     OFF
VM-to-VM:       OFF
```

For:

```text
untrusted experiments
malware analysis
dangerous labs
```

---

## Profile 2 - NAT

```text
Kali
  ↓
VirtualBox NAT
  ↓
Internet
```

The VM can access the Internet.

External machines cannot normally initiate connections directly to the guest.

This should be your **normal development mode**.

---

## Profile 3 - Host-only

```text
Ubuntu Host
     │
     │ private virtual network
     │
    Kali
```

Useful for:

- host ↔ VM file transfer
- debugging
- management
- local services

No public Internet unless we deliberately add another interface.

---

## Profile 4 - Bridged

```text
Physical LAN
     │
 ┌───┴────┐
Host     Kali
```

This is the **"expose the VM" switch**.

I would make this an explicit opt-in mode.

VirtualBox warns that bridged mode gives the guest network access similar to the host and that firewalling may be necessary; their security guide specifically suggests NAT port forwarding as an alternative where only specific inbound access is needed. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/Security.html?utm_source=chatgpt.com))

So our default should **not** be bridged.

---

# 8. File transfer

You have two good choices.

## Method A - Temporary shared folder

VirtualBox Guest Additions provide shared folders, including **transient shares** that disappear when the VM powers off. They can also be read-only. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/guestadditions.html?utm_source=chatgpt.com))

This is ideal:

```text
Host:
~/CyberAI/transfer/

        ↕

Kali:
/mnt/transfer
```

And because we can make it:

```text
READ ONLY
```

the guest can't modify your host files.

For more controlled transfers:

```text
transient + read-only
```

is what I'd use.

---

# 9. Your Python server idea is also good

For a one-time transfer:

```text
Host:
python3 -m http.server
```

Then Kali downloads a specific file.

Or the reverse direction.

The advantage is:

```text
Start server
     ↓
Transfer files
     ↓
Stop server
```

Nothing remains permanently shared.

I'd actually provide a helper:

```text
cyber-transfer send file.zip
```

which starts a temporary transfer service and then shuts it down.

---

# 10. We can automate these network modes

This is important.

You shouldn't manually change VirtualBox settings every time.

Eventually:

```bash
./cybervm start --network offline
```

or:

```bash
./cybervm start --network nat
```

or:

```bash
./cybervm start --network host-only
```

or:

```bash
./cybervm start --network bridged
```

And:

```bash
./cybervm transfer ./report.pdf
```

could temporarily enable the transfer path.

---

# 11. RAG: I would make it a separate service

Your requirement is exactly right.

Don't do:

```text
VM1 → RAG copy
VM2 → RAG copy
VM3 → RAG copy
```

Instead:

```text
                 RAG SERVICE
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
       VM1          VM2          VM3
```

The RAG service becomes the **single source of truth**.

---

# 12. But I want to change how we think about "real-time RAG"

You said:

> security documentation is compulsory and it should contain real-time updates.

I agree with the goal, but **RAG cannot magically know about a new vulnerability**.

We need an ingestion/update pipeline.

```text
Internet
   │
   ├── CVE feeds
   ├── vendor advisories
   ├── security advisories
   ├── OWASP
   ├── CWE
   ├── MITRE ATT&CK
   ├── exploit-development research
   ├── security blogs
   └── tool/project releases
           │
           ▼
       INGESTION
           │
           ▼
       NORMALIZE
           │
           ▼
       DEDUPLICATE
           │
           ▼
       VALIDATE
           │
           ▼
        EMBED
           │
           ▼
      VECTOR DATABASE
```

Then all AI VMs query the same database.

---

# 13. Don't treat every Internet source equally

This is **very important** if your goal is low false-positive information.

I'd assign source trust levels.

### Tier 1 - authoritative

```text
CVE/NVD
CISA
vendor advisories
Microsoft
Apple
Google
Linux projects
Kubernetes
OWASP
MITRE
official project documentation
```

### Tier 2 - high-quality research

```text
well-known security research teams
academic papers
established security companies
maintainer advisories
```

### Tier 3 - community

```text
GitHub research
technical blogs
conference material
```

### Tier 4 - unverified

```text
forums
random posts
social media
anonymous claims
```

Then the AI sees:

```text
SOURCE:
CISA

DATE:
2026-09-18

CONFIDENCE:
HIGH

STATUS:
Verified advisory
```

rather than just:

```text
Some website says X.
```

---

# 14. New CVE example

Suppose tomorrow:

```text
CVE-2026-XXXXX
```

appears.

Our pipeline detects it.

```text
New CVE
   ↓
CVE feed
   ↓
correlate vendor advisory
   ↓
check affected versions
   ↓
check exploitation status
   ↓
retrieve technical references
   ↓
index
```

Then:

```text
RAG version:
2026-09-20T04:00Z
```

and every AI VM automatically uses the new knowledge.

**No VM rebuild required.**

---

# 15. "Hackers in the wild" information

Yes, we can incorporate information about emerging techniques, but I would **not treat a random exploit PoC as truth**.

Instead maintain separate knowledge categories:

```text
knowledge/
├── fundamentals/
├── vulnerabilities/
├── attack-techniques/
├── detection/
├── mitigations/
├── exploitation-research/
├── threat-intelligence/
├── ctf/
└── experimental/
```

Then the AI knows whether something is:

```text
documented vulnerability
confirmed exploitation
research technique
proof of concept
unverified claim
```

That distinction is much more valuable than simply dumping exploit repositories into a vector database.

---

# 16. We should also maintain freshness metadata

Every RAG document should have:

```text
source
URL
published_at
updated_at
retrieved_at
version
vendor
CVE/CWE/ATT&CK IDs
confidence
source_tier
affected_products
```

Then the AI can answer:

> Is this information current?

rather than blindly returning old material.

This matters because security information genuinely changes. For example, Anthropic's current model lifecycle documentation explicitly shows models moving from active → deprecated → retired and recommends testing migrations before retirement. ([Claude Platform Docs](https://docs.anthropic.com/en/docs/about-claude/model-deprecations?utm_source=chatgpt.com))

The same principle applies to our security knowledge.

---

# 17. We should have two RAG modes

### Stable Knowledge

```text
OWASP
CWE
networking
Linux
HTTP
cryptography
etc.
```

Changes relatively slowly.

### Live Intelligence

```text
new CVEs
new advisories
new research
new exploitation reports
tool releases
emerging techniques
```

Changes rapidly.

So:

```text
                 RAG
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
   Stable KB           Live Intel
```

This makes freshness management much easier.

---

# 18. Your "least false positives" requirement

There is **no mechanism that guarantees least false positives**.

But we can dramatically improve reliability with:

```text
source ranking
+
freshness
+
deduplication
+
cross-source correlation
+
version matching
+
citations
+
confidence
+
human verification for high-impact claims
```

And most importantly:

> **The AI should be instructed to distinguish evidence from inference.**

For example:

```text
Evidence:
Vendor advisory confirms X.

Inference:
This may imply Y.

Not established:
No authoritative source confirms Z.
```

That is far better than letting the model confidently hallucinate an attack path.

---

# 19. Burp Suite automation

Yes - this should absolutely be automated.

Kali's current `kali-tools-top10` includes Burp Suite, and Kali's web tooling metapackage also includes Burp. ([Kali Linux](https://www.kali.org/tools/kali-meta/?utm_source=chatgpt.com))

Then we maintain:

```text
burp/
├── extensions/
│   ├── turbo-intruder.bapp
│   ├── extension2.bapp
│   └── extension3.jar
│
├── config/
│   ├── user.json
│   └── project.json
│
└── install.yml
```

Our provisioning system does:

```text
Install Burp
      ↓
Install required runtime dependencies
      ↓
Install extensions
      ↓
Load configuration
      ↓
Enable extensions
      ↓
Configure defaults
```

PortSwigger explicitly supports offline installation of BApps from downloaded `.bapp` files, as well as manual installation of `.jar`, `.py`, and `.rb` extensions. ([PortSwigger](https://portswigger.net/burp/documentation/desktop/extend-burp/extensions/installing/manual-install?utm_source=chatgpt.com))

And Burp settings can be exported/imported as JSON configuration files, which is excellent for reproducible provisioning. ([PortSwigger](https://portswigger.net/burp/documentation/desktop/settings?utm_source=chatgpt.com))

---

# 20. Turbo Intruder and other extensions

We can have a manifest:

```yaml
burp_extensions:
  - name: turbo-intruder
    source: ...
    version: ...
    sha256: ...

  - name: extension-2
    source: ...
    version: ...
    sha256: ...
```

The build process downloads/imports them and verifies the expected hash.

For offline builds:

```text
Internet-connected builder
          ↓
download BApps
          ↓
verify hashes
          ↓
store in artifact repository
          ↓
offline VM build
```

This is much better than blindly running:

```bash
curl ... | bash
```

inside every VM.

PortSwigger itself warns that BApp extensions are third-party code and can execute arbitrary code, despite their review process. ([PortSwigger](https://portswigger.net/burp/documentation/desktop/extend-burp/extensions/installing/bapp-store?utm_source=chatgpt.com))

So our build pipeline should **pin and verify extensions**.

---

# 21. Burp configuration becomes version-controlled

We can have:

```text
burp/
├── extensions.lock
├── user-settings.json
├── project-settings.json
└── README.md
```

Then:

```text
VM #1
VM #2
VM #3
```

all get the same Burp environment.

PortSwigger supports loading configuration files at startup, and its command-line options include project/config-file loading. ([PortSwigger](https://portswigger.net/burp/documentation/desktop/troubleshooting/launch-from-command-line?utm_source=chatgpt.com))

---

# 22. Your tool installation becomes manifest-driven

Instead of:

```text
install nmap
install ffuf
install gobuster
...
```

we create:

```yaml
security_tools:
  apt:
    - nmap
    - ffuf
    - gobuster
    - nikto
    - sqlmap
    - wpscan
    - metasploit-framework
    - wireshark

  pip:
    ...

  github:
    ...

  binaries:
    ...

  burp_extensions:
    ...

  custom:
    ...
```

Then Ansible installs it.

Kali already organizes tools into metapackages such as `kali-tools-web`, `kali-tools-vulnerability`, `kali-tools-reverse-engineering`, etc., so we can use those where appropriate and supplement them with your own manifest. ([Kali Linux](https://www.kali.org/docs/general-use/metapackages/?utm_source=chatgpt.com))

---

# 23. RAM: I don't want the RAG VM stealing your Kali RAM

This is an important concern.

Your system has:

```text
32 GB RAM
```

I propose initially:

```text
Ubuntu host
    ~8 GB reserved

Kali AI VM
    20 GB

RAG VM
    4 GB
```

But there is an even better option:

## Don't run the RAG VM when you don't need it.

```text
CTF:
    Kali = ON
    RAG = ON

Offline CTF:
    Kali = ON
    RAG = OFF

Simple pentest:
    Kali = ON
    RAG = OFF

Knowledge update:
    RAG = ON
    Kali = OFF
```

So the RAG VM isn't permanently consuming RAM.

---

# 24. And RAG shouldn't require 20 GB

A vector database + embedding service + API can operate with considerably less memory than the LLM.

So:

```text
Kali AI:
20 GB

RAG:
4 GB
```

is a sensible starting point.

If later your RAG grows substantially, we can increase it.

---

# 25. Your external SSD

I'd now recommend buying:

**1-2 TB external NVMe SSD, USB 3.2 Gen 2 or better.**

For this project:

```text
1 TB
```

is probably enough to start.

Something like:

```text
External SSD
│
├── CyberAI/
│   ├── factory/
│   ├── images/
│   ├── models/
│   ├── rag/
│   ├── artifacts/
│   └── backups/
│
└── labs/
```

Your existing HDD can become the **cold backup**.

---

# 26. Why SSD matters

You could put:

```text
Kali VM
+
Qwen
+
RAG
```

on the HDD.

But VM disk I/O + database I/O + model loading + Burp project files will make an HDD frustrating.

So:

```text
External NVMe SSD
    = active CyberAI workspace

External HDD
    = backup/archive
```

is a much better arrangement.

---

# 27. VM portability

For portability:

```text
CyberAI SSD
│
├── images/
│   ├── kali-cyberai.ova
│   ├── rag.ova
│   └── ...
│
├── manifests/
│
└── factory/
```

VirtualBox supports OVF/OVA import/export and cloning, and snapshots can preserve a VM state and be restored later. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/toc.htm?utm_source=chatgpt.com))

So your workflow becomes:

```text
Build
  ↓
Test
  ↓
Snapshot
  ↓
Export OVA
  ↓
Copy to SSD
```

On another Linux machine:

```text
Import OVA
  ↓
Start
```

---

# 28. But don't use OVA as your development artifact

This distinction is important.

Use:

```text
Git repository
      ↓
Packer + Ansible
      ↓
OVA
```

not:

```text
OVA
 ↓
manually modify
 ↓
OVA
 ↓
manually modify
```

Otherwise six months later you won't know what changed.

---

# 29. Your final project structure

I would build this:

```text
CyberAI/
│
├── README.md
│
├── factory/
│   │
│   ├── packer/
│   │   ├── kali-base.pkr.hcl
│   │   ├── kali-ai.pkr.hcl
│   │   └── rag.pkr.hcl
│   │
│   ├── ansible/
│   │   ├── common.yml
│   │   ├── kali.yml
│   │   ├── security-tools.yml
│   │   ├── burp.yml
│   │   ├── ai-clients.yml
│   │   └── rag-client.yml
│   │
│   └── scripts/
│       ├── build.sh
│       ├── test.sh
│       ├── export.sh
│       └── update.sh
│
├── profiles/
│   ├── base.yml
│   ├── security.yml
│   ├── ai-local.yml
│   ├── ai-cloud.yml
│   ├── opencode.yml
│   ├── codex.yml
│   └── multi-ai.yml
│
├── burp/
│   ├── extensions.lock
│   ├── configs/
│   └── artifacts/
│
├── rag/
│   ├── sources/
│   ├── ingestion/
│   ├── metadata/
│   └── manifests/
│
├── models/
│   └── manifests/
│
├── images/
│
├── labs/
│
└── docs/
```

This is the part I want us to build **before** installing random things into Kali.

---

# 30. And eventually you'll be able to do this

### Build a standard Kali

```bash
./cyberai build kali
```

### Build Kali + local AI

```bash
./cyberai build kali --profile ai-local
```

### Build Kali + OpenCode

```bash
./cyberai build kali --profile opencode
```

### Build the multi-AI environment

```bash
./cyberai build kali --profile multi-ai
```

### Build RAG

```bash
./cyberai build rag
```

### Update RAG

```bash
./cyberai rag update
```

### Start offline

```bash
./cyberai start kali --network isolated
```

### Start with Internet

```bash
./cyberai start kali --network nat
```

### Start host-only transfer

```bash
./cyberai start kali --network host-only
```

### Explicitly expose it

```bash
./cyberai start kali --network bridged
```

That last command should produce a prominent warning/confirmation.

---

# 31. The final system

So the architecture becomes:

```text
                         ┌─────────────────────────┐
                         │     Ubuntu 24.04 HOST   │
                         │                         │
                         │  32 GB / i5-13600K      │
                         └────────────┬────────────┘
                                      │
                                  VirtualBox
                                      │
            ┌─────────────────────────┼──────────────────────────┐
            │                         │                          │
            ▼                         ▼                          ▼
     ┌──────────────┐         ┌──────────────┐           ┌──────────────┐
     │ KALI AI VM   │         │  RAG VM      │           │ LAB VM       │
     │              │         │              │           │              │
     │ Kali         │         │ Documents    │           │ DVWA         │
     │ Burp         │         │ Embeddings    │           │ Juice Shop   │
     │ Nmap         │         │ Vector DB     │           │ vulnerable   │
     │ ffuf         │         │ API           │           │ targets      │
     │ Metasploit   │         │ Update        │           │              │
     │ etc.         │         │ pipeline      │           │              │
     │              │         │              │           │              │
     │ AI Clients   │◄────────┤              │           │              │
     │              │         └──────────────┘           └──────────────┘
     │ Ollama       │
     │ OpenCode     │
     │ Codex        │
     │ Claude Code  │
     │ API clients  │
     └──────┬───────┘
            │
            ▼
     ┌──────────────────────────────────────┐
     │        AI PROVIDER LAYER             │
     │                                      │
     │ Local:       Ollama / llama.cpp      │
     │ OpenAI:      API / Codex             │
     │ Anthropic:   Claude API / Claude Code│
     │ DeepSeek:    API                     │
     │ Other:       OpenRouter/etc.         │
     └──────────────────────────────────────┘
```

And around all of it:

```text
                    IMAGE FACTORY
                 Packer + Ansible
                        │
            ┌───────────┴────────────┐
            ▼                        ▼
        reproducible             versioned
          images                configuration
            │                        │
            └──────────┬─────────────┘
                       ▼
                   OVA / VM
```

---

# 32. What happens when Windows enters the picture?

We don't need to change the architecture.

Today:

```text
Ubuntu
  ↓
VirtualBox
  ↓
CyberAI VMs
```

Future:

```text
Windows
  ↓
VirtualBox
  ↓
same CyberAI OVA
```

The **VM itself stays essentially the same**.

The differences are primarily the host-side pieces:

| Area | Ubuntu host | Windows host |
|---|---|---|
| VirtualBox | Same | Same |
| OVA | Same | Same |
| Kali | Same | Same |
| RAG VM | Same | Same |
| AI models | Same | Same |
| VM network | VirtualBox | VirtualBox |
| Shared folders | Linux path | Windows path |
| USB devices | Linux permissions | Windows USB handling |
| Host automation | Bash/Python | PowerShell/Python |
| Performance | Depends on host | Depends on host/Hyper-V configuration |

So if we keep **host-specific automation outside the VM**, portability remains high.

---

# 33. One thing I would *not* do

I would not create:

```text
Kali-Qwen.ova
Kali-Claude.ova
Kali-DeepSeek.ova
Kali-Codex.ova
Kali-OpenCode.ova
```

as completely separate hand-maintained environments.

That creates duplication.

Instead:

```text
Kali-CyberAI
│
├── local model support
├── cloud API support
├── OpenCode
├── Codex
├── Claude Code
└── generic AI client interface
```

and then create **profiles/configurations**.

Only create separate images when there is a real resource/isolation reason.

---

# 34. What I think our actual build sequence should be

I would now change our original plan to this:

### Phase 0 - Architecture repository
Build the source-of-truth directory.

### Phase 1 - VirtualBox host
Configure Ubuntu → VirtualBox.

### Phase 2 - Base Kali image
Create minimal reproducible Kali.

### Phase 3 - Security-tool image
Automate all your required tools.

### Phase 4 - Burp automation
Burp + pinned extensions + configuration.

### Phase 5 - Network isolation
Build the four network modes.

### Phase 6 - Transfer mechanism
Transient shared folder + temporary transfer server.

### Phase 7 - RAG appliance
Separate RAG VM.

### Phase 8 - RAG ingestion
Stable security knowledge.

### Phase 9 - RAG live intelligence
CVE/advisory/research update pipeline.

### Phase 10 - AI provider layer
Local + cloud.

### Phase 11 - AI clients
OpenCode + Codex + Claude Code + local interfaces.

### Phase 12 - Tool/AI integration
Controlled tool execution.

### Phase 13 - Snapshots/cloning
Golden → disposable.

### Phase 14 - OVA export
Portable external-SSD artifacts.

### Phase 15 - Performance testing
Benchmark different models/clients.

### Phase 16 - Offline test
Disconnect Internet and verify the environment still works.

---

## I don't see a fundamental blocker anymore

Your requirements are sufficiently clear to start designing the implementation.

There is **one decision I recommend we make before touching the machine**:

### Don't install anything yet.

First we should create the **CyberAI source-of-truth repository and architecture**, because that becomes the foundation for Packer/Ansible and prevents us from repeating work.

Then we'll build the **first minimal Kali image**, test it, and only then add the security tools, Burp, RAG, and AI layers one at a time.

That approach means if we later discover that, say, **Qwen is too slow on your 13600K**, we don't rebuild Kali. We simply change the AI profile/model.

Likewise, if tomorrow you decide to use **Claude instead of OpenCode**, we don't rebuild Kali or RAG.

And if a new CVE appears, we **update the RAG service**, not 5 different VMs.

That's the architecture I would use for your stated goal.

---

**Sources:**

- [Providers | OpenCode](https://opencode.ai/docs/providers)
- [Security Guide](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/Security.html?utm_source=chatgpt.com)
- [Model deprecations - Claude Platform Docs](https://docs.anthropic.com/en/docs/about-claude/model-deprecations?utm_source=chatgpt.com)
- [kali-meta | Kali Linux Tools](https://www.kali.org/tools/kali-meta/?utm_source=chatgpt.com)
- [Installing extensions manually - PortSwigger](https://portswigger.net/burp/documentation/desktop/extend-burp/extensions/installing/manual-install?utm_source=chatgpt.com)

## Prompt:
9/19/2026, 10:32:45 PM

Now give me the complete detailed plan which I can follow and perform all setup consider I am doing everything for first time and I need attention over all setup process to make it detailed just like for a newbie

## Response:
9/19/2026, 10:32:47 PM

I’ll turn the architecture into a beginner-friendly build sequence: host preparation → storage → VirtualBox → automation → golden Kali → Burp/tools → networking → RAG → AI providers → testing → backups/portability. I’ll also mark exactly what you should **do now**, what can wait, and what must never be done inside the golden image.

> **Searching 3 websites**
>
> 
>
> **Searched 3 websites**
>
> 
>
> Worked for 8s

Yes. Given that you are doing this for the first time, I recommend **not trying to build the entire CyberAI platform in one shot**. We will build it in controlled stages, verify each stage, and only move forward when the previous stage works.

The end result will look like this:

```text
                         YOUR UBUNTU HOST
                    Ubuntu 24.04.2 LTS
                   i5-13600K / 32 GB RAM
                              │
                         VirtualBox
                              │
       ┌──────────────────────┼────────────────────────┐
       │                      │                        │
       ▼                      ▼                        ▼
  Kali-Golden            Kali-Work-01            RAG-Service
  NEVER use              Disposable VM            Shared service
  directly               ┌───────────────┐        ┌─────────────┐
                          │ Burp Suite    │        │ Knowledge   │
                          │ Nmap          │        │ CVEs        │
                          │ ffuf          │        │ Advisories  │
                          │ sqlmap        │        │ Research    │
                          │ etc.          │        │ Vector DB   │
                          │ AI clients     │        │ API         │
                          └───────────────┘        └─────────────┘
                                │
                     ┌──────────┼──────────┐
                     ▼          ▼          ▼
                  Ollama     OpenCode    Cloud APIs
                  Local      Multi-AI     Claude/OpenAI/
                                         DeepSeek/etc.
```

The important principle is:

> **The VM is disposable. The configuration is permanent.**

If you destroy a Kali VM tomorrow, you should be able to recreate another one from your configuration rather than reinstalling everything manually.

Kali itself provides official VirtualBox images, and its documentation recommends verifying downloaded images rather than obtaining them from unofficial sources. ([Kali Linux](https://www.kali.org/docs/introduction/download-official-kali-linux-images/?utm_source=chatgpt.com))

---

# 1. What we are going to build

We will build this in **15 phases**.

| Phase | What you build | Risk |
|---|---|---|
| 0 | Understand architecture | None |
| 1 | Prepare Ubuntu host | Low |
| 2 | Prepare external SSD | Low |
| 3 | Install/configure VirtualBox | Low |
| 4 | Create CyberAI project repository | None |
| 5 | Download & verify Kali | Low |
| 6 | Create first Kali VM | Low |
| 7 | Create golden Kali image | Medium |
| 8 | Automate Kali provisioning | Medium |
| 9 | Security tools + Burp automation | Medium |
| 10 | VM network isolation | Important |
| 11 | Disposable clones/snapshots | Important |
| 12 | Shared RAG service | Medium |
| 13 | AI provider layer | Medium |
| 14 | Benchmark local vs cloud AI | Low |
| 15 | Backups + portability + recovery | Important |

**Do not skip directly to Phase 12.**

The RAG and AI parts depend on having the VM architecture correct first.

---

# 2. Final directory structure

Eventually your external SSD should contain something approximately like:

```text
CyberAI/
│
├── README.md
├── VERSION
│
├── factory/
│   ├── packer/
│   │   ├── kali.pkr.hcl
│   │   ├── variables.pkr.hcl
│   │   └── http/
│   │
│   ├── ansible/
│   │   ├── inventory/
│   │   ├── playbooks/
│   │   ├── roles/
│   │   └── requirements.yml
│   │
│   └── scripts/
│       ├── build.sh
│       ├── clone.sh
│       ├── destroy.sh
│       ├── snapshot.sh
│       └── verify.sh
│
├── profiles/
│   ├── base.yml
│   ├── security.yml
│   ├── ai-local.yml
│   ├── ai-cloud.yml
│   └── multi-ai.yml
│
├── burp/
│   ├── extensions.lock
│   ├── configs/
│   └── artifacts/
│
├── tools/
│   ├── apt.yml
│   ├── pip.yml
│   ├── github.yml
│   └── binaries.yml
│
├── rag/
│   ├── config/
│   ├── ingestion/
│   ├── sources/
│   ├── database/
│   └── backups/
│
├── models/
│
├── images/
│   ├── golden/
│   ├── releases/
│   └── checksums/
│
├── labs/
│   ├── active/
│   ├── snapshots/
│   └── destroyed/
│
├── artifacts/
│
├── transfer/
│
├── backups/
│
└── docs/
    ├── architecture/
    ├── networking/
    ├── recovery/
    └── benchmarks/
```

You will **not** create all of this manually today. We will create it progressively.

---

# 3. Understand the three different things

This distinction is extremely important.

## Model

Examples:

```text
Qwen
Llama
DeepSeek
Claude
GPT
```

## Provider/runtime

Examples:

```text
Ollama
llama.cpp
OpenAI API
Anthropic API
DeepSeek API
OpenRouter
AWS Bedrock
```

## Agent/client

Examples:

```text
OpenCode
Codex
Claude Code
your own CyberAI agent
```

So:

```text
                 MODEL
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
    Ollama      OpenAI      Anthropic
       │           │           │
       └───────────┼───────────┘
                   ▼
             AI CLIENT
        ┌──────────┼─────────┐
        ▼          ▼         ▼
    OpenCode     Codex    CyberAI
```

This is why **OpenCode must not become the foundation of the entire system**.

It can be one of the clients.

---

# 4. Your hardware strategy

You have:

```text
CPU       i5-13600K
cores     14 physical / 20 threads
RAM       32 GB
GPU       none
Storage   ~309 GB currently free
```

Initially I recommend:

### Host

```text
Ubuntu
8+ GB available
```

### Kali

```text
RAM: 16-20 GB
CPU: 6-8 vCPU
Disk: 80-120 GB
```

### RAG

Initially:

```text
RAM: 4 GB
CPU: 2 vCPU
Disk: 40-80 GB
```

But **do not run Kali + RAG + local LLM simultaneously at maximum resources**.

For example:

```text
CTF:
Ubuntu
  └── Kali 20 GB

RAG work:
Ubuntu
  └── RAG 4 GB

AI security research:
Ubuntu
  ├── Kali 16 GB
  └── RAG 4 GB
```

Later we optimize this.

---

# PHASE 0 - Important safety rules

Before doing anything, establish these rules.

## Rule 1 - Golden VM is never your working VM

You will have:

```text
Kali-Golden
```

and:

```text
Kali-Work-01
Kali-Work-02
Kali-CTF-01
Kali-WebLab-01
```

You work only inside the disposable machines.

---

## Rule 2 - Never put secrets in Git

Never commit:

```text
OpenAI API keys
Anthropic API keys
DeepSeek keys
SSH private keys
passwords
cookies
tokens
Burp project data containing sensitive material
```

---

## Rule 3 - No permanent shared folder initially

VirtualBox shared folders are convenient, but they increase host/guest integration.

VirtualBox supports shared folders and they can be made transient/read-only, which is exactly what we will eventually use for controlled transfers. ([Kali Linux](https://www.kali.org/docs/virtualization/install-virtualbox-guest-additions/?utm_source=chatgpt.com))

---

## Rule 4 - Do not use Bridged networking by default

Your default should be:

```text
OFFLINE
```

or:

```text
NAT
```

not:

```text
BRIDGED
```

VirtualBox documents NAT, host-only, internal, and bridged modes separately; bridged mode places the VM directly on the physical network, while host-only keeps it away from the outside network. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/networkingdetails.html?utm_source=chatgpt.com))

---

# PHASE 1 - Prepare Ubuntu

Do this first.

Open Terminal.

Run:

```bash
sudo apt update
```

Then:

```bash
sudo apt full-upgrade -y
```

Then:

```bash
sudo reboot
```

After reboot:

```bash
uname -a
```

Then:

```bash
lsb_release -a
```

You should see Ubuntu 24.04.x.

---

# PHASE 2 - Check virtualization

Run:

```bash
lscpu | grep -E 'Virtualization|Model name|CPU\(s\)'
```

You want something showing:

```text
Virtualization: VT-x
```

or equivalent.

Also:

```bash
lsmod | grep kvm
```

This isn't directly required by VirtualBox in the same way KVM is, so don't worry if this output isn't what you expect.

The important point is that Intel VT-x should be enabled in BIOS/UEFI.

---

# PHASE 3 - Prepare the external SSD

**Do not format the SSD yet if you haven't bought it.**

When you buy it, connect it.

Run:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
```

You might see something like:

```text
nvme0n1       931G
├─nvme0n1p1   512M
└─nvme0n1p2   930G /
sda           1.8T
└─sda1        1.8T
```

Your internal NVMe is probably:

```text
nvme0n1
```

The external SSD will probably be:

```text
sda
```

**Do not assume this.**

Never run `mkfs` until you have confirmed the correct device.

---

# 6. External SSD filesystem

For your Linux-first environment, I recommend:

```text
ext4
```

rather than NTFS.

Why?

Because your primary environment is Ubuntu and VM disks benefit from a native Linux filesystem.

Later, if Windows portability becomes important, we can add an additional portable export partition or store OVA files on a filesystem Windows can access.

The architecture itself remains portable.

---

# 7. Create the CyberAI root

Once the SSD is mounted, identify its path:

```bash
findmnt
```

Suppose it is:

```text
/media/$USER/CyberAI-SSD
```

Then:

```bash
mkdir -p /media/$USER/CyberAI-SSD/CyberAI
```

From this point forward I'll call this:

```text
$CYBERAI
```

You can temporarily set:

```bash
export CYBERAI="/media/$USER/CyberAI-SSD/CyberAI"
```

Verify:

```bash
echo "$CYBERAI"
```

---

# PHASE 4 - Install VirtualBox

For Ubuntu 24.04, use an official VirtualBox package/repository rather than an unofficial build.

The current official download archive includes a VirtualBox 7.2.x package specifically for Ubuntu Noble; as of the current check, 7.2.18 is listed. ([VirtualBox](https://download.virtualbox.org/virtualbox/7.2.8/?utm_source=chatgpt.com))

I recommend installing the current compatible release rather than hard-coding an old version.

After installation:

```bash
VBoxManage --version
```

You should get something similar to:

```text
7.2.x
```

Also test:

```bash
VBoxManage list hostinfo
```

If that works, VirtualBox is functioning.

---

# 8. Configure VirtualBox's default VM location

This is important because we don't want your large VM disks filling your Ubuntu root filesystem.

Create:

```bash
mkdir -p "$CYBERAI/images"
```

Then:

```bash
VBoxManage setproperty machinefolder "$CYBERAI/images"
```

Check:

```bash
VBoxManage list systemproperties | grep -i "Default machine folder"
```

You want:

```text
Default machine folder:
.../CyberAI/images
```

---

# PHASE 5 - Create the project

Go into your project:

```bash
cd "$CYBERAI"
```

Create directories:

```bash
mkdir -p \
factory/packer \
factory/ansible/inventory \
factory/ansible/playbooks \
factory/ansible/roles \
factory/scripts \
profiles \
burp/configs \
burp/artifacts \
tools \
rag/config \
rag/ingestion \
rag/sources \
rag/database \
rag/backups \
models \
images/golden \
images/releases \
images/checksums \
labs/active \
labs/snapshots \
labs/destroyed \
artifacts \
transfer \
backups \
docs/architecture \
docs/networking \
docs/recovery \
docs/benchmarks
```

Verify:

```bash
find "$CYBERAI" -maxdepth 2 -type d | sort
```

---

# 9. Initialize Git

Install Git:

```bash
sudo apt install -y git
```

Then:

```bash
cd "$CYBERAI"
git init
```

Create:

```bash
nano .gitignore
```

Put:

```text
# Secrets
.env
.env.*
*.key
*.pem
*.token
*.secret

# Virtual machines
*.vdi
*.vmdk
*.vhd
*.qcow2
*.sav
*.nvram

# VM runtime
*.log

# Burp projects
*.burp
*.burpsuite

# Local databases
rag/database/*
rag/backups/*

# Models
models/*

# Temporary files
/tmp/
transfer/*
artifacts/*
```

Save.

Then:

```bash
git add .gitignore
git commit -m "Initial CyberAI repository"
```

---

# PHASE 6 - Install Packer

We will use:

```text
Packer
+
Ansible
+
VirtualBox
```

Packer creates the machine image, while Ansible describes what should exist inside the machine.

Packer officially supports VirtualBox builders that can create VMs and export OVA/OVF images. ([HashiCorp Developer](https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/vm?utm_source=chatgpt.com))

Ansible is designed around repeatable desired-state configuration through playbooks. ([Ansible Documentation](https://docs.ansible.com/projects/ansible/latest/getting_started/index.html?utm_source=chatgpt.com))

That combination is exactly what we want.

Install Packer using HashiCorp's official installation method.

Then verify:

```bash
packer version
```

You want:

```text
Packer v...
```

---

# PHASE 7 - Install Ansible

For the first version:

```bash
sudo apt install -y ansible
```

Check:

```bash
ansible --version
```

You should get something similar to:

```text
ansible [core ...]
```

---

# 10. Why Packer + Ansible?

Imagine manually creating three VMs:

```text
Kali 1
 ├── Burp
 ├── Nmap
 ├── ffuf
 ├── sqlmap
 ├── OpenCode
 └── Ollama

Kali 2
 ├── Burp
 ├── Nmap
 ├── ffuf
 ├── sqlmap
 ├── OpenCode
 └── Ollama

Kali 3
 ├── Burp
 ├── Nmap
 ├── ffuf
 ├── sqlmap
 ├── OpenCode
 └── Ollama
```

That's exactly what we don't want.

Instead:

```text
Configuration
      │
      ▼
   Packer
      │
      ▼
   Ansible
      │
      ▼
Golden Kali
      │
 ┌────┼────┐
 ▼    ▼    ▼
VM1  VM2   VM3
```

If you add:

```text
new-tool
```

to your configuration, you rebuild the image.

Ansible's idempotent design means the same configuration can be reapplied without unnecessarily changing systems already matching the desired state. ([Ansible Documentation](https://docs.ansible.com/projects/ansible/latest/getting_started/introduction.html?utm_source=chatgpt.com))

---

# PHASE 8 - Get Kali

There are two possible approaches.

## Approach A - Recommended for your first build

Use Kali's official pre-built VirtualBox image.

This is much easier for a beginner.

Kali officially publishes pre-built VirtualBox images with guest integration already prepared. ([Kali Linux](https://www.kali.org/docs/introduction/download-official-kali-linux-images/?utm_source=chatgpt.com))

Download from the official Kali site.

**Do not download Kali from random mirrors or GitHub accounts.**

Kali explicitly recommends obtaining images from official sources and verifying their SHA256 checksums. ([Kali Linux](https://www.kali.org/docs/introduction/download-official-kali-linux-images/?utm_source=chatgpt.com))

---

# 11. Verify Kali

After downloading:

```bash
sha256sum kali-linux-*-virtualbox-amd64.*
```

Compare the result against Kali's official checksum.

Do not proceed if the checksum doesn't match.

---

# 12. Import Kali into VirtualBox

Extract the Kali archive.

For example:

```bash
7z x kali-linux-*-virtualbox-amd64.7z
```

You should eventually get:

```text
something.vbox
something.vdi
```

Then:

```bash
VBoxManage registervm "/path/to/kali.vbox"
```

Or use VirtualBox GUI:

```text
VirtualBox
    ↓
Add
    ↓
select .vbox
```

Kali documents this exact pre-built VirtualBox import workflow. ([Kali Linux](https://www.kali.org/docs/virtualization/import-premade-virtualbox/?utm_source=chatgpt.com))

---

# PHASE 9 - First Kali configuration

Before installing hundreds of tools, boot Kali once.

Do not modify anything complicated yet.

Verify:

```bash
whoami
```

Then:

```bash
hostname
```

Then:

```bash
ip addr
```

Then:

```bash
df -h
```

Then:

```bash
free -h
```

Then:

```bash
lscpu
```

This gives us a baseline.

---

# 13. Update Kali

Inside Kali:

```bash
sudo apt update
```

Then:

```bash
sudo apt full-upgrade -y
```

Then:

```bash
sudo reboot
```

Kali specifically recommends updating the system before installing metapackages. ([Kali Linux](https://www.kali.org/docs/general-use/metapackages/?utm_source=chatgpt.com))

---

# PHASE 10 - Install the Kali baseline

Do **not** immediately install:

```text
kali-linux-everything
```

That is unnecessary for our first build.

Kali currently provides purpose-specific metapackages such as:

```text
kali-tools-information-gathering
kali-tools-vulnerability
kali-tools-web
kali-tools-database
kali-tools-reverse-engineering
kali-tools-exploitation
kali-tools-forensics
...
```

and broader groups such as:

```text
kali-linux-default
kali-linux-large
kali-linux-everything
```

Kali warns that `kali-linux-everything` installs a very large collection of packages. ([Kali Linux](https://www.kali.org/docs/general-use/metapackages/?utm_source=chatgpt.com))

For your first image I'd use:

```bash
sudo apt install -y \
kali-linux-default \
kali-tools-information-gathering \
kali-tools-vulnerability \
kali-tools-web \
kali-tools-database \
kali-tools-reverse-engineering \
kali-tools-fuzzing
```

Then:

```bash
sudo apt autoremove -y
```

Then:

```bash
sudo apt clean
```

---

# 14. Why not everything?

Because you have:

```text
32 GB RAM
```

and want:

```text
Kali
+
Burp
+
AI
+
RAG
+
VM infrastructure
```

Installing every Kali package is not automatically better.

Kali's published installation-size documentation shows the difference between smaller and broader metapackages is substantial. ([Kali Linux](https://www.kali.org/docs/installation/installation-sizes/?utm_source=chatgpt.com))

Instead, we'll have:

```text
Kali baseline
      +
our custom tool manifest
      +
Burp extensions
      +
AI layer
```

That is much more controllable.

---

# PHASE 11 - Create your tool manifest

On the host:

```bash
cd "$CYBERAI"
nano tools/apt.yml
```

Initially:

```yaml
packages:
  - nmap
  - ffuf
  - gobuster
  - nikto
  - sqlmap
  - wpscan
  - wireshark
  - tcpdump
  - netcat-openbsd
  - curl
  - wget
  - jq
  - git
  - tmux
  - python3
  - python3-pip
  - python3-venv
```

This file becomes the **source of truth**.

Later:

```text
tools/
├── apt.yml
├── pip.yml
├── github.yml
└── binaries.yml
```

---

# PHASE 12 - Burp Suite

Burp should be treated as a separately managed component.

We'll eventually have:

```text
burp/
├── extensions.lock
├── configs/
│   ├── user.json
│   └── project.json
└── artifacts/
```

The important concept is:

```text
Burp configuration
        +
extension manifest
        +
extension binaries
        ↓
automated installation
```

PortSwigger supports installing BApps and manual extensions, and Burp settings can be saved/loaded. ([Kali Linux](https://www.kali.org/docs/introduction/download-official-kali-linux-images/?utm_source=chatgpt.com))

---

# 15. Turbo Intruder

For example, eventually:

```yaml
extensions:
  - name: turbo-intruder
    source: official
    version: PINNED_VERSION
    sha256: CHECKSUM
```

We will **pin versions** rather than blindly downloading "latest".

That gives you:

```text
2026-09 image
Turbo Intruder version X
```

instead of:

```text
whatever version happened to be online today
```

This is important for reproducibility.

---

# 16. Do not blindly trust Burp extensions

This is particularly important for your lab.

A third-party Burp extension executes code inside Burp's environment.

Therefore:

```text
unknown extension
       ↓
potential arbitrary code
       ↓
inside VM
```

We will therefore:

1. Prefer official BApps.
2. Pin versions.
3. Store checksums.
4. Download during controlled build.
5. Test inside the VM.
6. Avoid installing random extensions from untrusted sources.

---

# PHASE 13 - Create the first golden VM

Once Kali is:

```text
updated
+
security tools installed
+
Burp installed
+
Guest Additions working
+
basic configuration complete
```

SHUT IT DOWN.

Do not use it as your normal working machine.

Rename it:

```text
CyberAI-Kali-Golden
```

Take a snapshot:

```text
GOLDEN-CLEAN
```

The purpose is:

```text
CyberAI-Kali-Golden
          │
          ├── snapshot GOLDEN-CLEAN
          │
          ├── clone → Kali-Work-01
          ├── clone → Kali-CTF-01
          └── clone → Kali-Research-01
```

VirtualBox snapshots preserve VM state and can be restored, while clones can be created from them. This is exactly the workflow we want. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/networkingdetails.html?utm_source=chatgpt.com))

---

# PHASE 14 - Never work directly in Golden

This rule is worth repeating.

If you want to perform a CTF:

```text
GOLDEN
   │
   └── clone
        │
        ▼
Kali-CTF-01
```

Do your work there.

Finished?

Destroy:

```text
Kali-CTF-01
```

Your golden image remains clean.

---

# PHASE 15 - Build the Packer pipeline

Now we start automating.

Our pipeline becomes:

```text
Kali base image
      │
      ▼
    Packer
      │
      ▼
    Ansible
      │
      ├── OS update
      ├── tools
      ├── Burp
      ├── AI clients
      ├── configuration
      └── security settings
      │
      ▼
Testing
      │
      ▼
Golden image
      │
      ▼
OVA
```

Packer's VirtualBox builders support creating, provisioning, snapshotting, and exporting VirtualBox images. ([HashiCorp Developer](https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/vm?utm_source=chatgpt.com))

---

# 17. Packer source of truth

Create:

```bash
nano factory/packer/kali.pkr.hcl
```

The eventual structure will be:

```hcl
packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1"
    }
  }
}

source "virtualbox-ovf" "kali" {
  source_path = var.kali_ova

  vm_name = "CyberAI-Kali-Build"

  cpus   = 6
  memory = 16384

  shutdown_command = "sudo shutdown -P now"
}

build {
  sources = [
    "source.virtualbox-ovf.kali"
  ]

  provisioner "ansible" {
    playbook_file = "../ansible/playbooks/kali.yml"
  }
}
```

**Don't copy this blindly yet.**

We will adapt it to the actual Kali image and SSH configuration.

The important concept is:

```text
OVA
 ↓
Packer
 ↓
Ansible
 ↓
new image
```

---

# PHASE 16 - Ansible

Create:

```bash
nano factory/ansible/playbooks/kali.yml
```

Eventually:

```yaml
---
- name: Configure CyberAI Kali
  hosts: all
  become: true

  roles:
    - common
    - security_tools
    - burp
    - ai_clients
    - hardening
```

Then:

```text
roles/
├── common/
├── security_tools/
├── burp/
├── ai_clients/
└── hardening/
```

This is much easier to maintain than a 2,000-line shell script.

---

# 18. What each role does

## common

```text
updates
packages
timezone
users
shell
git
curl
jq
tmux
```

## security_tools

```text
Nmap
ffuf
Gobuster
SQLMap
Nikto
WPScan
Wireshark
Metasploit
etc.
```

## burp

```text
Burp
extensions
configuration
certificates
```

## ai_clients

```text
OpenCode
Codex
Claude tooling
Ollama
other clients
```

## hardening

```text
disable unnecessary services
reduce integration
firewall
safe defaults
```

---

# PHASE 17 - Network architecture

We will create four explicit modes.

## Mode 1 - OFFLINE

```text
Kali
 │
 X Internet
 X Host
 X LAN
```

VirtualBox:

```text
Adapter 1:
Not attached
```

This is the safest mode for particularly risky samples.

VirtualBox explicitly provides a "Not attached" mode that behaves as if the virtual Ethernet cable were unplugged. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/networkingdetails.html?utm_source=chatgpt.com))

---

# 19. Mode 2 - NAT

```text
Kali
  │
VirtualBox NAT
  │
Ubuntu
  │
Internet
```

Use this for:

```text
apt update
download tools
AI APIs
research
RAG updates
```

NAT is VirtualBox's standard outbound networking mode and normally does not expose the VM directly to the outside network. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/networkingdetails.html?utm_source=chatgpt.com))

But:

> NAT is not equivalent to complete isolation.

VirtualBox's security documentation specifically notes that NAT permits access to the host's loopback interface. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/Security.html?utm_source=chatgpt.com))

So our architecture will still treat network mode as an explicit security control.

---

# 20. Mode 3 - Host-only

```text
Ubuntu
   │
Host-only network
   │
Kali
```

No Internet.

Useful for:

```text
host ↔ VM
VM ↔ RAG
VM ↔ another lab VM
```

VirtualBox documents host-only networking as a network between the host and selected VMs without external network connectivity. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/networkingdetails.html?utm_source=chatgpt.com))

---

# 21. Mode 4 - Bridged

```text
Home/office router
       │
       ├── Ubuntu
       │
       └── Kali
```

Kali becomes a device on your physical network.

This should be:

```text
EXPLICITLY ENABLED
```

not default.

VirtualBox notes that bridged networking gives the VM direct access to the physical network and recommends considering NAT port forwarding instead in situations where only specific access is needed. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/Security.html?utm_source=chatgpt.com))

---

# 22. Our network profiles

We'll eventually implement:

```text
isolated
nat
host-only
bridged
```

So the workflow becomes:

```bash
./cyberai start kali --network isolated
```

or:

```bash
./cyberai start kali --network nat
```

or:

```bash
./cyberai start kali --network host-only
```

or, only when deliberately needed:

```bash
./cyberai start kali --network bridged
```

---

# PHASE 18 - File transfer

We need a controlled transfer mechanism.

I recommend two mechanisms.

## Method A - Temporary shared folder

Host:

```text
CyberAI/transfer/
```

Guest:

```text
/mnt/transfer
```

Mount it only when necessary.

Prefer:

```text
read-only
```

where possible.

Then unmount it.

---

# 23. Method B - Temporary HTTP server

Host:

```bash
cd "$CYBERAI/transfer"
python3 -m http.server 8000
```

VM downloads:

```bash
wget http://HOST-IP:8000/file
```

Then stop the server:

```text
CTRL+C
```

This is excellent for one-off transfers because there is no permanent shared filesystem integration.

---

# PHASE 19 - Shared RAG

Only after Kali + networking + disposable clones work should we build the RAG.

The architecture is:

```text
                  INTERNET
                     │
         ┌───────────┼───────────┐
         ▼           ▼           ▼
        CVE       Advisories   Research
         │           │           │
         └───────────┼───────────┘
                     ▼
                INGESTION
                     │
                  NORMALIZE
                     │
                  DEDUPE
                     │
               VALIDATE/CORRELATE
                     │
                  EMBEDDINGS
                     │
                 VECTOR DB
                     │
                 RAG API
                     │
       ┌─────────────┼──────────────┐
       ▼             ▼              ▼
     Kali 1        Kali 2         Kali 3
```

---

# 24. RAG must not live inside every Kali VM

Wrong:

```text
Kali 1
 └── RAG

Kali 2
 └── RAG

Kali 3
 └── RAG
```

Correct:

```text
                RAG VM
                  │
        ┌─────────┼─────────┐
        ▼         ▼         ▼
      Kali 1    Kali 2    Kali 3
```

Then when you update CVEs:

```text
RAG updated
```

rather than:

```text
rebuild Kali 1
rebuild Kali 2
rebuild Kali 3
```

---

# 25. RAG knowledge layers

We will have:

## Layer A - Stable knowledge

Examples:

```text
OWASP
CWE
HTTP
TLS
Linux
networking
cryptography
MITRE ATT&CK
security standards
official documentation
```

## Layer B - Current intelligence

Examples:

```text
new CVEs
vendor advisories
CISA alerts
security research
confirmed exploitation
new tool releases
new techniques
```

---

# 26. Every RAG document gets metadata

Something like:

```json
{
  "source": "vendor",
  "url": "...",
  "published_at": "...",
  "updated_at": "...",
  "retrieved_at": "...",
  "cve": "CVE-XXXX-XXXXX",
  "cwe": "...",
  "vendor": "...",
  "product": "...",
  "confidence": "high",
  "source_tier": 1
}
```

This is extremely important.

We don't want:

```text
Random Reddit post
       =
CISA advisory
       =
Vendor security bulletin
```

The RAG should know the difference.

---

# 27. RAG source tiers

We'll implement:

```text
TIER 1
Official/authoritative

TIER 2
Established security research

TIER 3
Community research/GitHub/blogs

TIER 4
Unverified claims
```

And the AI should answer something like:

```text
Evidence:
Vendor advisory - high confidence

Supporting research:
Research paper - medium/high confidence

Community claim:
Unverified
```

rather than pretending everything is equally verified.

---

# PHASE 20 - RAG storage

For the first version:

```text
RAG VM
├── ingestion
├── metadata database
├── vector database
└── API
```

Later we can choose the exact stack.

I would **not** start by installing five different databases.

First establish:

```text
source
→ ingestion
→ retrieval
→ answer
```

Then optimize.

---

# PHASE 21 - AI layer

Now we add AI.

We will support:

```text
LOCAL
```

and:

```text
CLOUD
```

independently.

---

# 28. Local AI

Inside or accessible to Kali:

```text
Ollama
```

Potentially:

```text
llama.cpp
```

Then:

```text
OpenCode
      │
      ▼
Ollama
      │
      ▼
local model
```

No Internet required after the model is downloaded.

---

# 29. Cloud AI

For example:

```text
OpenCode
    │
    ├── OpenAI
    ├── Anthropic
    ├── DeepSeek
    ├── OpenRouter
    └── other providers
```

OpenCode supports a large number of providers, including cloud and local providers, so it is useful as **one interchangeable client**, not as the architecture itself.

---

# 30. API keys

Never put keys into:

```text
Packer
Git
Ansible repository
OVA
golden VM
```

Instead use environment/secret storage.

For example:

```text
OPENAI_API_KEY
ANTHROPIC_API_KEY
DEEPSEEK_API_KEY
```

Only expose them to a VM when that VM actually needs them.

---

# 31. Local vs cloud experiment

We will eventually benchmark:

```text
Same prompt
Same context
Same task
```

against:

```text
Local model
OpenAI
Claude
DeepSeek
etc.
```

Measure:

```text
latency
tokens/sec
time-to-first-token
RAM
CPU
answer quality
tool-use reliability
RAG accuracy
```

Do not judge models from one random prompt.

We'll create a repeatable benchmark set.

---

# PHASE 22 - RAG + AI together

The final workflow becomes:

```text
User
 │
 ▼
AI Agent
 │
 ├───────────────► Security tools
 │
 ├───────────────► Kali
 │
 └───────────────► RAG API
                       │
                       ▼
                 Verified sources
```

For example:

```text
"What does CVE-X affect?"
```

AI asks:

```text
RAG
```

RAG retrieves:

```text
Vendor advisory
CVE record
research
```

Then AI answers with provenance.

---

# PHASE 23 - VM lifecycle

We eventually want these commands:

```bash
./cyberai list
```

```bash
./cyberai create kali-ctf-01
```

```bash
./cyberai start kali-ctf-01 --network isolated
```

```bash
./cyberai start kali-ctf-01 --network nat
```

```bash
./cyberai snapshot kali-ctf-01 checkpoint-01
```

```bash
./cyberai restore kali-ctf-01 checkpoint-01
```

```bash
./cyberai stop kali-ctf-01
```

```bash
./cyberai destroy kali-ctf-01
```

Destroying:

```text
kali-ctf-01
```

must not destroy:

```text
Golden image
RAG
configuration
models
tool manifests
```

---

# 32. Snapshot strategy

For each working VM:

```text
Kali-Work-01

    SNAPSHOT
       │
       ▼
  CLEAN-START
       │
       ▼
   experiment
       │
       ▼
  SNAPSHOT
   TEST-01
```

If something goes wrong:

```text
restore TEST-01
```

or:

```text
restore CLEAN-START
```

---

# PHASE 24 - Security boundaries

Your architecture should look like:

```text
                 HOST
        ┌───────────────────────┐
        │ Ubuntu                │
        │                       │
        │ VirtualBox            │
        │                       │
        │  ┌─────────────────┐  │
        │  │ Kali            │  │
        │  │                 │  │
        │  │ Burp            │  │
        │  │ tools           │  │
        │  │ AI              │  │
        │  └─────────────────┘  │
        │                       │
        └───────────────────────┘
```

Avoid unnecessary:

```text
clipboard sharing
drag/drop
permanent shared folders
USB passthrough
webcam passthrough
microphone
host filesystem access
bridged networking
```

especially in risky labs.

A VM provides a strong isolation boundary, but it is not an absolute guarantee that arbitrary malicious code can never affect the host. VirtualBox itself documents security considerations around networking and VM integration. ([Oracle Docs](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/Security.html?utm_source=chatgpt.com))

---

# PHASE 25 - Golden image release process

Every release gets a version.

For example:

```text
CyberAI-Kali-2026.09.01
```

Then:

```text
images/
└── releases/
    ├── CyberAI-Kali-2026.09.01.ova
    ├── CyberAI-Kali-2026.09.01.sha256
    └── manifest.json
```

The manifest could contain:

```json
{
  "version": "2026.09.01",
  "kali": "...",
  "virtualbox": "...",
  "packer": "...",
  "ansible": "...",
  "tools": "...",
  "burp": "...",
  "build_date": "..."
}
```

This makes your environment reproducible.

---

# PHASE 26 - External SSD layout

Your SSD eventually looks like:

```text
CyberAI-SSD
│
└── CyberAI
    │
    ├── factory/
    │
    ├── images/
    │   ├── golden/
    │   └── releases/
    │
    ├── models/
    │
    ├── rag/
    │
    ├── labs/
    │
    ├── artifacts/
    │
    ├── transfer/
    │
    └── backups/
```

Your internal Ubuntu drive should contain mostly:

```text
OS
applications
configuration
```

while the external SSD contains:

```text
VMs
models
RAG data
OVA files
large artifacts
```

---

# PHASE 27 - Backup strategy

Your external SSD is **not** the backup.

Use your existing HDD as cold backup.

Example:

```text
External SSD
     │
     ├── active VMs
     ├── current RAG
     └── current models
              │
              ▼
       External HDD
       backup/archive
```

Back up:

```text
factory/
profiles/
tools/
burp/
rag/config/
images/releases/
docs/
```

The largest disposable things don't necessarily need continuous backup:

```text
working VMs
temporary artifacts
temporary lab data
```

But golden OVA releases should be backed up.

---

# PHASE 28 - Portability to another computer

Suppose you buy another computer.

Install:

```text
VirtualBox
```

Connect SSD.

Then:

```text
CyberAI/
   images/releases/
       CyberAI-Kali-2026.09.01.ova
```

Import:

```text
VirtualBox
 → Import
 → OVA
```

The VM runs.

Your architecture therefore becomes:

```text
Computer A
    │
    └── External SSD
           │
           └── CyberAI
                 │
                 └── OVA

Computer B
    │
    └── External SSD
           │
           └── same CyberAI
```

VirtualBox supports VM import/export, and Packer's VirtualBox builders also support OVA/OVF workflows. ([HashiCorp Developer](https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/ovf?utm_source=chatgpt.com))

---

# PHASE 29 - Future Windows host

We should **not** design the guest architecture around Ubuntu-specific paths.

Instead:

```text
Host layer
──────────

Ubuntu
Windows
```

both provide:

```text
VirtualBox
external storage
CyberAI factory
```

while:

```text
Kali
RAG
AI clients
tool configuration
```

remain essentially the same.

Only the host automation layer changes.

---

# PHASE 30 - The eventual command interface

This is the end goal.

You should eventually be able to do:

### Build

```bash
./cyberai build kali
```

### Build local-AI profile

```bash
./cyberai build kali --profile ai-local
```

### Build cloud-AI profile

```bash
./cyberai build kali --profile ai-cloud
```

### Multi-AI

```bash
./cyberai build kali --profile multi-ai
```

### RAG

```bash
./cyberai build rag
```

### Update RAG

```bash
./cyberai rag update
```

### Start isolated

```bash
./cyberai start kali-ctf-01 --network isolated
```

### Start Internet

```bash
./cyberai start kali-ctf-01 --network nat
```

### Start host-only

```bash
./cyberai start kali-ctf-01 --network host-only
```

### Snapshot

```bash
./cyberai snapshot kali-ctf-01
```

### Destroy

```bash
./cyberai destroy kali-ctf-01
```

---

# 33. What happens when you add a new tool?

Suppose six months from now you want:

```text
Tool-X
```

You should **not** open every Kali VM and install it manually.

Instead:

```text
tools/apt.yml
       │
       ▼
add Tool-X
       │
       ▼
git commit
       │
       ▼
Packer
       │
       ▼
Ansible
       │
       ▼
new Golden Image
       │
       ▼
new clones contain Tool-X
```

That is the entire reason we're building this architecture.

---

# 34. What happens when a CVE is released?

You should **not rebuild Kali**.

Instead:

```text
New CVE
   │
   ▼
RAG ingestion
   │
   ▼
validate
   │
   ▼
deduplicate
   │
   ▼
embed
   │
   ▼
RAG database
```

Then every Kali VM can query:

```text
same RAG
```

---

# 35. What happens when an AI provider changes?

You should **not rebuild Kali**.

Provider configuration should be externalized.

For example:

```text
AI provider
    │
    ├── OpenAI
    ├── Anthropic
    ├── DeepSeek
    ├── Ollama
    └── OpenRouter
```

Changing provider should therefore be a configuration change, not a VM rebuild.

---

# 36. What happens if Kali gets destroyed?

Nothing important.

You delete:

```text
Kali-CTF-01
```

Then:

```text
Golden image
     │
     ▼
new clone
     │
     ▼
Kali-CTF-02
```

This is exactly the behavior we want.

---

# 37. What happens if Golden gets corrupted?

This is why we have:

```text
source configuration
+
OVA release
+
Git
+
backup HDD
```

You rebuild it.

The golden image itself is not the ultimate source of truth.

The ultimate source is:

```text
Git configuration
+
build automation
```

---

# 38. What we should NOT build initially

Don't start with:

```text
Kubernetes
Docker Swarm
multiple RAG databases
GPU passthrough
distributed inference
10 different LLMs
automatic exploit generation
automatic Internet scanning
complex orchestration
```

Those are future features.

Start with:

```text
VirtualBox
     ↓
Kali
     ↓
automation
     ↓
network isolation
     ↓
RAG
     ↓
AI
```

---

# 39. First milestone

Your first milestone should be:

```text
Ubuntu
  │
  ├── VirtualBox
  │
  └── CyberAI SSD
          │
          └── CyberAI project
                  │
                  └── Kali VM
```

And you must be able to:

```text
start Kali
↓
update Kali
↓
run security tools
↓
shutdown Kali
↓
snapshot Kali
↓
clone Kali
↓
start clone
↓
delete clone
```

**Do not proceed to RAG until this works.**

---

# 40. Second milestone

Then:

```text
Kali Golden
     │
     ├── security tools
     ├── Burp
     ├── extensions
     └── configuration
```

And:

```text
Packer
   +
Ansible
```

can reproduce it.

---

# 41. Third milestone

Networking:

```text
OFFLINE
NAT
HOST-ONLY
BRIDGED
```

and you can switch between them without manually rebuilding the VM.

---

# 42. Fourth milestone

RAG:

```text
RAG VM
 │
 ├── stable knowledge
 ├── CVEs
 ├── advisories
 ├── research
 └── retrieval API
```

Kali:

```text
Kali
 │
 └── query RAG
```

---

# 43. Fifth milestone

AI:

```text
Kali
 │
 ├── Ollama
 ├── OpenCode
 ├── Codex
 ├── Claude tooling
 └── other providers
```

with:

```text
local
cloud
```

being selectable.

---

# 44. Sixth milestone

Benchmarking:

```text
                    Same task
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
    Local AI        OpenAI         Anthropic
       │               │               │
       └───────────────┼───────────────┘
                       ▼
                 benchmark data
```

Then we'll have actual measurements rather than guessing which model is suitable.

---

# 45. Your complete build order

Follow this **exact order**:

```text
[01] Ubuntu update
       ↓
[02] Verify CPU virtualization
       ↓
[03] Buy/connect external SSD
       ↓
[04] Verify SSD device carefully
       ↓
[05] Format/mount SSD
       ↓
[06] Create CyberAI directory
       ↓
[07] Install VirtualBox
       ↓
[08] Move VirtualBox default VM storage to SSD
       ↓
[09] Install Git
       ↓
[10] Create CyberAI repository
       ↓
[11] Install Packer
       ↓
[12] Install Ansible
       ↓
[13] Download official Kali VirtualBox image
       ↓
[14] Verify Kali checksum
       ↓
[15] Import Kali
       ↓
[16] Configure Kali
       ↓
[17] Update Kali
       ↓
[18] Install Kali security metapackages
       ↓
[19] Install additional tools
       ↓
[20] Install/configure Burp
       ↓
[21] Configure Guest Additions
       ↓
[22] Create Golden Kali
       ↓
[23] Snapshot Golden
       ↓
[24] Create disposable clone
       ↓
[25] Test clone
       ↓
[26] Build network profiles
       ↓
[27] Build Ansible roles
       ↓
[28] Build Packer pipeline
       ↓
[29] Generate reproducible Golden OVA
       ↓
[30] Build RAG VM
       ↓
[31] Build RAG ingestion
       ↓
[32] Add authoritative sources
       ↓
[33] Add live CVE/advisory feeds
       ↓
[34] Add retrieval API
       ↓
[35] Connect Kali → RAG
       ↓
[36] Install local AI
       ↓
[37] Install OpenCode
       ↓
[38] Configure cloud providers
       ↓
[39] Add AI profiles
       ↓
[40] Benchmark
       ↓
[41] Backup
       ↓
[42] Test disaster recovery
       ↓
[43] Export portable OVA
```

---

# 46. The most important part for you right now

**Do not start installing Kali tools yet.**

Your immediate job is only:

### Step A

Check your current system:

```bash
lsb_release -a
```

```bash
lscpu | grep -E 'Virtualization|Model name|CPU\(s\)'
```

```bash
df -h
```

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
```

### Step B

Install/check:

```bash
git --version
```

```bash
virtualbox --help
```

```bash
packer version
```

```bash
ansible --version
```

If one isn't installed, that's fine.

### Step C

**When your external SSD arrives, do not format it yet.**

Run:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
```

and identify it carefully before doing anything destructive.

---

## The architecture we're aiming for

![Image](https://images.openai.com/static-rsc-4/4fVaseLhpMNk-jMIWwOAu0_nbbPQ0iu3NltcTa2NzNTtwvntFHMi1vD9xIUXbAMmv1N3Mm3JW63VuMf8vuzjr7UgxOBfyg207s-yiidRlUTu0aYMJESgRDZAZF_5gqBGTT04GAq0-NL6Sww3NLYNwPi5tvqqWHkye6VBvzDsVOABKmC2WQtbqhIq9lDjOzDI?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/53h8g3TZ5nK2En-3wT2IkVqF2a7uDxkZ9ThRJXzjmBcwOBuqDeYbMy3Gp_wzLfB5uad249OHPmDtvum6FByMQlLLCuEY2Lt5brfEwJtpsOsY1mKTWGrCrWjcLDDzYOl1EfnsKpKfJX5j6l0_i6aiFjxcFtQEiprwTZ4PUeQUZg_7xVNi_mxKgV5A0UpQzMf0?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/DOJrLfrVHl7CCuWpIXovZ_LRyArFZqhq_XAZc8sYmFv1IDR6XUquUykVW-SXOhVRFwXRN2CvFth7z2fEu_lbeRwvcOOtDcir2daputMIQNKJB-C4U4eyRhZVsp69LH0x6nMfVgu6S9Qo_Gpqe4taBFRfLxjD8rrzKEqvdBL7MFLYi2fE1Ie3XBJo4onIIA0Y?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/M2bYo53isKHRz23t6mdxHF_R7JR-ntZEoa0UiqGUMzVqHxKg0phPWNRaAGiA70pYwnLn0L3IxsPR-Pev2MTDOXRmrkSTPtLDYQppSPi-dEePeWGs_AgyvqwfB9KsLyqNpAIikmHY8OXg7c75zV8i9DaXwHDbAweSV1M_A2a3tECPjoLFMzUXkq4omcPAmMSF?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/QAN6RiwiSBG7kNDpmq-OdiOgIIPc_rhISX4pponiR4V-twR1SkncBTDiH-cU8_cEsiVgjAMmx_FtV6rcWhjoYaMUaQ2WTeCpOp19DZpSf4N4NYZnc3daI0CQrvvNb2REHjuSiTeL-HQWwIu-Gq1bmfuy81kWPaycsMoLDvn1_PORq9euIbjwGhbs_Af3uyJh?purpose=fullsize)

```text
                         ┌──────────────────────────┐
                         │      UBUNTU HOST         │
                         │                          │
                         │  i5-13600K / 32 GB       │
                         │                          │
                         │       VirtualBox         │
                         └────────────┬─────────────┘
                                      │
              ┌───────────────────────┼──────────────────────┐
              │                       │                      │
              ▼                       ▼                      ▼
       ┌─────────────┐        ┌──────────────┐       ┌─────────────┐
       │ Kali Golden │        │ Kali Work VM │       │  RAG VM     │
       │             │        │              │       │             │
       │ DO NOT USE  │───────►│ Burp         │       │ CVEs        │
       │ DIRECTLY    │ clone  │ Nmap         │       │ Advisories  │
       │             │        │ ffuf         │       │ Research    │
       └─────────────┘        │ sqlmap       │       │ Vector DB   │
                              │ AI clients   │       │ API         │
                              └──────┬───────┘       └──────┬──────┘
                                     │                      │
                         ┌───────────┼────────────┐         │
                         │           │            │         │
                         ▼           ▼            ▼         │
                       Ollama     OpenCode      Cloud ◄─────┘
                         │           │         APIs
                         ▼           ▼
                      Local AI   Multi-provider AI
```

### One important adjustment to the earlier plan

For a first-time setup, **I would not start by writing the complete Packer-from-ISO installer**. That's where beginners commonly get buried in unattended Kali installer details.

Instead:

```text
Official Kali VirtualBox image
             ↓
      manually verify it
             ↓
      make first Golden VM
             ↓
      automate configuration
             ↓
      Packer + Ansible
             ↓
      fully reproducible images
```

Packer can subsequently use an existing OVA/OVF as its source, provision it, and produce a new image, which gives us a much smoother path from beginner setup to full automation. ([HashiCorp Developer](https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/ovf?utm_source=chatgpt.com))

That means **you get a working lab early**, while we progressively automate it rather than spending days debugging the image factory before you even have Kali running.

---

## Your first checkpoint

Don't execute 40 phases at once.

**Start with Phase 1-4 only.**

Run these four commands and keep the output:

```bash
lsb_release -a
```

```bash
lscpu | grep -E 'Virtualization|Model name|CPU\(s\)'
```

```bash
df -h
```

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
```

Then install/check the three automation components:

```bash
virtualbox --version
```

```bash
packer version
```

```bash
ansible --version
```

Once those are done, **the next step is the external SSD + VirtualBox setup**, and from there we can proceed one phase at a time without you having to guess what command belongs where.

---

**Sources:**

- [Downloading Kali Linux | Kali Linux Documentation](https://www.kali.org/docs/introduction/download-official-kali-linux-images/?utm_source=chatgpt.com)
- [Virtual Networking](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/networkingdetails.html?utm_source=chatgpt.com)
- [Index of http://download.virtualbox.org/virtualbox/7.2.8](https://download.virtualbox.org/virtualbox/7.2.8/?utm_source=chatgpt.com)
- [VirtualBox Builder | Integrations | Packer | HashiCorp Developer](https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox/latest/components/builder/vm?utm_source=chatgpt.com)
- [Getting started with Ansible — Ansible Community Documentation](https://docs.ansible.com/projects/ansible/latest/getting_started/index.html?utm_source=chatgpt.com)

## Prompt:
9/19/2026, 10:49:39 PM

Hey currently I do not have the SSD and I will be performing all setups in my directory sandeep03edu-ubuntu@sandeep03edu-ubuntu:~/Personal/CyberAIKaliVM$

So can you update the plan in a way that we can perform all setups in my Linux machine as of now and then move or shift that to SSD in future which can be an additional step

## Response:
9/19/2026, 10:49:41 PM

Absolutely. **Do not wait for the SSD.** We can build the entire CyberAI lab under:

```text
~/Personal/CyberAIKaliVM
```

and later make the SSD a **storage migration step**, not a rebuild.

The key is to separate **configuration/source code** from **large VM/model/RAG data** from the beginning.

---

# Updated architecture

For now:

```text
Ubuntu internal NVMe
│
└── ~/Personal/CyberAIKaliVM/
    │
    ├── factory/          ← source/configuration
    ├── profiles/         ← VM profiles
    ├── tools/            ← tool manifests
    ├── burp/             ← Burp configuration
    ├── rag/              ← RAG configuration/data
    ├── models/           ← local AI models
    ├── images/           ← VM images
    ├── labs/             ← disposable VMs
    ├── artifacts/        ← build artifacts
    ├── transfer/         ← temporary transfer
    ├── backups/          ← local backups
    └── docs/             ← documentation
```

Later:

```text
External SSD
│
└── CyberAIKaliVM/
    │
    ├── factory/
    ├── profiles/
    ├── tools/
    ├── burp/
    ├── rag/
    ├── models/
    ├── images/
    ├── labs/
    ├── artifacts/
    ├── transfer/
    ├── backups/
    └── docs/
```

So the **directory structure doesn't change**.

Only the physical location changes.

---

# One important change to the previous plan

Previously I suggested moving VirtualBox's default VM directory to the SSD.

**Do not do that now.**

Keep everything inside your current project until the SSD arrives.

Later we'll explicitly move the large components:

```text
Current:

~/Personal/CyberAIKaliVM/
    images/
    labs/
    models/
    rag/

Future:

/media/.../CyberAIKaliVM/
    images/
    labs/
    models/
    rag/
```

The automation will use a configurable root directory so we don't hard-code:

```text
/home/sandeep/...
```

anywhere.

---

# New complete plan

We're going to split the project into:

```text
                    CyberAIKaliVM
                          │
             ┌────────────┴────────────┐
             │                         │
       SOURCE / CONFIG             LARGE DATA
             │                         │
             ▼                         ▼
       factory/                   images/
       profiles/                 labs/
       tools/                    models/
       burp/                     rag/database/
       scripts/                  artifacts/
       docs/                     backups/
```

This is what makes the future SSD migration easy.

---

# PHASE 0 - Establish the project root

You already have:

```text
~/Personal/CyberAIKaliVM
```

Let's make that the permanent logical root.

Open Terminal:

```bash
cd ~/Personal/CyberAIKaliVM
```

Verify:

```bash
pwd
```

You should get:

```text
/home/<your-user>/Personal/CyberAIKaliVM
```

Don't worry about your username being different from examples I use.

---

# PHASE 1 - Create the complete structure

Run:

```bash
mkdir -p \
factory/packer \
factory/ansible/inventory \
factory/ansible/playbooks \
factory/ansible/roles \
factory/scripts \
profiles \
tools \
burp/configs \
burp/artifacts \
rag/config \
rag/ingestion \
rag/sources \
rag/database \
rag/backups \
models \
images/golden \
images/releases \
images/checksums \
labs/active \
labs/snapshots \
labs/destroyed \
artifacts \
transfer \
backups \
docs/architecture \
docs/networking \
docs/recovery \
docs/benchmarks
```

Then:

```bash
find . -maxdepth 2 -type d | sort
```

You should now see the basic CyberAI structure.

---

# PHASE 2 - Create a configuration file

This is one of the most important changes.

We will **never hard-code the storage location** into our scripts.

Create:

```bash
nano .cyberai.env
```

Put:

```bash
CYBERAI_ROOT="$HOME/Personal/CyberAIKaliVM"

CYBERAI_IMAGES="$CYBERAI_ROOT/images"
CYBERAI_LABS="$CYBERAI_ROOT/labs"
CYBERAI_MODELS="$CYBERAI_ROOT/models"
CYBERAI_RAG="$CYBERAI_ROOT/rag"
CYBERAI_ARTIFACTS="$CYBERAI_ROOT/artifacts"
CYBERAI_BACKUPS="$CYBERAI_ROOT/backups"
CYBERAI_TRANSFER="$CYBERAI_ROOT/transfer"
```

Save it.

Later, when the SSD arrives, we change essentially this:

```bash
CYBERAI_ROOT="/media/.../CyberAIKaliVM"
```

instead of rewriting the whole project.

---

# PHASE 3 - Don't put `.cyberai.env` into Git

Add it to `.gitignore`:

```bash
nano .gitignore
```

Use:

```text
# Local configuration
.cyberai.env

# Secrets
.env
.env.*
*.key
*.pem
*.token
*.secret

# Virtual machines
*.vdi
*.vmdk
*.vhd
*.qcow2
*.sav
*.nvram

# VirtualBox
*.log

# Burp projects
*.burp
*.burpsuite

# Local RAG database
rag/database/*
rag/backups/*

# Local models
models/*

# Temporary files
transfer/*
artifacts/*

# Python
__pycache__/
*.pyc

# OS/editor
.DS_Store
.vscode/
.idea/
```

---

# PHASE 4 - Initialize Git

From:

```bash
cd ~/Personal/CyberAIKaliVM
```

run:

```bash
git init
```

Then:

```bash
git add .gitignore
```

Then:

```bash
git commit -m "Initial CyberAIKaliVM structure"
```

Your Git repository will contain the **instructions for building the lab**, not necessarily the huge VM disks.

That's exactly what we want.

---

# PHASE 5 - Check available internal storage

Because you're temporarily keeping everything on the internal NVMe, we need to watch storage carefully.

Run:

```bash
df -h "$HOME"
```

You previously had roughly 309 GB available.

That's enough to get started, but we shouldn't immediately fill it with:

```text
multiple Kali VMs
+
large local models
+
RAG database
+
OVA backups
```

We'll deliberately control storage.

---

# Storage strategy while waiting for SSD

For now:

```text
Internal NVMe
│
├── Source/configuration       small
├── One Golden Kali VM         ~80-120 GB
├── One disposable Kali VM    ~80-120 GB
├── RAG                       small initially
└── Models                    carefully selected
```

Do **not** create 5-10 Kali VMs yet.

You don't need them.

---

# PHASE 6 - VirtualBox

Install VirtualBox, but **don't change its default storage location yet**.

After installation:

```bash
VBoxManage --version
```

Then:

```bash
VBoxManage list systemproperties
```

Look for:

```text
Default machine folder
```

For now, that's okay.

---

# PHASE 7 - Use a dedicated VirtualBox directory

Rather than letting VirtualBox scatter VMs around your home directory, we'll eventually point it to:

```text
~/Personal/CyberAIKaliVM/images
```

For example:

```bash
mkdir -p ~/Personal/CyberAIKaliVM/images
```

Then:

```bash
VBoxManage setproperty machinefolder "$HOME/Personal/CyberAIKaliVM/images"
```

Check:

```bash
VBoxManage list systemproperties | grep -i "Default machine folder"
```

It should point to your CyberAI directory.

---

# Why we're doing this now

Later, when the SSD arrives, we don't want:

```text
VirtualBox
    ↓
VM somewhere random in /home
```

Instead:

```text
VirtualBox
    ↓
CyberAI root
    ↓
images/
```

Then migration is much easier.

---

# PHASE 8 - First Kali VM

Now we download the official Kali VirtualBox image.

The important thing here is:

**Do not manually install Kali from an ISO yet.**

For your first build, use Kali's official pre-built VirtualBox image.

Kali provides pre-built VirtualBox images specifically for this purpose and documents importing them into VirtualBox. 

Download it from Kali's official website and verify its checksum before importing it.

Then import it.

---

# PHASE 9 - Naming convention

Don't call the first VM simply:

```text
Kali
```

Use:

```text
CyberAI-Kali-Golden
```

Later:

```text
CyberAI-Kali-Work-01
CyberAI-Kali-CTF-01
CyberAI-Kali-Research-01
```

RAG:

```text
CyberAI-RAG
```

This will become important once you have multiple VMs.

---

# PHASE 10 - VM storage layout

Initially:

```text
~/Personal/CyberAIKaliVM/
│
├── images/
│   ├── golden/
│   └── releases/
│
└── labs/
    ├── active/
    ├── snapshots/
    └── destroyed/
```

But there's an important distinction:

### `images/`

Permanent/generated images.

### `labs/active/`

Currently running working VMs.

### `labs/destroyed/`

Optional temporary archive.

### `images/releases/`

Portable OVA files.

This prevents us from mixing:

```text
golden
working VM
OVA
snapshot
```

into one directory.

---

# PHASE 11 - First Golden Kali

Once Kali boots:

1. Update Kali.
2. Install Guest Additions if required.
3. Configure basic system settings.
4. Install your baseline security tools.
5. Install Burp.
6. Configure Burp.
7. Verify everything.
8. Shut down.
9. Snapshot.

Kali recommends updating before installing its metapackages. 

For the initial baseline, we'll use Kali's purpose-specific metapackages rather than immediately installing the enormous `kali-linux-everything` collection.

---

# PHASE 12 - Golden snapshot

Once the VM is correct:

```text
CyberAI-Kali-Golden
        │
        ▼
GOLDEN-CLEAN
```

The golden VM becomes:

> **Read-only conceptually.**

You don't have to make the disk literally read-only.

You simply don't use it for actual work.

---

# PHASE 13 - Create first disposable VM

Clone:

```text
CyberAI-Kali-Golden
        │
        ▼
CyberAI-Kali-Work-01
```

Now:

```text
Golden
  │
  └── Work-01
```

Work only inside:

```text
CyberAI-Kali-Work-01
```

---

# PHASE 14 - Test destruction

This is an important test.

Inside Work-01:

```text
create files
install something
change configuration
perform lab work
```

Then shut it down.

Delete it.

Create another clone:

```text
Golden
  │
  └── Work-02
```

Verify Work-02 starts clean.

If that works:

**your disposable VM architecture works.**

---

# PHASE 15 - Automation

Only after the above works do we automate.

We'll install:

```text
Packer
Ansible
```

Then:

```text
Packer
   │
   ▼
Kali base
   │
   ▼
Ansible
   │
   ├── packages
   ├── security tools
   ├── Burp
   ├── AI clients
   └── hardening
   │
   ▼
Golden image
```

This prevents us from trying to debug:

```text
VirtualBox
+
Kali
+
Packer
+
Ansible
+
Burp
+
AI
```

all at once.

---

# PHASE 16 - Tool manifest

We'll have:

```text
tools/
├── apt.yml
├── pip.yml
├── github.yml
└── binaries.yml
```

Example:

```yaml
packages:
  - nmap
  - ffuf
  - gobuster
  - sqlmap
  - nikto
  - wpscan
  - wireshark
  - tcpdump
```

Then the VM build process reads this.

So six months later:

```text
add tool
   ↓
edit manifest
   ↓
rebuild Golden
```

rather than manually modifying every VM.

---

# PHASE 17 - Burp

Burp will have its own configuration:

```text
burp/
├── configs/
├── artifacts/
└── extensions.lock
```

We'll pin the extensions and configurations.

PortSwigger documents both manual extension installation and Burp configuration import/export. 

---

# PHASE 18 - Network modes

We'll create:

```text
isolated
nat
host-only
bridged
```

The default will be:

```text
isolated
```

or, when Internet is needed:

```text
nat
```

We won't use bridged networking unless you specifically need it.

VirtualBox documents the security and behavior differences between NAT, host-only, internal and bridged networking. 

---

# PHASE 19 - Transfer system

Keep:

```text
transfer/
```

in the project root.

For example:

```text
~/Personal/CyberAIKaliVM/transfer/
```

For temporary transfers we can use:

```bash
python3 -m http.server
```

or a transient VirtualBox shared folder.

VirtualBox supports transient shared folders that disappear when the VM powers off, which fits this architecture well. 

---

# PHASE 20 - RAG

The RAG VM will initially live here:

```text
~/Personal/CyberAIKaliVM/
└── rag/
```

Eventually:

```text
External SSD
└── CyberAIKaliVM/
    └── rag/
```

No architectural change.

We'll build:

```text
RAG
├── ingestion
├── normalization
├── deduplication
├── metadata
├── embeddings
├── vector database
└── API
```

---

# PHASE 21 - AI

Local models:

```text
models/
```

Cloud providers:

```text
credentials outside Git
```

Clients:

```text
OpenCode
Codex
Claude tooling
custom CyberAI client
```

The architecture remains:

```text
model
  ↓
provider/runtime
  ↓
agent/client
```

rather than making OpenCode the central dependency.

---

# PHASE 22 - SSD migration

This becomes a **separate future phase**.

Suppose your SSD mounts as:

```text
/media/sandeep/CyberAI-SSD
```

We'll create:

```text
/media/sandeep/CyberAI-SSD/CyberAIKaliVM
```

Then shut down all VMs.

Copy:

```text
~/Personal/CyberAIKaliVM/
```

to:

```text
/media/sandeep/CyberAI-SSD/CyberAIKaliVM/
```

But we **will not blindly copy everything**.

We'll classify:

### Move

```text
images/
labs/
models/
rag/database/
artifacts/
```

### Keep / sync

```text
factory/
profiles/
tools/
burp/
docs/
scripts/
```

These are small enough to keep backed up in Git.

---

# 23. Then change one variable

Current:

```bash
CYBERAI_ROOT="$HOME/Personal/CyberAIKaliVM"
```

Future:

```bash
CYBERAI_ROOT="/media/sandeep/CyberAI-SSD/CyberAIKaliVM"
```

Then:

```text
same scripts
same automation
same profiles
same tools
same architecture
```

The storage location changed.

That's it.

---

# 24. Even better: use a symlink

There is an even easier migration option.

After moving the project to the SSD:

```text
SSD
└── CyberAIKaliVM
```

we can have:

```text
~/Personal/CyberAIKaliVM
        │
        └── symlink
              ↓
       External SSD
```

Then your scripts can continue using:

```text
~/Personal/CyberAIKaliVM
```

while the actual files are on the SSD.

For example:

```bash
mv ~/Personal/CyberAIKaliVM ~/Personal/CyberAIKaliVM-old
ln -s /media/sandeep/CyberAI-SSD/CyberAIKaliVM \
      ~/Personal/CyberAIKaliVM
```

**But don't do this now.**

We'll do it only after the SSD exists and we've verified the migration.

---

# 25. What about VirtualBox?

This is the one part that requires care.

VirtualBox stores VM registration information separately from the VM files.

After migration we may need to:

```text
unregister old VM
        ↓
register VM from new location
```

or use VirtualBox's move functionality.

We will **not manually move a running VM's `.vdi` files**.

The migration procedure will be:

```text
1. Shutdown VM
2. Verify snapshot state
3. Backup
4. Move/copy VM
5. Verify files
6. Register new location
7. Boot
8. Test
9. Only then delete old copy
```

This avoids accidentally destroying your working VM.

---

# 26. Your updated project lifecycle

The complete lifecycle is now:

```text
             NOW
              │
              ▼
     Ubuntu internal NVMe
              │
              ▼
~/Personal/CyberAIKaliVM
              │
       ┌──────┴───────┐
       ▼              ▼
   automation       VM data
       │              │
       ▼              ▼
    Git          VirtualBox
       │              │
       └──────┬───────┘
              ▼
        Golden Kali
              │
              ▼
       Disposable VMs
              │
              ▼
          RAG + AI
              │
              ▼
        TEST EVERYTHING
              │
              ▼
        SSD ARRIVES
              │
              ▼
       shutdown VMs
              │
              ▼
         backup first
              │
              ▼
       migrate large data
              │
              ▼
       update CYBERAI_ROOT
              │
              ▼
      verify everything
              │
              ▼
      continue normally
```

---

# 27. One more thing: don't fill your internal disk

Because you're currently working without the SSD, I recommend this policy:

### Initially

```text
1 Golden Kali
+
1 disposable Kali
+
small RAG
+
1-2 local models
```

### Avoid

```text
5+ Kali VMs
+
10 local models
+
multiple OVA exports
+
multiple snapshots
```

until the SSD arrives.

VM snapshots can consume significant storage because VirtualBox uses differencing disks. 

---

# 28. What I want you to do right now

**Nothing related to Kali yet.**

First let's establish the host correctly.

Run these:

```bash
cd ~/Personal/CyberAIKaliVM
```

```bash
pwd
```

```bash
df -h "$HOME"
```

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
```

```bash
lscpu | grep -E 'Virtualization|Model name|CPU\(s\)'
```

Then:

```bash
git --version
```

```bash
VBoxManage --version
```

```bash
packer version
```

```bash
ansible --version
```

If `packer`, `ansible`, or `VBoxManage` says **command not found**, that's completely fine.

**Don't start installing random packages yet.**

Send me the output of those commands. From there, we'll proceed with **Stage 1: preparing your existing Ubuntu machine and this exact `~/Personal/CyberAIKaliVM` directory**, then we'll install VirtualBox and create the first Kali VM. The SSD becomes a later migration stage rather than something that blocks us now.



---
Powered by [ChatGPT Exporter](https://www.chatgptexporter.com)