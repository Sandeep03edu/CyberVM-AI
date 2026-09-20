# Bring the lab up on a brand-new machine
```
git clone <repo> CyberAIKaliVM && cd CyberAIKaliVM
cp .cyberai.env.example .cyberai.env      # set CYBERAI_ROOT
./cyberai host-setup                      # VirtualBox must already be installed
./cyberai doctor
# then EITHER (fast) copy an .ova release and:  ./cyberai import <ova>
# OR (from source): download the Kali .7z into downloads/kali/, then:
#   ./cyberai base import && ./cyberai golden build
./cyberai rag up && ./cyberai rag update live
```
Requirements on the new host: x86-64, VT-x enabled, VirtualBox 7.1+, ≥16 GB RAM, ~200 GB free.
