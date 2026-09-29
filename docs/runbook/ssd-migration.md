# Move everything to an external SSD (later)

Only `CYBERVM_ROOT` changes. Procedure (nothing destructive until the last step):
```
1. Stop all VMs:            ./cybervm list ; ./cybervm stop <each>
2. Back up first:           ./cybervm backup /media/$USER/HDD
3. Format+mount the SSD (ext4). Confirm the device with lsblk BEFORE mkfs.
4. Move registered VMs:     VBoxManage movevm CyberVM-Kali-Base   --type basic --folder /media/$USER/SSD/CyberVM-AI/images/base
                            VBoxManage movevm CyberVM-Kali-Golden --type basic --folder /media/$USER/SSD/CyberVM-AI/images/golden
5. rsync data dirs:         rsync -a downloads models rag /media/$USER/SSD/CyberVM-AI/
6. Edit .cybervm.env:       CYBERVM_ROOT="/media/$USER/SSD/CyberVM-AI"
7. Re-run:                  ./cybervm host-setup   (rebinds Ollama models path)
8. Verify:                  ./cybervm doctor
9. Only then delete the old copies.
```
Optional: symlink `~/Personal/CyberVM-AI -> /media/$USER/SSD/CyberVM-AI` so paths stay familiar.
