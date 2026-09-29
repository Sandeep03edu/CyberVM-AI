# Bring the lab up on a brand-new machine
```
git clone <repo> CyberVM-AI && cd CyberVM-AI
cp .cybervm.env.example .cybervm.env      # set CYBERVM_ROOT
./cybervm host-setup                      # VirtualBox must already be installed
./cybervm doctor
# then EITHER (fast) copy an .ova release and:  ./cybervm import <ova>
# OR (from source): download the Kali .7z into downloads/kali/, then:
#   ./cybervm base import && ./cybervm golden build
./cybervm rag up && ./cybervm rag update live
```
Requirements on the new host: x86-64, VT-x enabled, VirtualBox 7.1+, ≥16 GB RAM, ~200 GB free.
